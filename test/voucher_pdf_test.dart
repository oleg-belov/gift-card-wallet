import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/services/voucher_pdf.dart';

/// Builds a minimal PDF from latin1 strings, nested chunks and raw bytes.
/// Note: Uint8List must be matched before List<Object> — at runtime
/// `Uint8List is List<Object>` is true (covariance), which would otherwise
/// iterate and drop the raw bytes.
Uint8List buildPdf(List<Object> parts) {
  final out = BytesBuilder();
  void add(Object part) {
    if (part is String) {
      out.add(latin1.encode(part));
    } else if (part is Uint8List) {
      out.add(part);
    } else if (part is List<int>) {
      out.add(part);
    } else if (part is List<Object>) {
      for (final inner in part) {
        add(inner);
      }
    }
  }

  out.add(latin1.encode('%PDF-1.4\n'));
  for (final part in parts) {
    add(part);
  }
  out.add(latin1.encode('%%EOF\n'));
  return out.toBytes();
}

Uint8List flate(String content) =>
    Uint8List.fromList(ZLibCodec().encode(latin1.encode(content)));

/// Content stream object (FlateDecode, length is not checked by the
/// extractor).
List<Object> contentObject(int objNum, String content) => [
      '\n$objNum 0 obj\n<< /Length 99 /Filter /FlateDecode >>\nstream\n',
      flate(content),
      '\nendstream\nendobj\n',
    ];

void main() {
  group('real voucher PDF', () {
    // The genuine Lidl CH voucher PDF (fully redeemed, owner-approved
    // fixture): Qt webarchiver, Identity-H CID fonts with an array-form
    // bfrange ToUnicode CMap.
    late Uint8List bytes;
    setUp(() {
      bytes = File(
        'test/fixtures/lidl_voucher_100chf_used.pdf',
      ).readAsBytesSync();
    });

    test('extracts card number, PIN, face value and serial', () {
      final data = VoucherPdfExtractor.extract(bytes);
      expect(data.cardNumber, '211224627680296028');
      expect(data.pin, '7195');
      expect(data.value, 100.0);
      expect(data.serial, '200000000018022770');
      expect(data.hasCardData, isTrue);
    });

    test('decoded text keeps the printed grouping and labels', () {
      final data = VoucherPdfExtractor.extract(bytes);
      expect(data.text, contains('2112 2462 7680 2960 28'));
      expect(data.text, contains('200000000018022770'));
      expect(data.text, contains('PIN'));
      expect(data.text, contains('CHF'));
    });

    test('extracts embedded images as decodable encodings', () {
      final data = VoucherPdfExtractor.extract(bytes);
      // The real voucher embeds the card artwork (DCTDecode/JPEG) and the
      // barcode strip (FlateDecode raw RGB → wrapped as PNG).
      expect(data.images, hasLength(2));

      final jpgs = data.images.where((i) => i.extension == 'jpg');
      expect(jpgs, isNotEmpty);
      for (final jpg in jpgs) {
        expect(jpg.bytes[0], 0xFF); // JPEG SOI marker
        expect(jpg.bytes[1], 0xD8);
        expect(jpg.bytes[2], 0xFF);
      }

      final pngs = data.images.where((i) => i.extension == 'png');
      expect(pngs, isNotEmpty);
      for (final png in pngs) {
        expect(png.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]); // PNG signature
        expect(String.fromCharCodes(png.bytes.skip(12).take(4)), 'IHDR');
        // IHDR: width/height as big-endian u32 at offsets 16/20.
        final width = png.bytes[16] << 24 |
            png.bytes[17] << 16 |
            png.bytes[18] << 8 |
            png.bytes[19];
        final height = png.bytes[20] << 24 |
            png.bytes[21] << 16 |
            png.bytes[22] << 8 |
            png.bytes[23];
        expect(width, greaterThan(0));
        expect(height, greaterThan(0));
        // Ends with the IEND chunk.
        expect(
          String.fromCharCodes(png.bytes.skip(png.bytes.length - 8).take(4)),
          'IEND',
        );
      }
    });
  });

  group('synthetic CID-font PDF (array bfrange CMap)', () {
    test('decodes glyphs through the font CMap', () {
      const cMap = '/CIDInit /ProcSet findresource begin\n'
          '12 dict begin\n'
          'begincmap\n'
          '1 beginbfrange\n'
          '<0001> <0009> [<0032> <0031> <0034> <0036> <0037> <0038> <0039>'
          ' <0030> <0020>]\n'
          'endbfrange\n'
          'endcmap\n'
          'end\n';
      // CID1='2', CID2='1', CID3='4', CID4='6', CID5='7', CID6='8',
      // CID7='9', CID8='0', CID9=' '.
      final pdf = buildPdf([
        '\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
        '\n2 0 obj\n<< /Type /Page /Resources << /Font << /F1 3 0 R >> >>'
            ' /Contents 4 0 R >>\nendobj\n',
        '\n3 0 obj\n<< /Type /Font /Subtype /Type0 /Encoding /Identity-H'
            ' /ToUnicode 5 0 R >>\nendobj\n',
        '\n5 0 obj\n<< /Length 99 >>\nstream\n$cMap\nendstream\nendobj\n',
        contentObject(
          4,
          'BT /F1 20 Tf 5 100 Td '
              '<0001> Tj 10 0 Td <0002> Tj 10 0 Td <0002> Tj 10 0 Td <0001> Tj '
              '10 0 Td <0009> Tj 10 0 Td <0001> Tj 10 0 Td <0003> Tj 10 0 Td '
              '<0004> Tj 10 0 Td <0001> Tj 10 0 Td <0009> Tj 10 0 Td <0005> Tj '
              '10 0 Td <0004> Tj 10 0 Td <0006> Tj 10 0 Td <0008> Tj 10 0 Td '
              '<0009> Tj 10 0 Td <0001> Tj 10 0 Td <0007> Tj 10 0 Td <0004> Tj '
              '10 0 Td <0008> Tj 10 0 Td <0009> Tj 10 0 Td <0001> Tj 10 0 Td '
              '<0006> Tj ET\n',
        ),
      ]);

      final data = VoucherPdfExtractor.extract(pdf);
      expect(data.cardNumber, '211224627680296028');
      // No other long digit run exists, so the serial stays null.
      expect(data.serial, isNull);
    });
  });

  group('synthetic literal-string PDF (no CMap)', () {
    test('reads plain WinAnsi text operators', () {
      final pdf = buildPdf([
        '\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
        '\n2 0 obj\n<< /Type /Page /Contents 3 0 R >>\nendobj\n',
        contentObject(
          3,
          'BT (2112 2462 7680 2960 28) Tj ET\n'
              'BT (PIN 7195) Tj ET\n'
              'BT (Wert 100 CHF) Tj ET\n'
              'BT (200000000018022770) Tj ET\n',
        ),
      ]);

      final data = VoucherPdfExtractor.extract(pdf);
      expect(data.cardNumber, '211224627680296028');
      expect(data.pin, '7195');
      expect(data.value, 100.0);
      expect(data.serial, '200000000018022770');
    });

    test('unescapes octal codes and parentheses', () {
      final pdf = buildPdf([
        '\n1 0 obj\n<< /Type /Page /Contents 2 0 R >>\nendobj\n',
        contentObject(
          2,
          r'BT (Betrag \(Netto\) 100,00 CHF) Tj ET\n'
              r'BT (PIN 7\06195) Tj ET\n',
        ),
      ]);

      final data = VoucherPdfExtractor.extract(pdf);
      expect(data.value, 100.0);
      expect(data.pin, '7195');
    });
  });

  group('synthetic bfchar CMap PDF', () {
    test('decodes bfchar mappings', () {
      const cMap = 'begincmap\n'
          '1 beginbfchar\n'
          '<0001> <0032>\n'
          '<0002> <0030>\n'
          '<0003> <0031>\n'
          'endbfchar\n'
          'endcmap\n';
      final pdf = buildPdf([
        '\n1 0 obj\n<< /Type /Page /Resources << /Font << /F9 3 0 R >> >>'
            ' /Contents 4 0 R >>\nendobj\n',
        '\n3 0 obj\n<< /Type /Font /Subtype /Type0 /Encoding /Identity-H'
            ' /ToUnicode 5 0 R >>\nendobj\n',
        '\n5 0 obj\n<< /Length 99 >>\nstream\n$cMap\nendstream\nendobj\n',
        // CID1='2', CID2='0', CID3='1' → "2010" repeated → 16 digits.
        contentObject(
          4,
          'BT /F9 12 Tf <0001><0002><0003><0002>'
              '<0001><0002><0003><0002>'
              '<0001><0002><0003><0002>'
              '<0001><0002><0003><0002> Tj ET\n',
        ),
      ]);

      final data = VoucherPdfExtractor.extract(pdf);
      expect(data.cardNumber, '2010201020102010');
    });
  });

  group('robustness', () {
    test('empty/binary content yields no fields without throwing', () {
      final pdf = buildPdf([
        '\n1 0 obj\n<< /Type /Page /Contents 2 0 R >>\nendobj\n',
        contentObject(2, 'BT /F1 10 Tf 10 10 Td ET'),
      ]);
      final data = VoucherPdfExtractor.extract(pdf);
      expect(data.hasCardData, isFalse);
      expect(data.pin, isNull);
      expect(data.value, isNull);
      expect(data.serial, isNull);
    });

    test('un-inflatable streams are skipped gracefully', () {
      final garbage = Uint8List.fromList(
        List.generate(200, (i) => (i * 37 + 11) & 0xFF),
      );
      final pdf = buildPdf([
        '\n1 0 obj\n<< /Type /Page /Contents 2 0 R >>\nendobj\n',
        '\n2 0 obj\n<< /Length 200 /Filter /FlateDecode >>\nstream\n',
        garbage,
        '\nendstream\nendobj\n',
        contentObject(3, 'BT (PIN 7195) Tj ET'),
      ]);
      final data = VoucherPdfExtractor.extract(pdf);
      expect(data.pin, '7195');
    });
  });
}
