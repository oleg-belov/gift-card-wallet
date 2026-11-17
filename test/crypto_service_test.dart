import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/services/crypto_service.dart';

void main() {
  // Low iteration count keeps the pure-Dart PBKDF2 fast in tests; production
  // uses kDefaultKdfIterations via the platform implementation.
  late CardCrypto crypto;

  setUp(() {
    crypto = CardCrypto(defaultIterations: 1000);
  });

  test('setup returns a config and unlocks the session', () async {
    final config = await crypto.setup('1234', iterations: 1000);

    expect(crypto.isUnlocked, isTrue);
    expect(config.saltBase64, isNotEmpty);
    expect(config.verifier, startsWith(kCiphertextPrefix));
    expect(config.iterations, 1000);
  });

  test('unlock with the correct PIN verifies and unlocks', () async {
    final config = await crypto.setup('1234', iterations: 1000);
    crypto.lock();
    expect(crypto.isUnlocked, isFalse);

    await crypto.unlock('1234', config);
    expect(crypto.isUnlocked, isTrue);
  });

  test('unlock with a wrong PIN throws WrongPinException and stays locked',
      () async {
    final config = await crypto.setup('1234', iterations: 1000);
    crypto.lock();

    expect(
      () => crypto.unlock('9999', config),
      throwsA(isA<WrongPinException>()),
    );
    expect(crypto.isUnlocked, isFalse);
  });

  test('field encryption round-trips', () async {
    await crypto.setup('1234', iterations: 1000);

    const plaintext = '12345678901234567890';
    final cipher = await crypto.encryptField(plaintext);

    expect(CardCrypto.isEncrypted(cipher), isTrue);
    expect(cipher, isNot(contains(plaintext)));
    expect(await crypto.decryptField(cipher), plaintext);
  });

  test('decryptField passes legacy plaintext through unchanged', () async {
    await crypto.setup('1234', iterations: 1000);

    expect(await crypto.decryptField('plain-value'), 'plain-value');
    expect(await crypto.decryptFieldOrNull(null), isNull);
    expect(await crypto.decryptFieldOrNull('legacy'), 'legacy');
  });

  test('tampered ciphertext fails authentication', () async {
    await crypto.setup('1234', iterations: 1000);

    final cipher = await crypto.encryptField('secret');
    // Corrupt the tail of the base64 payload (inside the MAC).
    final flipped =
        '${cipher.substring(0, cipher.length - 2)}${cipher.endsWith('AA') ? 'bb' : 'AA'}';

    expect(
      () => crypto.decryptField(flipped),
      throwsA(anyOf(
        isA<SecretBoxAuthenticationError>(),
        isA<FormatException>(),
      )),
    );
  });

  test('encrypt/decrypt without an unlocked session throws', () async {
    expect(
      () => crypto.encryptField('x'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => crypto.decryptField('${kCiphertextPrefix}abc'),
      throwsA(isA<StateError>()),
    );
  });

  test('each encryption uses a fresh nonce', () async {
    await crypto.setup('1234', iterations: 1000);

    final a = await crypto.encryptField('same');
    final b = await crypto.encryptField('same');
    expect(a, isNot(b));
  });

  test('CryptoConfig round-trips through settings map', () async {
    final config = await crypto.setup('1234', iterations: 12345);

    final restored = CryptoConfig.fromSettings({
      kSaltSettingKey: config.saltBase64,
      kVerifierSettingKey: config.verifier,
      kIterationsSettingKey: '${config.iterations}',
    });
    expect(restored, isNotNull);
    expect(restored!.saltBase64, config.saltBase64);
    expect(restored.iterations, 12345);

    // Missing iteration entry falls back to the default.
    final withoutIterations = CryptoConfig.fromSettings({
      kSaltSettingKey: config.saltBase64,
      kVerifierSettingKey: config.verifier,
    });
    expect(withoutIterations!.iterations, kDefaultKdfIterations);
  });

  test('a key derived for one PIN cannot decrypt the other PINs data',
      () async {
    final configA = await crypto.setup('1111', iterations: 1000);
    final cipher = await crypto.encryptField('belongs-to-1111');

    crypto.lock();
    // PIN 2222 has a different salt: unlocking A's config with it must fail.
    expect(
      () => crypto.unlock('2222', configA),
      throwsA(isA<WrongPinException>()),
    );
    expect(crypto.isUnlocked, isFalse);
    expect(CardCrypto.isEncrypted(cipher), isTrue);
  });
}
