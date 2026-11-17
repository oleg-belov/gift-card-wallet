import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Marks a value in the database as ciphertext produced by [CardCrypto].
/// Values without this prefix are legacy plaintext and are passed through
/// unchanged on read, so rows written before encryption existed keep working.
const String kCiphertextPrefix = 'enc1:';

/// Default PBKDF2-HMAC-SHA256 iteration count used when creating a new
/// PIN. The value actually used is stored with the crypto config so it can
/// be raised in a future version without breaking existing data.
const int kDefaultKdfIterations = 200000;

/// Settings-table keys (see `getSetting`/`setSetting` in db/database.dart).
const String kSaltSettingKey = 'crypto.salt';
const String kVerifierSettingKey = 'crypto.verifier';
const String kIterationsSettingKey = 'crypto.kdfIterations';

/// Fixed plaintext encrypted under the derived key and stored in the
/// settings table. Decrypting it proves the entered PIN was correct.
const String _verifierPlaintext = 'lidl-gift-card-crypto-v1';

const int _saltBytes = 16;
const int _nonceBytes = 12;
const int _macBytes = 16;

/// Thrown when a PIN does not match the stored crypto config.
class WrongPinException implements Exception {
  WrongPinException();

  @override
  String toString() => 'WrongPinException';
}

/// Stored parameters of the PIN-derived encryption. Everything except the
/// PIN itself lives in the `settings` table.
class CryptoConfig {
  const CryptoConfig({
    required this.saltBase64,
    required this.verifier,
    required this.iterations,
  });

  /// Reads the config from the settings rows, or null when encryption has
  /// never been set up.
  static CryptoConfig? fromSettings(Map<String, String?> settings) {
    final salt = settings[kSaltSettingKey];
    final verifier = settings[kVerifierSettingKey];
    if (salt == null || verifier == null) return null;
    final iterations =
        int.tryParse(settings[kIterationsSettingKey] ?? '') ??
        kDefaultKdfIterations;
    return CryptoConfig(
      saltBase64: salt,
      verifier: verifier,
      iterations: iterations,
    );
  }

  final String saltBase64;
  final String verifier;
  final int iterations;
}

/// App-PIN-derived field encryption for the card database.
///
/// The key is derived with PBKDF2-HMAC-SHA256 from the 4-digit app PIN and a
/// random salt, then kept in memory only while the app is unlocked
/// ([isUnlocked]). Every encrypted field is AES-256-GCM with its own random
/// nonce, serialized as `enc1:` + base64(nonce | cipherText | mac).
class CardCrypto {
  CardCrypto({this.defaultIterations = kDefaultKdfIterations});

  final AesGcm _aesGcm = AesGcm.with256bits();

  /// Iteration count used when creating a NEW config (setup / PIN change).
  final int defaultIterations;

  SecretKey? _sessionKey;

  /// True while a PIN-derived key is held in memory.
  bool get isUnlocked => _sessionKey != null;

  /// Forgets the derived key. All later encrypt/decrypt calls throw until
  /// the correct PIN is entered again.
  void lock() {
    _sessionKey = null;
  }

  /// Creates a new crypto config for [pin], stores the derived key in memory
  /// and returns the config to persist. Used on first-run setup and when
  /// choosing a new PIN (which replaces the whole config).
  Future<CryptoConfig> setup(String pin, {int? iterations}) async {
    final salt = _randomBytes(_saltBytes);
    final key = await _deriveKey(pin, salt, iterations ?? defaultIterations);
    _sessionKey = key;
    final verifier = await _encrypt(key, _verifierPlaintext);
    return CryptoConfig(
      saltBase64: base64Encode(salt),
      verifier: verifier,
      iterations: iterations ?? defaultIterations,
    );
  }

  /// Derives the key for [pin] and checks it against the stored verifier.
  /// On success the key is kept in memory for field encryption. Throws
  /// [WrongPinException] when the PIN is wrong.
  Future<void> unlock(String pin, CryptoConfig config) async {
    final salt = base64Decode(config.saltBase64);
    final key = await _deriveKey(pin, salt, config.iterations);
    try {
      await _decrypt(key, config.verifier);
    } on SecretBoxAuthenticationError {
      lock();
      throw WrongPinException();
    }
    _sessionKey = key;
  }

  /// Encrypts [plaintext] for a database column. Requires an unlocked
  /// session.
  Future<String> encryptField(String plaintext) async {
    final key = _requireKey();
    return _encrypt(key, plaintext);
  }

  /// Decrypts a stored column value. Values without the `enc1:` prefix are
  /// returned unchanged (legacy plaintext rows).
  Future<String> decryptField(String stored) async {
    if (!stored.startsWith(kCiphertextPrefix)) return stored;
    final key = _requireKey();
    return _decrypt(key, stored);
  }

  /// Returns null when the value is not ciphertext (legacy plaintext rows).
  Future<String?> decryptFieldOrNull(String? stored) async {
    if (stored == null) return null;
    return decryptField(stored);
  }

  /// True when [stored] carries ciphertext of this format.
  static bool isEncrypted(String? stored) =>
      stored != null && stored.startsWith(kCiphertextPrefix);

  SecretKey _requireKey() {
    final key = _sessionKey;
    if (key == null) {
      throw StateError('CardCrypto is locked: unlock with the PIN first.');
    }
    return key;
  }

  Future<SecretKey> _deriveKey(String pin, List<int> salt, int iterations) async {
    // PBKDF2 with 200k iterations blocks for several seconds — long enough
    // to trip the Android ANR dialog when run on the UI isolate. Derive in a
    // background isolate and hand the raw key bytes back.
    final keyBytes = await Isolate.run(() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );
      final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
      return key.extractBytes();
    });
    return SecretKey(keyBytes);
  }

  Future<String> _encrypt(SecretKey key, String plaintext) async {
    final box = await _aesGcm.encryptString(plaintext, secretKey: key);
    final packed = Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    return kCiphertextPrefix + base64Encode(packed);
  }

  Future<String> _decrypt(SecretKey key, String stored) async {
    final packed = base64Decode(stored.substring(kCiphertextPrefix.length));
    if (packed.length < _nonceBytes + _macBytes) {
      throw const FormatException('Ciphertext too short');
    }
    final box = SecretBox(
      packed.sublist(_nonceBytes, packed.length - _macBytes),
      nonce: packed.sublist(0, _nonceBytes),
      mac: Mac(packed.sublist(packed.length - _macBytes)),
    );
    return _aesGcm.decryptString(box, secretKey: key);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
