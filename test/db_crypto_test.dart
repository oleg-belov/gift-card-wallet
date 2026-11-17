import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/db/database.dart';
import 'package:lidl_gift_card/models/card_transaction.dart';
import 'package:lidl_gift_card/models/gift_card.dart';
import 'package:lidl_gift_card/services/crypto_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmpDir;
  late Database db;
  late CardCrypto crypto;
  final today = DateTime(2026, 11, 13);

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lidl_gc_crypto_test');
    db = await openCardDatabase(path: '${tmpDir.path}/test.db');
    crypto = CardCrypto(defaultIterations: 1000);
  });

  tearDown(() async {
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  GiftCard card({
    required String number,
    required String pin,
    double balance = 100,
    String? nickname,
  }) {
    return GiftCard(
      id: null,
      cardNumber: number,
      pin: pin,
      nickname: nickname,
      balance: balance,
    );
  }

  test('DAO with an unlocked session stores ciphertext at rest and decrypts '
      'transparently', () async {
    final config = await crypto.setup('1234', iterations: 1000);
    await saveCryptoConfig(db, config);

    final dao = CardDao(db, crypto: crypto);
    final id = await dao.insert(
      card(
        number: '1234567890',
        pin: '9876',
        balance: 45.5,
        nickname: 'Birthday',
      ),
    );

    // Raw row: sensitive columns are ciphertext, metadata stays plaintext.
    final raw = (await db.query('cards', where: 'id = ?', whereArgs: [id]))
        .single;
    expect(CardCrypto.isEncrypted(raw['cardNumber'] as String), isTrue);
    expect(CardCrypto.isEncrypted(raw['pin'] as String), isTrue);
    expect(CardCrypto.isEncrypted(raw['nickname'] as String), isTrue);
    expect(CardCrypto.isEncrypted(raw['balance'] as String), isTrue);
    expect(CardCrypto.isEncrypted(raw['expiryDate'] as String?), isFalse);
    expect(raw['lastRefreshed'], isNull);
    expect(raw['isManuallyEdited'], 0);
    expect((raw['cardNumber'] as String), isNot(contains('1234567890')));

    // Through the DAO everything reads back in plaintext.
    final loaded = await dao.getById(id);
    expect(loaded!.cardNumber, '1234567890');
    expect(loaded.pin, '9876');
    expect(loaded.nickname, 'Birthday');
    expect(loaded.balance, 45.5);
  });

  test('encrypted mode still supports getByCardNumber and filters', () async {
    await crypto.setup('1234', iterations: 1000);
    final dao = CardDao(db, crypto: crypto);
    await dao.insert(card(number: 'AAA', pin: '1', balance: 10));
    await dao.insert(card(number: 'BBB', pin: '2', balance: 0));

    final found = await dao.getByCardNumber('AAA');
    expect(found, isNotNull);
    expect(found!.pin, '1');
    expect(await dao.getByCardNumber('nope'), isNull);

    // Never-synced zero-balance cards stay refreshable (existing lifecycle
    // rule), the encrypted store must not change that.
    expect(
      (await dao.getRefreshable(today)).map((c) => c.cardNumber),
      ['AAA', 'BBB'],
    );
  });

  test('writes fail while locked, resume after unlock', () async {
    final config = await crypto.setup('1234', iterations: 1000);
    final dao = CardDao(db, crypto: crypto);

    crypto.lock();
    expect(
      () => dao.insert(card(number: 'X', pin: '1')),
      throwsA(isA<StateError>()),
    );

    await crypto.unlock('1234', config);
    final id = await dao.insert(card(number: 'X', pin: '1'));
    expect((await dao.getById(id))!.cardNumber, 'X');
  });

  test('enableEncryption migrates pre-existing plaintext rows', () async {
    // Simulate an old install: plaintext rows, no crypto config.
    final dao = CardDao(db);
    await dao.insert(card(number: 'PLAIN1', pin: '1111', balance: 25));
    await dao.insert(card(number: 'PLAIN2', pin: '2222', balance: 0));
    expect(await readCryptoConfig(db), isNull);

    await enableEncryption(db, crypto, '4321');
    final config = await readCryptoConfig(db);
    expect(config, isNotNull);

    // Rows are now ciphertext at rest...
    for (final raw in await db.query('cards')) {
      expect(CardCrypto.isEncrypted(raw['cardNumber'] as String), isTrue);
      expect(CardCrypto.isEncrypted(raw['pin'] as String), isTrue);
      expect(CardCrypto.isEncrypted(raw['balance'] as String), isTrue);
    }

    // ...and decrypt correctly through an encrypted DAO.
    final encryptedDao = CardDao(db, crypto: crypto);
    final all = await encryptedDao.getAll();
    expect(all.map((c) => c.cardNumber), ['PLAIN1', 'PLAIN2']);
    expect(all[0].pin, '1111');
    expect(all[0].balance, 25);
  });

  test('enableEncryption refuses to run on already encrypted rows', () async {
    final dao = CardDao(db);
    await dao.insert(card(number: 'PLAIN', pin: '1111', balance: 25));

    final config = await enableEncryption(db, crypto, '4321');

    // Simulate a foreign/manual write path breaking the invariant: encrypted
    // rows must only ever exist together with a stored config.
    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: [kSaltSettingKey],
    );

    await expectLater(
      enableEncryption(db, crypto, '4321'),
      throwsA(isA<StateError>()),
    );

    // The transaction rolled back: the data is untouched and still decrypts
    // under the original key.
    final restoredConfig = await readCryptoConfig(db);
    expect(restoredConfig, isNull); // config row was deleted, not rewritten
    final fresh = CardCrypto(defaultIterations: 1000);
    await fresh.unlock('4321', config);
    final all = await CardDao(db, crypto: fresh).getAll();
    expect(all.single.cardNumber, 'PLAIN');
    expect(all.single.pin, '1111');
  });

  test('changeCardPin re-encrypts all rows under the new PIN', () async {
    final dao = CardDao(db);
    await dao.insert(card(number: 'REPIN', pin: '1111', balance: 30));
    // Pre-existing activity log row: must follow the PIN change as well.
    await TransactionDao(db).insert(CardTransaction(
      cardId: 1,
      type: CardTransactionType.spend,
      amount: -10,
      balanceAfter: 20,
      note: 'Kiosk',
      createdAt: 1731500000000,
    ));
    final firstConfig = await enableEncryption(db, crypto, '1111');

    final newConfig = await changeCardPin(db, crypto, '1111', '2222');
    expect(newConfig.saltBase64, isNot(firstConfig.saltBase64));

    // Card data is readable under the new key.
    final all = await CardDao(db, crypto: crypto).getAll();
    expect(all.single.cardNumber, 'REPIN');
    expect(all.single.pin, '1111');
    expect(all.single.balance, 30);

    // Transaction rows are ciphertext at rest and decrypt under the new key.
    final rawTxn = (await db.query('transactions')).single;
    expect(CardCrypto.isEncrypted(rawTxn['amount'] as String), isTrue);
    expect(CardCrypto.isEncrypted(rawTxn['note'] as String), isTrue);
    final txns = await TransactionDao(db, crypto: crypto)
        .listForCard(all.single.id!);
    expect(txns.single.amount, -10);
    expect(txns.single.balanceAfter, 20);
    expect(txns.single.note, 'Kiosk');

    // A fresh session with the old PIN can no longer unlock.
    final fresh = CardCrypto(defaultIterations: 1000);
    await expectLater(
      fresh.unlock('1111', newConfig),
      throwsA(isA<WrongPinException>()),
    );
    await fresh.unlock('2222', newConfig);
    expect(
      await CardDao(db, crypto: fresh).getById(all.single.id!),
      isNotNull,
    );
  });

  test('changeCardPin rejects a wrong current PIN and leaves data intact',
      () async {
    final dao = CardDao(db);
    await dao.insert(card(number: 'SAFE', pin: '1111', balance: 30));
    await enableEncryption(db, crypto, '1111');

    await expectLater(
      changeCardPin(db, crypto, '0000', '2222'),
      throwsA(isA<WrongPinException>()),
    );

    // The verifier still matches the old PIN and data decrypts fine.
    final config = await readCryptoConfig(db);
    final fresh = CardCrypto(defaultIterations: 1000);
    await fresh.unlock('1111', config!);
    final all = await CardDao(db, crypto: fresh).getAll();
    expect(all.single.cardNumber, 'SAFE');
    expect(all.single.balance, 30);
  });

  test('schema v2 (REAL balance) migrates to v3 without data loss',
      () async {
    // Build a v1 database by hand in a "databases" directory (the `path`
    // parameter of openCardDatabase is a directory, see join() below),
    // then let openDatabase upgrade it.
    final upgradeDir = '${tmpDir.path}/databases';
    Directory(upgradeDir).createSync();
    final v1Path = p.join(upgradeDir, 'lidl_gift_card.db');
    final v1 = await openDatabase(v1Path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE cards (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cardNumber TEXT NOT NULL,
          pin TEXT NOT NULL,
          nickname TEXT,
          balance REAL NOT NULL DEFAULT 0,
          currency TEXT NOT NULL DEFAULT 'CHF',
          status TEXT NOT NULL DEFAULT 'unbekannt',
          expiryDate TEXT,
          lastRefreshed INTEGER,
          isManuallyEdited INTEGER NOT NULL DEFAULT 0,
          barcodeFormat TEXT
        )
      ''');
      await db.insert('cards', {
        'cardNumber': 'LEGACY',
        'pin': '4321',
        'balance': 12.5,
        'isManuallyEdited': 0,
      });
    });
    await v1.close();

    final upgraded = await openCardDatabase(path: upgradeDir);
    final raw = (await upgraded.query('cards')).single;
    expect(raw['cardNumber'], 'LEGACY');
    expect(raw['balance'], '12.5'); // TEXT affinity converts numerics.

    final loaded = await CardDao(upgraded).getAll();
    expect(loaded.single.cardNumber, 'LEGACY');
    expect(loaded.single.balance, 12.5);
    await upgraded.close();
  });
}
