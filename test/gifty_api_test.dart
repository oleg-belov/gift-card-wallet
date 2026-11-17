import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/models/gift_card.dart';
import 'package:lidl_gift_card/services/gifty_api.dart';
import 'package:lidl_gift_card/services/parser.dart';

void main() {
  group('GiftyApiParser', () {
    /// The real `POST /explore/giftyBalanceV2/gifty` answer for a fully
    /// spent 100 CHF voucher, captured live in November 2026.
    late String spentPayload;

    setUp(() {
      spentPayload = File(
        'test/fixtures/gifty_api_response_spent_card.json',
      ).readAsStringSync();
    });

    test('parses the real spent-card response', () {
      final outcome = GiftyApiParser.parse(spentPayload)!;
      expect(outcome.errorKey, isNull);
      expect(outcome.errorDetail, isNull);

      final result = outcome.result;
      expect(result.balance, 0.0);
      // "ACTIVE" is an English status word — maps to the aktiv enum.
      expect(result.status, GiftCardStatus.aktiv);
      // expires_at is "2031-10-31 22:59:59" (ISO + time) — the date must
      // survive, which needs ISO support in parseExpiry.
      expect(result.expiryDate, '2031-10-31');
      expect(result.isSuccess, isTrue);
    });

    test('parses an active card with a decimal balance', () {
      final payload = jsonEncode({
        'card_id': 'abc',
        'status': 'ACTIVE',
        'card_number': '211224627680296028',
        'serial_number': '200000000018022770',
        'balance': {'amount': 47.35, 'currency': 'CHF'},
        'activated_at': '2026-10-09 06:44:42',
        'expires_at': '2031-10-31 22:59:59',
      });
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.errorKey, isNull);
      expect(outcome.result.balance, 47.35);
      expect(outcome.result.status, GiftCardStatus.aktiv);
      expect(outcome.result.expiryDate, '2031-10-31');
    });

    test('maps REDEEMED status to eingelöst', () {
      final payload = jsonEncode({
        'status': 'REDEEMED',
        'balance': {'amount': 0, 'currency': 'CHF'},
      });
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.result.status, GiftCardStatus.eingeloest);
    });

    test('treats code 4002 as card-not-found', () {
      final payload = jsonEncode({
        'code': 4002,
        'message': 'Card not found',
        'description': 'The card number does not exist',
      });
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.errorKey, RefreshErrors.cardNotFound);
      expect(outcome.errorDetail, isNull);
    });

    test('maps other API errors to apiError with the description', () {
      final payload = jsonEncode({
        'code': 5001,
        'message': 'Internal error',
        'description': 'Service temporarily unavailable',
      });
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.errorKey, RefreshErrors.apiError);
      expect(outcome.errorDetail, 'Service temporarily unavailable');
    });

    test('message-only errors without balance keys map to apiError', () {
      final payload = jsonEncode({'message': 'captcha failed'});
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.errorKey, RefreshErrors.apiError);
    });

    test('returns null for non-JSON, arrays and unusable maps', () {
      expect(GiftyApiParser.parse('not json'), isNull);
      expect(GiftyApiParser.parse(jsonEncode([1, 2, 3])), isNull);
      expect(GiftyApiParser.parse(jsonEncode({'foo': 'bar'})), isNull);
    });

    test('a parsed-but-incomplete payload falls back to null', () {
      // Balance key present but no usable amount and no status.
      expect(GiftyApiParser.parse(jsonEncode({'balance': null})), isNull);
    });

    test('integer amounts are flagged for page confirmation (rappen)', () {
      // Some cards report minor units: 10375 rappen = 103.75 CHF.
      final payload = jsonEncode({
        'status': 'ACTIVE',
        'balance': {'amount': 10375, 'currency': 'CHF'},
      });
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.amountIsInteger, isTrue);
      expect(outcome.result.balance, 10375.0);
      expect(GiftyApiParser.needsPageConfirmation(outcome), isTrue);
    });

    test('decimal amounts need no confirmation', () {
      final payload = jsonEncode({
        'status': 'ACTIVE',
        'balance': {'amount': 103.75, 'currency': 'CHF'},
      });
      final outcome = GiftyApiParser.parse(payload)!;
      expect(outcome.amountIsInteger, isFalse);
      expect(outcome.result.balance, 103.75);
      expect(GiftyApiParser.needsPageConfirmation(outcome), isFalse);
    });

    test('zero and small integers need no confirmation', () {
      final outcome = GiftyApiParser.parse(jsonEncode({
        'status': 'ACTIVE',
        'balance': {'amount': 0, 'currency': 'CHF'},
      }))!;
      expect(GiftyApiParser.needsPageConfirmation(outcome), isFalse);
    });
  });
}
