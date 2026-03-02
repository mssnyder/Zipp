import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

/// E2E encryption using X25519 key exchange + AES-256-GCM.
///
/// Flow:
///   1. On first login: generate X25519 key pair, store private key in secure
///      storage, upload public key to server.
///   2. Sending: fetch recipient public key → DH → HKDF → AES-256-GCM encrypt.
///   3. Receiving: load own private key → DH with sender pub key → decrypt.
class CryptoService {
  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  /// Generate a new X25519 key pair and persist private key.
  static Future<SimpleKeyPair> generateKeyPair() async {
    final kp = await _x25519.newKeyPair();
    final privBytes = await kp.extractPrivateKeyBytes();
    await StorageService.setPrivateKey(base64Url.encode(privBytes));
    return kp;
  }

  /// Load key pair from secure storage. Returns null if no key exists.
  static Future<SimpleKeyPair?> loadKeyPair() async {
    final privStr = await StorageService.getPrivateKey();
    if (privStr == null) return null;
    final privBytes = base64Url.decode(privStr);
    return await _x25519.newKeyPairFromSeed(privBytes);
  }

  /// Get the public key bytes (for uploading to server).
  static Future<String> getPublicKeyBase64(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return base64Url.encode(pub.bytes);
  }

  /// Derive shared AES key from DH shared secret using HKDF.
  static Future<SecretKey> _deriveKey(SimpleKeyPair myKp, SimplePublicKey theirPub) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKp,
      remotePublicKey: theirPub,
    );
    return await _hkdf.deriveKey(
      secretKey: shared,
      nonce: Uint8List(0),
      info: utf8.encode('zipp-v1'),
    );
  }

  /// Encrypt plaintext. Returns {ciphertext, nonce} both base64url encoded.
  /// Pass [nonce] to reuse an existing nonce (e.g. for the sender copy).
  static Future<({String ciphertext, String nonce})> encrypt(
    String plaintext,
    SimpleKeyPair myKp,
    String recipientPublicKeyBase64, {
    List<int>? nonce,
  }) async {
    final recipientPub = SimplePublicKey(
      base64Url.decode(recipientPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final aesKey = await _deriveKey(myKp, recipientPub);
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: aesKey,
      nonce: nonce,
    );
    final combined = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return (
      ciphertext: base64Url.encode(combined),
      nonce: base64Url.encode(secretBox.nonce),
    );
  }

  /// Decrypt a message intended for the recipient.
  /// [senderPublicKeyBase64] is the message sender's public key.
  /// Returns null if decryption fails.
  static Future<String?> decrypt(
    String ciphertextB64,
    String nonceB64,
    SimpleKeyPair myKp,
    String senderPublicKeyBase64,
  ) async {
    try {
      final senderPub = SimplePublicKey(
        base64Url.decode(senderPublicKeyBase64),
        type: KeyPairType.x25519,
      );
      final aesKey = await _deriveKey(myKp, senderPub);
      final raw = base64Url.decode(ciphertextB64);
      final mac = Mac(raw.sublist(raw.length - 16));
      final cipherBytes = raw.sublist(0, raw.length - 16);
      final nonce = base64Url.decode(nonceB64);
      final secretBox = SecretBox(cipherBytes, nonce: nonce, mac: mac);
      final plain = await _aesGcm.decrypt(secretBox, secretKey: aesKey);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Decrypt the sender copy of a message (own sent messages).
  /// [senderPublicKeyBase64] is the sender's OWN public key (used when encrypting the copy).
  /// Returns null if decryption fails.
  static Future<String?> decryptForSender(
    String ciphertextB64,
    String nonceB64,
    SimpleKeyPair myKp,
    String senderPublicKeyBase64,
  ) async {
    try {
      final senderPub = SimplePublicKey(
        base64Url.decode(senderPublicKeyBase64),
        type: KeyPairType.x25519,
      );
      final aesKey = await _deriveKey(myKp, senderPub);
      final raw = base64Url.decode(ciphertextB64);
      final mac = Mac(raw.sublist(raw.length - 16));
      final cipherBytes = raw.sublist(0, raw.length - 16);
      final nonce = base64Url.decode(nonceB64);
      final secretBox = SecretBox(cipherBytes, nonce: nonce, mac: mac);
      final plain = await _aesGcm.decrypt(secretBox, secretKey: aesKey);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  // ── Key backup: PBKDF2 + AES-256-GCM wrapping ───────────────────────────

  /// Derive wrapping key bytes using PBKDF2 in an isolate to avoid blocking UI.
  static Future<SecretKey> _deriveWrappingKeyInIsolate(String password, List<int> salt) async {
    final keyBytes = await compute(
      _pbkdf2Isolate,
      _Pbkdf2Params(password, salt),
    );
    return SecretKey(keyBytes);
  }

  /// Encrypt a private key with a password-derived wrapping key.
  /// Returns base64url-encoded encrypted blob, salt, and nonce.
  /// Runs PBKDF2 in an isolate to avoid blocking the UI.
  static Future<({String encryptedPrivateKey, String keySalt, String keyNonce})>
      encryptPrivateKey(List<int> privKeyBytes, String password) async {
    final rng = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));

    final wrappingKey = await _deriveWrappingKeyInIsolate(password, salt);

    final secretBox = await _aesGcm.encrypt(
      privKeyBytes,
      secretKey: wrappingKey,
    );
    final combined = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return (
      encryptedPrivateKey: base64Url.encode(combined),
      keySalt: base64Url.encode(salt),
      keyNonce: base64Url.encode(secretBox.nonce),
    );
  }

  /// Decrypt a private key blob with the user's password.
  /// Returns the raw private key bytes, or null if decryption fails (wrong password).
  static Future<List<int>?> decryptPrivateKey(
    String encryptedB64, String saltB64, String nonceB64, String password,
  ) async {
    try {
      final salt = base64Url.decode(saltB64);
      final wrappingKey = await _deriveWrappingKeyInIsolate(password, salt);
      final raw = base64Url.decode(encryptedB64);
      final mac = Mac(raw.sublist(raw.length - 16));
      final cipherBytes = raw.sublist(0, raw.length - 16);
      final nonce = base64Url.decode(nonceB64);
      final secretBox = SecretBox(cipherBytes, nonce: nonce, mac: mac);
      return await _aesGcm.decrypt(secretBox, secretKey: wrappingKey);
    } catch (_) {
      return null;
    }
  }
}

/// Helper class for passing params to the PBKDF2 isolate.
class _Pbkdf2Params {
  final String password;
  final List<int> salt;
  const _Pbkdf2Params(this.password, this.salt);
}

/// Top-level function for compute() isolate.
/// Returns raw key bytes (`List<int>`) so the result is serializable across isolates.
Future<List<int>> _pbkdf2Isolate(_Pbkdf2Params params) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(params.password)),
    nonce: params.salt,
  );
  return await key.extractBytes();
}