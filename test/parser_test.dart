import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/models/gift_card.dart';
import 'package:lidl_gift_card/services/parser.dart';

void main() {
  group('parseBalance', () {
    test('parses the portal format "200.00 CHF"', () {
      expect(BalanceParser.parseBalance('200.00 CHF'), 200.00);
    });

    test('parses leading currency "CHF 200.00"', () {
      expect(BalanceParser.parseBalance('CHF 200.00'), 200.00);
    });

    test('parses Swiss thousands separator "2\'000.00 CHF"', () {
      expect(BalanceParser.parseBalance("2'000.00 CHF"), 2000.00);
    });

    test('parses German decimal comma "1.999,90 CHF"', () {
      expect(BalanceParser.parseBalance('1.999,90 CHF'), 1999.90);
    });

    test('parses plain comma decimal "200,00 CHF"', () {
      expect(BalanceParser.parseBalance('200,00 CHF'), 200.00);
    });

    test('parses bare numbers and non-breaking space before CHF', () {
      expect(BalanceParser.parseBalance('31.50\u{00A0}CHF'), 31.50);
      expect(BalanceParser.parseBalance('0.00'), 0.00);
    });

    test('returns null for text without amounts', () {
      expect(BalanceParser.parseBalance('Kein Guthaben gefunden'), isNull);
      expect(BalanceParser.parseBalance(''), isNull);
    });
  });

  group('parseStatus', () {
    test('maps the portal status words', () {
      expect(BalanceParser.parseStatus('Aktiv'), GiftCardStatus.aktiv);
      expect(BalanceParser.parseStatus('Eingelöst'), GiftCardStatus.eingeloest);
      expect(
        BalanceParser.parseStatus('Eingeloest'),
        GiftCardStatus.eingeloest,
      );
      expect(
        BalanceParser.parseStatus('Abgelaufen'),
        GiftCardStatus.abgelaufen,
      );
    });

    test('is case-insensitive and tolerant of surrounding text', () {
      expect(
        BalanceParser.parseStatus('  Status: ABGELAUFEN '),
        GiftCardStatus.abgelaufen,
      );
    });

    test('falls back to unbekannt', () {
      expect(BalanceParser.parseStatus('something else'), GiftCardStatus.unbekannt);
    });

    test('maps the API\'s English status words', () {
      // Real gifty API payload statuses (November 2026): a fully spent card
      // still reports ACTIVE with amount 0.
      expect(BalanceParser.parseStatus('ACTIVE'), GiftCardStatus.aktiv);
      expect(BalanceParser.parseStatus('REDEEMED'), GiftCardStatus.eingeloest);
      expect(BalanceParser.parseStatus('EXPIRED'), GiftCardStatus.abgelaufen);
    });
  });

  group('parseExpiry', () {
    test('converts DD.MM.YYYY to ISO YYYY-MM-DD', () {
      expect(BalanceParser.parseExpiry('31.10.2031'), '2031-10-31');
      expect(BalanceParser.parseExpiry('Gültig bis 1.3.2027.'), '2027-03-01');
    });

    test('parses the API\'s ISO timestamps ("2031-10-31 22:59:59")', () {
      // Real expires_at format of giftyBalanceV2 — before ISO support this
      // returned null and every card lost its expiry date on refresh.
      expect(
        BalanceParser.parseExpiry('2031-10-31 22:59:59'),
        '2031-10-31',
      );
      expect(BalanceParser.parseExpiry('2031-10-31'), '2031-10-31');
    });

    test('rejects impossible dates and free text', () {
      expect(BalanceParser.parseExpiry('31.13.2031'), isNull);
      expect(BalanceParser.parseExpiry('2031-13-01'), isNull);
      expect(BalanceParser.parseExpiry('kein Datum'), isNull);
    });
  });

  group('extractFromPageText', () {
    test('extracts all three fields from a realistic result page', () {
      const page = '''
        Guthaben: 200.00 CHF
        Status: Aktiv
        Gültigkeitsdatum: 31.10.2031
      ''';
      final r = BalanceParser.extractFromPageText(page);
      expect(r.balance, 200.00);
      expect(r.status, GiftCardStatus.aktiv);
      expect(r.expiryDate, '2031-10-31');
      expect(r.isSuccess, isTrue);
    });

    test('extracts values even when markup noise surrounds them', () {
      const page = 'Ihre Karte | Guthaben 47.35 CHF | Eingelöst | 05.06.2026';
      final r = BalanceParser.extractFromPageText(page);
      expect(r.balance, 47.35);
      expect(r.status, GiftCardStatus.eingeloest);
      expect(r.expiryDate, '2026-06-05');
    });

    test('handles "CHF 200.00" word order', () {
      final r = BalanceParser.extractFromPageText('CHF 120.00 Aktiv 12.12.2030');
      expect(r.balance, 120.00);
      expect(r.status, GiftCardStatus.aktiv);
      expect(r.expiryDate, '2030-12-12');
    });

    test('degrades gracefully on an error page', () {
      const page = 'Leider konnte Ihre Karte nicht gefunden werden.';
      final r = BalanceParser.extractFromPageText(page);
      expect(r.balance, isNull);
      expect(r.status, GiftCardStatus.unbekannt);
      expect(r.expiryDate, isNull);
      expect(r.isSuccess, isFalse);
    });

    test('parses the real spent-card result panel (live capture)', () {
      // Exact innerText of the AGiftyBalanceCheck result panel for a fully
      // redeemed 100 CHF voucher: status stays "Aktiv", the 0.00 balance is
      // the redemption signal.
      const page = 'GUTSCHEIN\nPIN\nPin anzeigen\nI am human\n'
          'FriendlyCaptcha ⇗\nJETZT ABFRAGEN\nLÖSCHEN\n'
          'Guthaben\n0.00 CHF\nGutschein Status\nAktiv\n'
          'Gültigkeitsdatum\n31.10.2031';
      final r = BalanceParser.extractFromPageText(page);
      expect(r.balance, 0.0);
      expect(r.status, GiftCardStatus.aktiv);
      expect(r.expiryDate, '2031-10-31');
      expect(r.isSuccess, isTrue);
    });
  });
}
