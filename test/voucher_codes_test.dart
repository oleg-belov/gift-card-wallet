import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/services/voucher_codes.dart';

void main() {
  group('parseScannedCode', () {
    test('parses the real voucher GS1-128 payload (AI 01 + AI 90)', () {
      // Captured from a genuine Lidl CH voucher PDF barcode (Vision decode).
      const payload = '010406753421013490211224627680296028';
      final code = parseScannedCode(payload)!;
      expect(code.cardNumber, '211224627680296028');
      expect(code.barcodeValue, payload);
    });

    test('strips the ]C1 symbology identifier', () {
      final code = parseScannedCode(']C1010406753421013490211224627680296028')!;
      expect(code.cardNumber, '211224627680296028');
      expect(code.barcodeValue, '010406753421013490211224627680296028');
    });

    test('strips GS/RS group separators and spaces', () {
      final code = parseScannedCode(
        '\u001D0104067534210134\u001D90211224627680296028',
      )!;
      expect(code.cardNumber, '211224627680296028');
      expect(code.barcodeValue, '010406753421013490211224627680296028');

      expect(parseScannedCode('01 04067534210134 90 211224627680296028')!
          .cardNumber, '211224627680296028');
    });

    test('rejects GS1 payloads whose card number is too short', () {
      expect(parseScannedCode('01040675342101349021122'), isNull);
    });

    test('accepts bare card numbers (15-22 digits)', () {
      final code = parseScannedCode('211224627680296028')!;
      expect(code.cardNumber, '211224627680296028');
      expect(code.barcodeValue, isNull);

      expect(parseScannedCode('9840281900485721')!.cardNumber,
          '9840281900485721');
    });

    test('rejects non-card values', () {
      expect(parseScannedCode(''), isNull);
      expect(parseScannedCode('hello'), isNull);
      expect(parseScannedCode('9840'), isNull); // too short
      expect(parseScannedCode('98402819004857'), isNull); // 14 digits
      // 36 digits without the recognizable 01/90 AI structure.
      expect(parseScannedCode('9' * 36), isNull);
    });
  });
}
