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

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lidl_gc_v4');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  String dbPath() => '${tmpDir.path}/test.db';

  /// The actual SQLite file [openCardDatabase] derives from a directory path.
  String dbFilePath() => p.join(dbPath(), 'lidl_gift_card.db');

  /// Creates a database with the pre-v4 (v3) schema holding one card row,
  /// so the v3→v4 upgrade path is exercised for real.
  Future<void> createV3DatabaseWithCard() async {
    await Directory(dbPath()).create(recursive: true);
    final db = await databaseFactory.openDatabase(dbFilePath());
    await db.execute('''
      CREATE TABLE cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cardNumber TEXT NOT NULL,
        pin TEXT NOT NULL,
        nickname TEXT,
        balance TEXT NOT NULL DEFAULT '0',
        currency TEXT NOT NULL DEFAULT 'CHF',
        status TEXT NOT NULL DEFAULT 'unbekannt',
        expiryDate TEXT,
        lastRefreshed INTEGER,
        isManuallyEdited INTEGER NOT NULL DEFAULT 0,
        barcodeFormat TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute(
      "INSERT INTO cards (cardNumber, pin, balance, currency) "
      "VALUES ('9840281900485721', '4920', '45.0', 'CHF')",
    );
    await db.execute('PRAGMA user_version = 3');
    await db.close();
  }

  group('database v4', () {
    test('fresh install creates v4 schema with new columns and transactions',
        () async {
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      final columns = (await db.rawQuery('PRAGMA table_info(cards)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, containsAll(['initialBalance', 'isFavorite']));

      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
          .map((row) => row['name'] as String)
          .toSet();
      expect(tables, contains('transactions'));
    });

    test('v3 database upgrades in place and keeps card rows', () async {
      await createV3DatabaseWithCard();
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      // v3 now upgrades through v4 all the way to the current schema v5.
      expect(await db.getVersion(), 5);
      final rows = await db.query('cards');
      expect(rows, hasLength(1));
      expect(rows.first['cardNumber'], '9840281900485721');
      expect(rows.first['isFavorite'], 0);

      final columns = (await db.rawQuery('PRAGMA table_info(cards)'))
          .map((row) => row['name'] as String)
          .toSet();
      expect(columns, containsAll(['initialBalance', 'isFavorite']));

      final dao = CardDao(db);
      final card = await dao.getById(rows.first['id'] as int);
      expect(card, isNotNull);
      expect(card!.balance, 45.0);
      expect(card.initialBalance, isNull);
      expect(card.isFavorite, isFalse);
    });
  });

  group('GiftCard v4 fields', () {
    test('db map round-trips initialBalance and isFavorite', () {
      final card = GiftCard(
        id: 1,
        cardNumber: '9840281900485721',
        pin: '4920',
        balance: 45,
        initialBalance: 50,
        isFavorite: true,
      );
      final restored = GiftCard.fromDbMap(card.toDbMap());
      expect(restored.initialBalance, 50);
      expect(restored.isFavorite, isTrue);
    });

    test('copyWith can clear initialBalance and toggle favorite', () {
      final card = GiftCard(
        id: 1,
        cardNumber: '9840281900485721',
        pin: '4920',
        balance: 10,
        initialBalance: 50,
      );
      final cleared = card.copyWith(clearInitialBalance: true);
      expect(cleared.initialBalance, isNull);
      expect(cleared.copyWith(isFavorite: true).isFavorite, isTrue);
    });

    test('usageRatio is null without an initial amount and clamped otherwise',
        () {
      final noInitial = GiftCard(
        id: 1,
        cardNumber: '9840281900485721',
        pin: '4920',
        balance: 10,
      );
      expect(noInitial.usageRatio, isNull);

      final card = GiftCard(
        id: 1,
        cardNumber: '9840281900485721',
        pin: '4920',
        balance: 25,
        initialBalance: 50,
      );
      expect(card.usageRatio, 0.5);
      expect(card.copyWith(balance: 100).usageRatio, 1.0);
      expect(card.copyWith(balance: 0).usageRatio, 0.0);
    });
  });

  group('TransactionDao', () {
    late Database db;
    late CardDao cardDao;
    late TransactionDao transactionDao;
    late int cardId;

    setUp(() async {
      db = await openCardDatabase(path: dbPath());
      cardDao = CardDao(db);
      transactionDao = TransactionDao(db);
      cardId = await cardDao.insert(GiftCard.draft(
        cardNumber: '9840281900485721',
        pin: '4920',
      ));
    });

    tearDown(() async {
      await db.close();
    });

    CardTransaction tx(CardTransactionType type, {double? amount}) {
      return CardTransaction(
        cardId: cardId,
        type: type,
        amount: amount,
        balanceAfter: amount,
        note: type == CardTransactionType.edit ? 'manual' : null,
        createdAt: DateTime(2026, 11, 13, 10).millisecondsSinceEpoch,
      );
    }

    test('insert and listForCard round-trip newest first', () async {
      await transactionDao.insert(tx(CardTransactionType.activation, amount: 50));
      await transactionDao.insert(tx(CardTransactionType.spend, amount: -5));

      final rows = await transactionDao.listForCard(cardId);
      expect(rows, hasLength(2));
      expect(rows.first.type, CardTransactionType.spend);
      expect(rows.first.amount, -5);
      expect(rows.last.type, CardTransactionType.activation);
      expect(rows.last.amount, 50);
      expect(rows.last.note, isNull);
    });

    test('listForCard only returns rows of the given card', () async {
      final otherCard = await cardDao.insert(GiftCard.draft(
        cardNumber: '1111222233334444',
        pin: '1111',
      ));
      await transactionDao.insert(tx(CardTransactionType.activation, amount: 50));
      await transactionDao.insert(CardTransaction(
        cardId: otherCard,
        type: CardTransactionType.activation,
        amount: 10,
        createdAt: 1,
      ));

      expect(await transactionDao.listForCard(cardId), hasLength(1));
      expect(await transactionDao.listForCard(otherCard), hasLength(1));
    });

    test('deleteForCard and deleteAll remove history rows', () async {
      await transactionDao.insert(tx(CardTransactionType.activation, amount: 50));
      await transactionDao.deleteForCard(cardId);
      expect(await transactionDao.listForCard(cardId), isEmpty);

      await transactionDao.insert(tx(CardTransactionType.spend, amount: -1));
      await transactionDao.deleteAll();
      expect(await transactionDao.listForCard(cardId), isEmpty);
    });

    test('encrypted session stores ciphertext and reads it back', () async {
      final crypto = CardCrypto(defaultIterations: 1000);
      final config = await crypto.setup('4321');
      await crypto.unlock('4321', config);
      addTearDown(crypto.lock);

      final encryptedDao = TransactionDao(db, crypto: crypto);
      await encryptedDao.insert(tx(CardTransactionType.edit, amount: 12.5));

      // Raw row holds ciphertext, not plaintext numbers.
      final raw = await db.query('transactions', limit: 1);
      expect(raw.first['amount'] as String, startsWith('enc1:'));

      final rows = await encryptedDao.listForCard(cardId);
      expect(rows, hasLength(1));
      expect(rows.first.amount, 12.5);
      expect(rows.first.balanceAfter, 12.5);
      expect(rows.first.note, 'manual');
    });
  });

  group('CardDao with crypto', () {
    test('initialBalance round-trips encrypted at rest', () async {
      final db = await openCardDatabase(path: dbPath());
      addTearDown(db.close);

      final crypto = CardCrypto(defaultIterations: 1000);
      final config = await crypto.setup('1234');
      await crypto.unlock('1234', config);
      addTearDown(crypto.lock);

      final dao = CardDao(db, crypto: crypto);
      final id = await dao.insert(GiftCard(
        id: null,
        cardNumber: '9840281900485721',
        pin: '4920',
        balance: 45,
        initialBalance: 50,
      ));

      final raw = await db.query('cards', where: 'id = ?', whereArgs: [id]);
      expect(raw.first['initialBalance'] as String, startsWith('enc1:'));

      final card = await dao.getById(id);
      expect(card!.balance, 45);
      expect(card.initialBalance, 50);
    });
  });
}
