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
    // Key upload is best-effort: a failure must not log the user out
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
    // Key upload is best-effort: a failure must not invalidate the session
    try {
      await _ensureKeyPair();
    } catch (_) {}
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
    await StorageService.clearSession();
    notifyListeners();
  }

  Future<void> _ensureKeyPair() async {
    _keyPair = await CryptoService.loadKeyPair();
    if (_keyPair == null) {
      _keyPair = await CryptoService.generateKeyPair();
      final pubKey = await CryptoService.getPublicKeyBase64(_keyPair!);
      await _api.uploadPublicKey(pubKey);
    } else if (_user?.publicKey == null) {
      // Key exists locally but not on server — upload it
      final pubKey = await CryptoService.getPublicKeyBase64(_keyPair!);
      await _api.uploadPublicKey(pubKey);
    }
  }

  void updateUser(ZippUser updated) {
    _user = updated;
    notifyListeners();
  }
}
