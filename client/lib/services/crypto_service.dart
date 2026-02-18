import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
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
  static Future<({String ciphertext, String nonce})> encrypt(
    String plaintext,
    SimpleKeyPair myKp,
    String recipientPublicKeyBase64,
  ) async {
    final recipientPub = SimplePublicKey(
      base64Url.decode(recipientPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final aesKey = await _deriveKey(myKp, recipientPub);
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: aesKey,
    );
    final combined = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return (
      ciphertext: base64Url.encode(combined),
      nonce: base64Url.encode(secretBox.nonce),
    );
  }

  /// Decrypt ciphertext. Returns plaintext string or null on failure.
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
}
