import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/card_transaction.dart';
import '../models/gift_card.dart';
import '../services/crypto_service.dart';

/// Opens (and lazily creates/migrates) the local SQLite database.
Future<Database> openCardDatabase({String? path}) async {
  final dbPath = path ?? await getDatabasesPath();
  return openDatabase(
    join(dbPath, 'lidl_gift_card.db'),
    version: 5,
    onCreate: (db, version) async {
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
          barcodeFormat TEXT,
          barcodeValue TEXT
        )
      ''');
      await _createSettingsTable(db);
      await _createTransactionsTable(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await _createSettingsTable(db);
      }
      if (oldVersion < 3) {
        // Content columns (balance included) are stored as text from v3 on:
        // they hold `enc1:` ciphertext once the app PIN is set up.
        await db.execute('ALTER TABLE cards RENAME TO cards_v2');
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
          INSERT INTO cards (
            id, cardNumber, pin, nickname, balance, currency, status,
            expiryDate, lastRefreshed, isManuallyEdited, barcodeFormat
          )
          SELECT
            id, cardNumber, pin, nickname, balance, currency, status,
            expiryDate, lastRefreshed, isManuallyEdited, barcodeFormat
          FROM cards_v2
        ''');
        await db.execute('DROP TABLE cards_v2');
      }
      if (oldVersion < 4) {
        // v4: initial amount for progress bars, favorites flag and the
        // activity log. initialBalance is TEXT like balance so it can hold
        // ciphertext; isFavorite stays plaintext like isManuallyEdited.
        await db.execute('ALTER TABLE cards ADD COLUMN initialBalance TEXT');
        await db.execute(
          'ALTER TABLE cards ADD COLUMN isFavorite INTEGER NOT NULL DEFAULT 0',
        );
        await _createTransactionsTable(db);
      }
      if (oldVersion < 5) {
        // v5: full barcode payload for GS1-128 voucher codes (AI 01 GTIN +
        // AI 90 card number), encrypted like the card number.
        await db.execute('ALTER TABLE cards ADD COLUMN barcodeValue TEXT');
      }
    },
  );
}

Future<void> _createSettingsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ''');
}

/// Activity log rows. amount/balanceAfter/note are TEXT-affinity like the
/// card balance columns so they can hold ciphertext under an app PIN.
Future<void> _createTransactionsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cardId INTEGER NOT NULL,
      type TEXT NOT NULL,
      amount TEXT,
      balanceAfter TEXT,
      note TEXT,
      createdAt INTEGER NOT NULL
    )
  ''');
}

/// Reads a single setting value, or null when unset.
Future<String?> getSetting(DatabaseExecutor db, String key) async {
  final rows = await db.query(
    'settings',
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first['value'] as String?;
}

/// Inserts or replaces a single setting value.
Future<void> setSetting(DatabaseExecutor db, String key, String value) async {
  await db.insert(
    'settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

/// Reads the stored crypto config, or null when no app PIN has been set up.
Future<CryptoConfig?> readCryptoConfig(DatabaseExecutor db) async {
  final rows = await db.query(
    'settings',
    where: 'key IN (?, ?, ?)',
    whereArgs: [kSaltSettingKey, kVerifierSettingKey, kIterationsSettingKey],
  );
  final map = {
    for (final row in rows) row['key'] as String: row['value'] as String?,
  };
  return CryptoConfig.fromSettings(map);
}

/// Writes the crypto config. Must run in the same transaction as the row
/// re-encryption it belongs to, otherwise the verifier and the ciphertext
/// could end up under different keys.
Future<void> saveCryptoConfig(DatabaseExecutor db, CryptoConfig config) async {
  await setSetting(db, kSaltSettingKey, config.saltBase64);
  await setSetting(db, kVerifierSettingKey, config.verifier);
  await setSetting(db, kIterationsSettingKey, '${config.iterations}');
}

/// Card columns that hold sensitive content and are encrypted at rest.
/// `id`, `lastRefreshed` and `isManuallyEdited` stay plaintext (operational
/// metadata that neither identifies nor pays).
const List<String> kEncryptedCardColumns = [
  'cardNumber',
  'pin',
  'nickname',
  'currency',
  'status',
  'expiryDate',
  'barcodeFormat',
  'barcodeValue',
];

/// Sets up encryption with the given app PIN and encrypts every existing
/// (plaintext) card and transaction row. Row encryption and the config write
/// happen in one transaction, so "encrypted rows without a config" can never
/// exist — callers only reach this when `readCryptoConfig` returned null.
Future<CryptoConfig> enableEncryption(
  Database db,
  CardCrypto crypto,
  String pin,
) async {
  final config = await crypto.setup(pin);
  await db.transaction((txn) async {
    await _encryptAllRows(txn, 'cards', crypto);
    await _encryptAllRows(txn, 'transactions', crypto);
    await saveCryptoConfig(txn, config);
  });
  return config;
}

/// Re-encrypts all card and transaction rows under a new PIN after verifying
/// [oldPin]. Throws [WrongPinException] when the old PIN is wrong; the
/// session is left holding the new key on success.
Future<CryptoConfig> changeCardPin(
  Database db,
  CardCrypto crypto,
  String oldPin,
  String newPin,
) async {
  final oldConfig = await readCryptoConfig(db);
  if (oldConfig == null) {
    throw StateError('Encryption is not set up yet.');
  }
  await crypto.unlock(oldPin, oldConfig);

  // Decrypt everything while the old key is still in the session.
  final plaintextCards = <Map<String, Object?>>[];
  for (final row in await db.query('cards')) {
    plaintextCards.add(await decryptRawRow(row, crypto));
  }
  final plaintextTransactions = <Map<String, Object?>>[];
  for (final row in await db.query('transactions')) {
    plaintextTransactions.add(await decryptRawTransactionRow(row, crypto));
  }

  final newConfig = await crypto.setup(newPin);
  await db.transaction((txn) async {
    for (final row in plaintextCards) {
      await txn.update(
        'cards',
        await encryptRawRow(row, crypto),
        where: 'id = ?',
        whereArgs: [row['id'] as int],
      );
    }
    for (final row in plaintextTransactions) {
      await txn.update(
        'transactions',
        await encryptRawTransactionRow(row, crypto),
        where: 'id = ?',
        whereArgs: [row['id'] as int],
      );
    }
    await saveCryptoConfig(txn, newConfig);
  });
  return newConfig;
}

/// Returns the row with all sensitive columns decrypted in memory.
/// Plaintext (legacy) values pass through unchanged.
Future<Map<String, Object?>> decryptRawRow(
  Map<String, Object?> row,
  CardCrypto crypto,
) async {
  final map = Map<String, Object?>.from(row);
  for (final column in kEncryptedCardColumns) {
    final value = map[column];
    if (value is String) {
      map[column] = await crypto.decryptField(value);
    }
  }
  final balance = map['balance'];
  if (balance is String) {
    final plain = await crypto.decryptField(balance);
    map['balance'] = double.tryParse(plain) ?? 0.0;
  }
  final initialBalance = map['initialBalance'];
  if (initialBalance is String) {
    final plain = await crypto.decryptField(initialBalance);
    map['initialBalance'] = double.tryParse(plain);
  }
  return map;
}

/// Returns the row with all sensitive columns encrypted. Callers must pass
/// plaintext rows — every path here (pre-setup migration, PIN change after
/// full decryption, in-memory model writes) guarantees that, so an already
/// encrypted value signals a bug and throws instead of corrupting data.
Future<Map<String, Object?>> encryptRawRow(
  Map<String, Object?> row,
  CardCrypto crypto,
) async {
  final map = Map<String, Object?>.from(row);
  for (final column in kEncryptedCardColumns) {
    final value = map[column];
    if (value is String) {
      if (CardCrypto.isEncrypted(value)) {
        throw StateError(
          'encryptRawRow called on an already encrypted $column value.',
        );
      }
      map[column] = await crypto.encryptField(value);
    }
  }
  final balance = map['balance'];
  if (balance is num) {
    map['balance'] = await crypto.encryptField(_balanceToString(balance));
  } else if (balance is String) {
    if (CardCrypto.isEncrypted(balance)) {
      throw StateError(
        'encryptRawRow called on an already encrypted balance value.',
      );
    }
    map['balance'] = await crypto.encryptField(balance);
  }
  final initialBalance = map['initialBalance'];
  if (initialBalance is num) {
    map['initialBalance'] =
        await crypto.encryptField(_balanceToString(initialBalance));
  } else if (initialBalance is String) {
    if (CardCrypto.isEncrypted(initialBalance)) {
      throw StateError(
        'encryptRawRow called on an already encrypted initialBalance value.',
      );
    }
    map['initialBalance'] = await crypto.encryptField(initialBalance);
  }
  return map;
}

/// Encrypts every row of [table] in place (used by the pre-setup migration).
Future<void> _encryptAllRows(
  DatabaseExecutor txn,
  String table,
  CardCrypto crypto,
) async {
  for (final row in await txn.query(table)) {
    final encrypted = table == 'transactions'
        ? await encryptRawTransactionRow(row, crypto)
        : await encryptRawRow(row, crypto);
    await txn.update(
      table,
      encrypted,
      where: 'id = ?',
      whereArgs: [row['id'] as int],
    );
  }
}

/// Canonical decimal form used when encrypting the numeric balance.
String _balanceToString(num balance) {
  final asDouble = balance.toDouble();
  return asDouble == asDouble.roundToDouble()
      ? asDouble.toStringAsFixed(2)
      : '$asDouble';
}

/// Data access object for the `cards` table. When a [CardCrypto] with an
/// unlocked session is provided, sensitive columns are encrypted on write
/// and decrypted on read; the [GiftCard] objects themselves stay plaintext.
class CardDao {
  CardDao(this._db, {this.crypto});

  final Database _db;

  /// Null means no encryption (used by tests and pre-setup reads).
  final CardCrypto? crypto;

  Future<int> insert(GiftCard card) async {
    return _db.insert('cards', await _encryptRow(card.toDbMap()));
  }

  Future<int> update(GiftCard card) async {
    return _db.update(
      'cards',
      await _encryptRow(card.toDbMap()),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<int> delete(int id) async {
    return _db.delete('cards', where: 'id = ?', whereArgs: [id]);
  }

  Future<GiftCard?> getById(int id) async {
    final rows = await _db.query('cards', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _decryptRow(rows.first);
  }

  /// Matches in memory: the encrypted `cardNumber` column is not SQL-queryable.
  Future<GiftCard?> getByCardNumber(String cardNumber) async {
    final all = await getAll();
    for (final card in all) {
      if (card.cardNumber == cardNumber) return card;
    }
    return null;
  }

  Future<List<GiftCard>> getAll() async {
    final rows = await _db.query('cards', orderBy: 'id ASC');
    final cards = <GiftCard>[];
    for (final row in rows) {
      cards.add(await _decryptRow(row));
    }
    return cards;
  }

  /// Streams are overkill for this scale; callers re-query after mutations.
  Future<List<GiftCard>> getActive(DateTime today) async {
    final all = await getAll();
    return all.where((c) => c.isActive(today)).toList()
      ..sort(_byEarliestExpiry);
  }

  Future<List<GiftCard>> getArchived(DateTime today) async {
    final all = await getAll();
    return all.where((c) => c.isArchived(today)).toList()
      ..sort(_byEarliestExpiry);
  }

  /// Cards eligible for an online refresh: everything in the wallet that is
  /// neither expired, already known to be spent, nor synced within the
  /// refresh cooldown (automatic refreshes stay polite; explicit per-card
  /// queries bypass this).
  Future<List<GiftCard>> getRefreshable(DateTime now) async {
    final all = await getAll();
    return all
        .where(
          (c) =>
              c.isRefreshable(now) && !c.isRefreshCoolingDown(now),
        )
        .toList()
      ..sort(_byEarliestExpiry);
  }

  /// Sum of balances over all active cards, in the wallet currency.
  Future<double> totalActiveBalance(DateTime today) async {
    final active = await getActive(today);
    return active.fold<double>(0.0, (sum, c) => sum + c.balance);
  }

  Future<Map<String, Object?>> _encryptRow(Map<String, Object?> map) async {
    final cardCrypto = crypto;
    if (cardCrypto == null) return map;
    return encryptRawRow(map, cardCrypto);
  }

  Future<GiftCard> _decryptRow(Map<String, Object?> row) async {
    final cardCrypto = crypto;
    if (cardCrypto == null) return GiftCard.fromDbMap(row);
    final map = await decryptRawRow(row, cardCrypto);
    return GiftCard.fromDbMap(map);
  }
}

int _byEarliestExpiry(GiftCard a, GiftCard b) {
  final aExp = a.expiryDate;
  final bExp = b.expiryDate;
  // Cards without a known expiry sort last but stay deterministic by id.
  if (aExp == null && bExp == null) return a.id!.compareTo(b.id!);
  if (aExp == null) return 1;
  if (bExp == null) return -1;
  final cmp = aExp.compareTo(bExp);
  if (cmp != 0) return cmp;
  return a.id!.compareTo(b.id!);
}

/// Data access object for the `transactions` activity log. Sensitive value
/// columns (amount/balanceAfter/note) follow the same crypto rules as the
/// card balance; type/cardId/createdAt stay plaintext.
class TransactionDao {
  TransactionDao(this._db, {this.crypto});

  final Database _db;

  /// Null means no encryption (used by tests and pre-setup reads).
  final CardCrypto? crypto;

  Future<int> insert(CardTransaction transaction) async {
    return _db.insert(
      'transactions',
      await _encryptRow(transaction.toDbMap()),
    );
  }

  /// Newest first.
  Future<List<CardTransaction>> listForCard(int cardId, {int limit = 100}) async {
    final rows = await _db.query(
      'transactions',
      where: 'cardId = ?',
      whereArgs: [cardId],
      orderBy: 'createdAt DESC, id DESC',
      limit: limit,
    );
    final transactions = <CardTransaction>[];
    for (final row in rows) {
      transactions.add(await _decryptRow(row));
    }
    return transactions;
  }

  Future<void> deleteForCard(int cardId) async {
    await _db.delete('transactions', where: 'cardId = ?', whereArgs: [cardId]);
  }

  Future<void> deleteAll() async {
    await _db.delete('transactions');
  }

  Future<Map<String, Object?>> _encryptRow(Map<String, Object?> map) async {
    final cardCrypto = crypto;
    if (cardCrypto == null) return map;
    return encryptRawTransactionRow(map, cardCrypto);
  }

  Future<CardTransaction> _decryptRow(Map<String, Object?> row) async {
    final cardCrypto = crypto;
    if (cardCrypto == null) return CardTransaction.fromDbMap(row);
    final map = await decryptRawTransactionRow(row, cardCrypto);
    return CardTransaction.fromDbMap(map);
  }
}

/// Sensitive columns of the `transactions` activity log.
const List<String> kEncryptedTransactionColumns = [
  'amount',
  'balanceAfter',
  'note',
];

/// Returns a transactions-table row with the sensitive columns decrypted in
/// memory (amount/balanceAfter as double?, note as String). Plaintext
/// (legacy) values pass through unchanged.
Future<Map<String, Object?>> decryptRawTransactionRow(
  Map<String, Object?> row,
  CardCrypto crypto,
) async {
  final map = Map<String, Object?>.from(row);
  for (final column in kEncryptedTransactionColumns) {
    final value = map[column];
    if (value is String) {
      final plain = await crypto.decryptField(value);
      map[column] = column == 'note' ? plain : double.tryParse(plain);
    }
  }
  return map;
}

/// Returns a transactions-table row with the sensitive columns encrypted.
/// Throws on already-encrypted input (same invariant as [encryptRawRow]).
Future<Map<String, Object?>> encryptRawTransactionRow(
  Map<String, Object?> row,
  CardCrypto crypto,
) async {
  final map = Map<String, Object?>.from(row);
  for (final column in kEncryptedTransactionColumns) {
    final value = map[column];
    if (value is num) {
      map[column] = await crypto.encryptField(_balanceToString(value));
    } else if (value is String) {
      if (CardCrypto.isEncrypted(value)) {
        throw StateError(
          'encryptRawTransactionRow called on an already encrypted $column.',
        );
      }
      map[column] = await crypto.encryptField(value);
    }
  }
  return map;
}
