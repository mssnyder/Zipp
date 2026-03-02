import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    lOptions: LinuxOptions(),
    wOptions: WindowsOptions(),
  );

  static const _privateKeyKey = 'zipp_private_key';
  static const _sessionKey = 'zipp_session_cookie';

  // Private key (X25519) — stored in platform secure storage
  static Future<String?> getPrivateKey() => _storage.read(key: _privateKeyKey);
  static Future<void> setPrivateKey(String key) => _storage.write(key: _privateKeyKey, value: key);
  static Future<void> deletePrivateKey() => _storage.delete(key: _privateKeyKey);

  // Session cookie — stored in secure storage too
  static Future<String?> getSessionCookie() => _storage.read(key: _sessionKey);
  static Future<void> setSessionCookie(String cookie) => _storage.write(key: _sessionKey, value: cookie);
  static Future<void> clearSession() => _storage.delete(key: _sessionKey);

  // Lightweight prefs
  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<bool> getOnboarded() async {
    final p = await _prefs;
    return p.getBool('onboarded') ?? false;
  }

  static Future<void> setOnboarded() async {
    final p = await _prefs;
    await p.setBool('onboarded', true);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
    final p = await _prefs;
    await p.clear();
  }
}