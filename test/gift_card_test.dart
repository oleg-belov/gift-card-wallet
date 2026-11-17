import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/models/gift_card.dart';

void main() {
  final today = DateTime(2026, 11, 13);

  GiftCard make({
    double balance = 100,
    String? expiry = '2031-10-31',
    GiftCardStatus status = GiftCardStatus.aktiv,
    int? lastRefreshed,
    bool isManuallyEdited = false,
  }) {
    return GiftCard(
      id: 1,
      cardNumber: '1234567890',
      pin: '1234',
      balance: balance,
      status: status,
      expiryDate: expiry,
      lastRefreshed: lastRefreshed,
      isManuallyEdited: isManuallyEdited,
    );
  }

  group('GiftCard lifecycle helpers', () {
    test('isExpired compares against the given day', () {
      expect(make(expiry: '2026-11-12').isExpired(today), isTrue);
      expect(make(expiry: '2026-11-13').isExpired(today), isFalse); // expires today = active
      expect(make(expiry: '2027-01-01').isExpired(today), isFalse);
      expect(make(expiry: null).isExpired(today), isFalse);
    });

    test('daysUntilExpiry counts whole days', () {
      expect(make(expiry: '2026-12-28').daysUntilExpiry(today), 45);
      expect(make(expiry: null).daysUntilExpiry(today), isNull);
    });

    test('archived only when spent-confirmed or expired', () {
      // A never-synced zero-balance card stays in the wallet.
      expect(make(balance: 0).isArchived(today), isFalse);
      expect(
        make(balance: 0, lastRefreshed: 1731500000000).isArchived(today),
        isTrue,
      );
      expect(
        make(balance: 0, isManuallyEdited: true).isArchived(today),
        isTrue,
      );
      expect(make(expiry: '2020-01-01').isArchived(today), isTrue);
      expect(make().isArchived(today), isFalse);
    });

    test('refreshable until expired or confirmed spent', () {
      expect(make().isRefreshable(today), isTrue);
      expect(make(balance: 0).isRefreshable(today), isTrue); // never synced
      expect(
        make(balance: 0, lastRefreshed: 1).isRefreshable(today),
        isFalse,
      );
      expect(make(expiry: '2020-01-01').isRefreshable(today), isFalse);
      expect(
        make(status: GiftCardStatus.abgelaufen).isRefreshable(today),
        isFalse,
      );
    });

    test('active only when not expired and not confirmed spent', () {
      expect(make().isActive(today), isTrue);
      expect(make(balance: 0).isActive(today), isTrue); // never synced
      expect(
        make(balance: 0, lastRefreshed: 1).isActive(today),
        isFalse,
      );
      expect(make(expiry: '2020-01-01').isActive(today), isFalse);
    });
  });

  group('GiftCard persistence mapping', () {
    test('db map round-trip preserves every field', () {
      final original = GiftCard(
        id: 7,
        cardNumber: 'CARD-987',
        pin: '0000',
        nickname: 'Test',
        balance: 123.45,
        currency: 'CHF',
        status: GiftCardStatus.eingeloest,
        expiryDate: '2030-03-03',
        lastRefreshed: 1731500000000,
        isManuallyEdited: true,
      );
      final restored = GiftCard.fromDbMap(original.toDbMap());
      expect(restored.id, 7);
      expect(restored.cardNumber, 'CARD-987');
      expect(restored.pin, '0000');
      expect(restored.nickname, 'Test');
      expect(restored.balance, 123.45);
      expect(restored.status, GiftCardStatus.eingeloest);
      expect(restored.expiryDate, '2030-03-03');
      expect(restored.lastRefreshed, 1731500000000);
      expect(restored.isManuallyEdited, isTrue);
    });

    test('unknown status string maps to unbekannt', () {
      final map = make().toDbMap();
      map['status'] = 'weird';
      expect(GiftCard.fromDbMap(map).status, GiftCardStatus.unbekannt);
    });
  });

  group('status labels', () {
    test('round-trips status from raw enum name', () {
      for (final s in GiftCardStatus.values) {
        expect(giftCardStatusFromRaw(s.name), s);
      }
    });

    test('unknown raw string maps to unbekannt', () {
      expect(giftCardStatusFromRaw('garbage'), GiftCardStatus.unbekannt);
    });
  });

  group('refresh cooldown', () {
    test('never cooling down without a sync', () {
      expect(make(lastRefreshed: null).isRefreshCoolingDown(today), isFalse);
    });

    test('cooling down within 2h of the last sync', () {
      final now = DateTime(2026, 11, 17, 15, 0);
      final recent = make(lastRefreshed: now.millisecondsSinceEpoch);
      expect(recent.isRefreshCoolingDown(now), isTrue);
      final justWithin = make(
        lastRefreshed: now
            .subtract(const Duration(hours: 1, minutes: 59))
            .millisecondsSinceEpoch,
      );
      expect(justWithin.isRefreshCoolingDown(now), isTrue);
    });

    test('not cooling down after 2h have passed', () {
      final now = DateTime(2026, 11, 17, 15, 0);
      final old = make(
        lastRefreshed: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
      expect(old.isRefreshCoolingDown(now), isFalse);
    });
  });

  group('barcode value (GS1-128)', () {
    test('checkoutBarcode falls back to the card number', () {
      final card = make();
      expect(card.checkoutBarcode, card.cardNumber);
    });

    test('checkoutBarcode prefers the full GS1 payload', () {
      final card = GiftCard(
        id: 1,
        cardNumber: '211224627680296028',
        pin: '7195',
        barcodeValue: '010406753421013490211224627680296028',
      );
      expect(card.checkoutBarcode, '010406753421013490211224627680296028');
    });

    test('barcodeValue round-trips through the db map', () {
      final card = GiftCard(
        id: 1,
        cardNumber: '211224627680296028',
        pin: '7195',
        barcodeValue: '010406753421013490211224627680296028',
      );
      final restored = GiftCard.fromDbMap(card.toDbMap());
      expect(restored.barcodeValue, '010406753421013490211224627680296028');
      // Absent from the map → null (like barcodeFormat, no explicit clear).
      final without = GiftCard.fromDbMap(
        card.toDbMap()..remove('barcodeValue'),
      );
      expect(without.barcodeValue, isNull);
    });
  });
}
