import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/db/database.dart';
import 'package:lidl_gift_card/models/gift_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late CardDao dao;
  final today = DateTime(2026, 11, 13);

  setUp(() async {
    final tmpDir = await Directory.systemTemp.createTemp('lidl_gc_test');
    db = await openCardDatabase(path: '${tmpDir.path}/test.db');
    dao = CardDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  GiftCard card({
    int? id,
    required String number,
    required String pin,
    double balance = 100,
    GiftCardStatus status = GiftCardStatus.aktiv,
    String? expiry = '2031-10-31',
    int? lastRefreshed,
    bool isManuallyEdited = false,
  }) {
    return GiftCard(
      id: id,
      cardNumber: number,
      pin: pin,
      balance: balance,
      status: status,
      expiryDate: expiry,
      lastRefreshed: lastRefreshed,
      isManuallyEdited: isManuallyEdited,
    );
  }

  test('insert assigns id and round-trips all fields', () async {
    final id = await dao.insert(GiftCard.draft(
      cardNumber: '1234567890',
      pin: '1234',
      nickname: 'Birthday Card',
    ));
    final loaded = await dao.getById(id);
    expect(loaded, isNotNull);
    expect(loaded!.cardNumber, '1234567890');
    expect(loaded.pin, '1234');
    expect(loaded.nickname, 'Birthday Card');
    expect(loaded.currency, 'CHF');
    expect(loaded.status, GiftCardStatus.unbekannt);
    expect(loaded.balance, 0);
    expect(loaded.isManuallyEdited, isFalse);
  });

  test('getByCardNumber finds a stored card', () async {
    await dao.insert(card(number: 'AAA111', pin: '4321'));
    final found = await dao.getByCardNumber('AAA111');
    expect(found, isNotNull);
    expect(found!.pin, '4321');
    expect(await dao.getByCardNumber('missing'), isNull);
  });

  test('update persists balance and manual-edit flag', () async {
    final id = await dao.insert(card(number: 'UPD1', pin: '1111'));
    final stored = await dao.getById(id);
    final updated = stored!.copyWith(
      balance: 45.5,
      status: GiftCardStatus.aktiv,
      expiryDate: '2027-01-01',
      lastRefreshed: 1731500000000,
      isManuallyEdited: true,
    );
    await dao.update(updated);

    final reloaded = await dao.getById(id);
    expect(reloaded!.balance, 45.5);
    expect(reloaded.status, GiftCardStatus.aktiv);
    expect(reloaded.expiryDate, '2027-01-01');
    expect(reloaded.lastRefreshed, 1731500000000);
    expect(reloaded.isManuallyEdited, isTrue);
  });

  test('delete removes the card', () async {
    final id = await dao.insert(card(number: 'DEL1', pin: '2222'));
    await dao.delete(id);
    expect(await dao.getById(id), isNull);
  });

  test('getActive filters spent and expired cards, sorts by expiry',
      () async {
    await dao.insert(card(number: 'A', pin: '1', expiry: '2027-05-01'));
    await dao.insert(card(number: 'B', pin: '2', expiry: '2026-12-01')); // soonest
    await dao.insert(card(number: 'C', pin: '3', balance: 0, lastRefreshed: 1731500000000)); // synced as empty
    await dao.insert(card(
      number: 'D',
      pin: '4',
      status: GiftCardStatus.abgelaufen,
      expiry: '2020-01-01',
    )); // expired

    final active = await dao.getActive(today);
    expect(active.map((c) => c.cardNumber), ['B', 'A']);
  });

  test('never-synced card with zero balance stays in the wallet', () async {
    await dao.insert(card(number: 'NEW', pin: '9', balance: 0));

    final active = await dao.getActive(today);
    expect(active.map((c) => c.cardNumber), ['NEW']);
    expect(await dao.getArchived(today), isEmpty);
    // It is also refreshable so its initial fetch can be retried.
    expect((await dao.getRefreshable(today)).map((c) => c.cardNumber), ['NEW']);
  });

  test('manually marked-empty card goes to the archive', () async {
    final id = await dao.insert(card(number: 'EMPTY', pin: '5'));
    final stored = await dao.getById(id);
    await dao.update(stored!.copyWith(balance: 0, isManuallyEdited: true));

    expect(await dao.getActive(today), isEmpty);
    expect((await dao.getArchived(today)).map((c) => c.cardNumber), ['EMPTY']);
    expect(await dao.getRefreshable(today), isEmpty);
  });

  test('getArchived returns spent and expired cards', () async {
    await dao.insert(card(number: 'A', pin: '1', expiry: '2027-05-01'));
    await dao.insert(card(number: 'C', pin: '3', balance: 0, lastRefreshed: 1731500000000));
    await dao.insert(card(
      number: 'D',
      pin: '4',
      status: GiftCardStatus.abgelaufen,
      expiry: '2020-01-01',
    ));

    final archived = await dao.getArchived(today);
    expect(archived.map((c) => c.cardNumber).toSet(), {'C', 'D'});
  });

  test('getRefreshable skips empty and expired cards', () async {
    await dao.insert(card(number: 'A', pin: '1', expiry: '2027-05-01'));
    await dao.insert(card(number: 'C', pin: '3', balance: 0, lastRefreshed: 1731500000000));
    await dao.insert(card(number: 'D', pin: '4', expiry: '2020-01-01'));

    final refreshable = await dao.getRefreshable(today);
    expect(refreshable.map((c) => c.cardNumber), ['A']);
  });

  test('totalActiveBalance sums active cards only', () async {
    await dao.insert(card(number: 'A', pin: '1', balance: 200, expiry: '2027-05-01'));
    await dao.insert(card(number: 'B', pin: '2', balance: 250, expiry: '2026-12-01'));
    await dao.insert(card(number: 'C', pin: '3', balance: 999, expiry: '2020-01-01')); // expired

    expect(await dao.totalActiveBalance(today), 450);
  });
}
