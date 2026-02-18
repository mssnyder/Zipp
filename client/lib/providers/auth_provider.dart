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
    } finally {
      _setLoading(false);
    }
    // No password available — can only load local key.
    if (_user != null) {
      try {
        await _ensureKeyPair();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    _setError(null);
    try {
      _user = await _api.login(email: email, password: password);
    } on ApiException catch (e) {
      _setError(e.message);
      rethrow;
    } finally {
      _setLoading(false);
    }
    // Key management is best-effort — must not invalidate the session
    try {
      _loginPassword = password;
      await _ensureKeyPair();
    } catch (_) {} finally {
      _loginPassword = null;
    }
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
    _user = null;
    _keyPair = null;
    _loginPassword = null;
    await StorageService.clearSession();
    notifyListeners();
  }

  /// Core key management logic.
  ///
  /// 1. Try loading local key from secure storage.
  /// 2. If no local key AND password available AND server has encrypted backup:
  ///    download + decrypt backup, store locally.
  /// 3. If still no local key: generate a new key pair.
  /// 4. If local public key differs from server's: upload public key.
  ///    If password available, also encrypt + upload private key backup.
  Future<void> _ensureKeyPair() async {
    // Step 1: try local key
    _keyPair = await CryptoService.loadKeyPair();

    // Step 2: try restoring from server backup (only if we have a password)
    if (_keyPair == null && _loginPassword != null && _user != null) {
      _keyPair = await _tryRestoreFromBackup(_loginPassword!);
    }

    // Step 3: generate new key pair if still no key
    if (_keyPair == null) {
      _keyPair = await CryptoService.generateKeyPair();
    }

    // Step 4: sync with server
    final localPub = await CryptoService.getPublicKeyBase64(_keyPair!);
    if (_user?.publicKey != localPub) {
      if (_loginPassword != null) {
        // Encrypt and upload both public key and private key backup
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
    } else if (_loginPassword != null && _user?.encryptedPrivateKey == null) {
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

  /// Try to download and decrypt the private key backup from the server.
  Future<SimpleKeyPair?> _tryRestoreFromBackup(String password) async {
    if (_user == null) return null;
    try {
      final keys = await _api.fetchOwnKeys(_user!.id);
      final enc = keys['encryptedPrivateKey'];
      final salt = keys['keySalt'];
      final nonce = keys['keyNonce'];
      if (enc == null || salt == null || nonce == null) return null;

      final privBytes = await CryptoService.decryptPrivateKey(enc, salt, nonce, password);
      if (privBytes == null) return null;

      // Store locally and load as key pair
      await StorageService.setPrivateKey(base64Url.encode(privBytes));
      return await CryptoService.loadKeyPair();
    } catch (_) {
      return null;
    }
  }

  /// Manual restore for settings UI — user enters password to restore key from backup.
  Future<bool> restoreKeyFromBackup(String password) async {
    if (_user == null) return false;
    try {
      final kp = await _tryRestoreFromBackup(password);
      if (kp == null) return false;
      _keyPair = kp;

      // Sync public key with server if needed
      final localPub = await CryptoService.getPublicKeyBase64(_keyPair!);
      if (_user?.publicKey != localPub) {
        final privBytes = await _keyPair!.extractPrivateKeyBytes();
        final backup = await CryptoService.encryptPrivateKey(privBytes, password);
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
