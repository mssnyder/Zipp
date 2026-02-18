import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api;

  ZippUser? _user;
  SimpleKeyPair? _keyPair;
  bool _loading = false;
  String? _error;

  /// Transient password used during login to decrypt/encrypt key backup.
  /// Cleared immediately after use.
  String? _loginPassword;

  AuthProvider(this._api);

  ZippUser? get user => _user;
  SimpleKeyPair? get keyPair => _keyPair;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  void _setLoading(bool v) { _loading = v; notifyListeners(); }
  void _setError(String? e) { _error = e; notifyListeners(); }

  Future<void> tryRestoreSession() async {
    _setLoading(true);
    try {
      _user = await _api.getMe();
    } on ApiException catch (e) {
      if (e.statusCode == 401) _user = null;
    } catch (_) {
      _user = null;
    }
    // Key management runs before we notify listeners, so ChatProvider gets
    // the key pair on the very first notification.
    if (_user != null) {
      try {
        await _ensureKeyPair();
      } catch (_) {}
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    _setError(null);
    try {
      _user = await _api.login(email: email, password: password);
    } on ApiException catch (e) {
      _setError(e.message);
      rethrow;
    }
    // Key management runs before we notify listeners, so ChatProvider gets
    // the key pair on the very first notification after login.
    try {
      _loginPassword = password;
      await _ensureKeyPair();
    } catch (_) {} finally {
      _loginPassword = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<Map<String, String>> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      await _api.register(email: email, username: username, password: password, displayName: displayName);
      return {'message': 'Check your email to verify your account.'};
    } on ApiException catch (e) {
      _setError(e.message);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _api.logout();
    await _api.clearCookies();
    _user = null;
    _keyPair = null;
    _loginPassword = null;
    await StorageService.clearSession();
    await StorageService.deletePrivateKey();
    notifyListeners();
  }

  /// Core key management logic.
  ///
  /// Always fetches key data from the server (the login response doesn't
  /// include key fields). Uses server key data to decide whether to restore
  /// from backup, generate new, or sync.
  Future<void> _ensureKeyPair() async {
    if (_user == null) return;

    // Step 1: try local key
    _keyPair = await CryptoService.loadKeyPair();

    // Step 2: fetch server key data
    final serverKeys = await _api.fetchOwnKeys(_user!.id);
    final serverPubKey = serverKeys['publicKey'];
    final serverEncPriv = serverKeys['encryptedPrivateKey'];
    final serverSalt = serverKeys['keySalt'];
    final serverNonce = serverKeys['keyNonce'];
    final hasServerBackup = serverEncPriv != null && serverSalt != null && serverNonce != null;

    // Step 3: try restoring from server backup (only if we have a password)
    if (_keyPair == null && _loginPassword != null && hasServerBackup) {
      final privBytes = await CryptoService.decryptPrivateKey(
        serverEncPriv, serverSalt, serverNonce, _loginPassword!,
      );
      if (privBytes != null) {
        await StorageService.setPrivateKey(base64Url.encode(privBytes));
        _keyPair = await CryptoService.loadKeyPair();
      }
    }

    // Step 4: generate new key pair only if no backup exists on the server.
    // If a backup exists but we can't decrypt it (no password, or wrong password),
    // leave keyPair null — never overwrite the server key with a new one.
    if (_keyPair == null) {
      if (hasServerBackup) {
        // Backup exists but we couldn't decrypt it — don't generate a new key
        // that would overwrite the backup. User can try again or restore manually.
        return;
      }
      _keyPair = await CryptoService.generateKeyPair();
    }

    // Step 5: sync with server
    final localPub = await CryptoService.getPublicKeyBase64(_keyPair!);
    if (serverPubKey != localPub) {
      if (_loginPassword != null) {
        final privBytes = await _keyPair!.extractPrivateKeyBytes();
        final backup = await CryptoService.encryptPrivateKey(privBytes, _loginPassword!);
        await _api.uploadPublicKey(
          localPub,
          encryptedPrivateKey: backup.encryptedPrivateKey,
          keySalt: backup.keySalt,
          keyNonce: backup.keyNonce,
        );
      } else {
        await _api.uploadPublicKey(localPub);
      }
    } else if (_loginPassword != null && !hasServerBackup) {
      // Key matches server but no backup exists yet — upload backup
      final privBytes = await _keyPair!.extractPrivateKeyBytes();
      final backup = await CryptoService.encryptPrivateKey(privBytes, _loginPassword!);
      await _api.uploadPublicKey(
        localPub,
        encryptedPrivateKey: backup.encryptedPrivateKey,
        keySalt: backup.keySalt,
        keyNonce: backup.keyNonce,
      );
    }
  }

  /// Manual restore for settings UI — user enters password to restore key from backup.
  Future<bool> restoreKeyFromBackup(String password) async {
    if (_user == null) return false;
    try {
      final serverKeys = await _api.fetchOwnKeys(_user!.id);
      final enc = serverKeys['encryptedPrivateKey'];
      final salt = serverKeys['keySalt'];
      final nonce = serverKeys['keyNonce'];
      if (enc == null || salt == null || nonce == null) return false;

      final privBytes = await CryptoService.decryptPrivateKey(enc, salt, nonce, password);
      if (privBytes == null) return false;

      await StorageService.setPrivateKey(base64Url.encode(privBytes));
      _keyPair = await CryptoService.loadKeyPair();
      if (_keyPair == null) return false;

      // Sync public key with server if needed
      final localPub = await CryptoService.getPublicKeyBase64(_keyPair!);
      final serverPub = serverKeys['publicKey'];
      if (serverPub != localPub) {
        final privB = await _keyPair!.extractPrivateKeyBytes();
        final backup = await CryptoService.encryptPrivateKey(privB, password);
        await _api.uploadPublicKey(
          localPub,
          encryptedPrivateKey: backup.encryptedPrivateKey,
          keySalt: backup.keySalt,
          keyNonce: backup.keyNonce,
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateUser(ZippUser updated) {
    _user = updated;
    notifyListeners();
  }
}
