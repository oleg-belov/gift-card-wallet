import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/db/database.dart';
import 'package:lidl_gift_card/models/gift_card.dart';
import 'package:lidl_gift_card/services/crypto_service.dart';
import 'package:lidl_gift_card/state/providers.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lidl_gc_v5');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  String dbPath() => '${tmpDir.path}/test.db';

  /// The actual SQLite file [openCardDatabase] derives from a directory path.
  String dbFilePath() => p.join(dbPath(), 'lidl_gift_card.db');

  /// Creates a v4 database (no barcodeValue column) with one card row so the
  /// v4→v5 upgrade path is exercised for real.
  Future<void> createV4DatabaseWithCard() async {
    await Directory(dbPath()).create(recursive: true);
    final db = await databaseFactory.openDatabase(dbFilePath());
    await db.execute('''
      CREATE TABLE cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cardNumber TEXT NOT NULL,
        pin TEXT NOT NULL,
        nickname TEXT,
        balance TEXT NOT NULL DEFAULT '0',
        initialBalance TEXT,
        currency TEXT NOT NULL DEFAULT 'CHF',
        status TEXT NOT NULL DEFAULT 'unbekannt',
        expiryDate TEXT,
        lastRefreshed INTEGER,
        isManuallyEdited INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        barcodeFormat TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cardId INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount TEXT,
        balanceAfter TEXT,
        note TEXT,
        createdAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
      "INSERT INTO cards (cardNumber, pin, balance, initialBalance, currency)"
      " VALUES ('211224627680296028', '7195', '0.0', '100.0', 'CHF')",
    );
    await db.execute('PRAGMA user_version = 4');
    await db.close();
  }

  group('database v5', () {
    test('fresh install creates the barcodeValue column', () async {
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      final columns = (await db.rawQuery('PRAGMA table_info(cards)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, contains('barcodeValue'));
      expect(await db.getVersion(), 5);
    });

    test('v4 database upgrades in place and keeps card rows', () async {
      await createV4DatabaseWithCard();
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      expect(await db.getVersion(), 5);
      final rows = await db.query('cards');
      expect(rows, hasLength(1));
      expect(rows.first['cardNumber'], '211224627680296028');
      expect(rows.first['initialBalance'], '100.0');

      final columns = (await db.rawQuery('PRAGMA table_info(cards)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, contains('barcodeValue'));

      final dao = CardDao(db);
      final card = await dao.getById(rows.first['id'] as int);
      expect(card, isNotNull);
      expect(card!.initialBalance, 100.0);
      expect(card.barcodeValue, isNull);
    });
  });

  group('barcodeValue at rest', () {
    test('round-trips encrypted under an app PIN', () async {
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      const gs1 = '010406753421013490211224627680296028';
      final crypto = CardCrypto(defaultIterations: 1000);
      final config = await crypto.setup('1234');
      await crypto.unlock('1234', config);
      addTearDown(crypto.lock);

      final dao = CardDao(db, crypto: crypto);
      final id = await dao.insert(GiftCard(
        id: null,
        cardNumber: '211224627680296028',
        pin: '7195',
        barcodeValue: gs1,
      ));

      // The raw row holds ciphertext for the sensitive columns.
      final raw = await db.query('cards', where: 'id = ?', whereArgs: [id]);
      expect(raw.first['cardNumber'] as String, startsWith('enc1:'));
      expect(raw.first['barcodeValue'] as String, startsWith('enc1:'));

      final card = await dao.getById(id);
      expect(card!.cardNumber, '211224627680296028');
      expect(card.barcodeValue, gs1);
      expect(card.checkoutBarcode, gs1);
    });

    test('survives a PIN change (re-encryption includes the column)',
        () async {
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      const gs1 = '010406753421013490211224627680296028';
      final crypto = CardCrypto(defaultIterations: 1000);
      final config = await crypto.setup('1111');
      await crypto.unlock('1111', config);
      addTearDown(crypto.lock);

      final dao = CardDao(db, crypto: crypto);
      final id = await dao.insert(GiftCard(
        id: null,
        cardNumber: '211224627680296028',
        pin: '7195',
        barcodeValue: gs1,
      ));
      // Persist the crypto config — changeCardPin reads it from settings.
      await saveCryptoConfig(db, config);

      await changeCardPin(db, crypto, '1111', '2222');

      final card = await dao.getById(id);
      expect(card!.barcodeValue, gs1);
      expect(card.cardNumber, '211224627680296028');
    });
  });

  group('addCard deduplication', () {
    /// ProviderContainer wired like main(): real database + an unlocked
    /// crypto session (writes throw without one).
    Future<(ProviderContainer, CardCrypto)> makeContainer() async {
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);
      final crypto = CardCrypto(defaultIterations: 1000);
      final config = await crypto.setup('1111');
      await crypto.unlock('1111', config);
      addTearDown(crypto.lock);
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        cryptoProvider.overrideWithValue(crypto),
      ]);
      addTearDown(container.dispose);
      return (container, crypto);
    }

    test('second insert with the same number returns the existing card',
        () async {
      final (container, _) = await makeContainer();

      final notifier = container.read(cardListProvider.notifier);
      final first = await notifier.addCard(GiftCard.draft(
        cardNumber: '211224627680296028',
        pin: '7195',
        nickname: 'Lidl 100',
      ));
      expect(first.isDuplicate, isFalse);
      expect(first.id, isNotNull);

      final second = await notifier.addCard(GiftCard.draft(
        cardNumber: '211224627680296028',
        pin: '7195',
      ));
      expect(second.isDuplicate, isTrue);
      expect(second.id, isNull);
      expect(second.existing!.nickname, 'Lidl 100');

      // Still exactly one row in the database.
      final db = container.read(databaseProvider);
      expect(await db.query('cards'), hasLength(1));
    });

    test('a different card number still inserts normally', () async {
      final (container, _) = await makeContainer();

      final notifier = container.read(cardListProvider.notifier);
      final a = await notifier
          .addCard(GiftCard.draft(cardNumber: '211224627680296028', pin: '7195'));
      final b = await notifier
          .addCard(GiftCard.draft(cardNumber: '9840281900485721', pin: '4920'));
      expect(a.isDuplicate, isFalse);
      expect(b.isDuplicate, isFalse);
      final db = container.read(databaseProvider);
      expect(await db.query('cards'), hasLength(2));
    });
  });
}
