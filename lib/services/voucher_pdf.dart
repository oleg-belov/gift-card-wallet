import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Data read from a Lidl voucher PDF's text layer.
///
/// The voucher PDFs Lidl sends (Qt webarchiver, Identity-H CID fonts) carry
/// the card number, PIN, value and serial as selectable text — no OCR or
/// native PDF renderer needed. All fields are null when the file did not
/// contain them; [text] keeps everything extracted for diagnostics.
class VoucherPdfData {
  VoucherPdfData({
    required this.text,
    this.cardNumber,
    this.pin,
    this.serial,
    this.value,
    this.images = const [],
  });

  /// Grouped card number without spaces (15-22 digits), e.g.
  /// "211224627680296028".
  final String? cardNumber;

  /// The 4-digit scratch PIN.
  final String? pin;

  /// Voucher serial (printed above the barcode, e.g. "200000000018022770").
  final String? serial;

  /// Voucher face value in the printed currency, e.g. 100 for "100 CHF".
  final double? value;

  /// Everything the text layer yielded (diagnostics / tests).
  final String text;

  /// Embedded raster images, converted to decodable encodings (JPEG kept as
  ///-is; raw RGB wrapped in a BMP). The thin strip image is the voucher's
  /// barcode — the caller can decode it for the GS1 payload.
  final List<VoucherPdfImage> images;

  bool get hasCardData => cardNumber != null;
}

/// One embedded image of the PDF, in a widely decodable encoding.
class VoucherPdfImage {
  const VoucherPdfImage({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// 'jpg' (DCTDecode passthrough) or 'bmp' (raw RGB wrapped).
  final String extension;
}

/// Extracts text from PDF files and pulls out the voucher fields.
///
/// Implementation notes: the PDF is byte-scanned instead of fully parsed —
/// object headers/streams are located, FlateDecode payloads are inflated
/// with dart:io's zlib, per-font ToUnicode CMaps are read and the content
/// streams' text-showing operators are decoded through the active font's
/// CMap. Spaces between digit groups are explicit glyphs in these files,
/// so glyph-order concatenation reproduces the printed layout well enough
/// for the field regexes below.
class VoucherPdfExtractor {
  VoucherPdfExtractor._();

  static VoucherPdfData extract(Uint8List bytes) {
    final pdf = latin1.decode(bytes, allowInvalid: true);
    final objects = _scanObjects(pdf, bytes);
    final images = _extractImages(objects);

    // Resource name -> font object number (merged over all /Font dicts).
    final fontRefs = <String, int>{};
    // Font object number -> font dict.
    final fontDicts = <int, String>{};
    for (final obj in objects.values) {
      for (final m in _fontDictRe.allMatches(obj.dict)) {
        for (final ref in _fontRefRe.allMatches(m.group(1)!)) {
          fontRefs[ref.group(1)!] = int.parse(ref.group(2)!);
        }
      }
      if (obj.dict.contains('/Type /Font') || obj.dict.contains('/ToUnicode')) {
        fontDicts[obj.number] = obj.dict;
      }
    }

    // Per font: CID width (Type0/Identity-H = 2 bytes) and CID->text map.
    final fonts = <String, _FontInfo>{};
    for (final entry in fontRefs.entries) {
      final dict = fontDicts[entry.value];
      if (dict == null) continue;
      final toUnicode = int.tryParse(
          _toUnicodeRe.firstMatch(dict)?.group(1) ?? '');
      fonts[entry.key] = _FontInfo(
        isTwoByte: dict.contains('/Type0') || dict.contains('Identity-H'),
        cmap: toUnicode == null ? null : _parseCMap(objects[toUnicode]),
      );
    }

    // Walk every content stream and decode the shown text.
    final text = StringBuffer();
    for (final obj in objects.values) {
      final decoded = obj.decodedString();
      if (decoded == null || !decoded.contains('BT')) continue;
      text.write(_extractStreamText(decoded, fonts));
    }

    final fullText = text.toString();
    return VoucherPdfData(
      text: fullText,
      cardNumber: _findCardNumber(fullText),
      pin: _findPin(fullText),
      serial: _findSerial(fullText),
      value: _findValue(fullText),
      images: images,
    );
  }

  // --- Embedded images -----------------------------------------------------

  /// Collects the PDF's raster images in decodable encodings:
  /// - DCTDecode payloads are JPEG files — pass the bytes through.
  /// - FlateDecode DeviceRGB images are raw top-down RGB rows — wrap them
  ///   in a minimal uncompressed 24-bit BMP (bottom-up, BGR, rows padded
  ///   to 4 bytes).
  /// Everything else (other filters/colorspaces) is skipped.
  static List<VoucherPdfImage> _extractImages(Map<int, _PdfObject> objects) {
    final images = <VoucherPdfImage>[];
    for (final obj in objects.values) {
      if (!obj.dict.contains('/Subtype') || !obj.dict.contains('/Image')) {
        continue;
      }
      final width = _intEntry(obj.dict, '/Width');
      final height = _intEntry(obj.dict, '/Height');
      if (width == null || height == null || width <= 0 || height <= 0) {
        continue;
      }
      final payload = obj.payload;
      if (payload == null || payload.isEmpty) continue;

      if (obj.dict.contains('/DCTDecode')) {
        images.add(VoucherPdfImage(bytes: payload, extension: 'jpg'));
        continue;
      }
      if (obj.dict.contains('/FlateDecode') &&
          obj.dict.contains('/DeviceRGB')) {
        List<int> raw;
        try {
          raw = ZLibCodec().decode(payload);
        } catch (_) {
          continue;
        }
        final png = _rgbToPng(raw, width, height);
        if (png != null) {
          images.add(VoucherPdfImage(bytes: png, extension: 'png'));
        }
      }
    }
    return images;
  }

  static int? _intEntry(String dict, String key) {
    final m = RegExp('$key\\s+(-?\\d+)').firstMatch(dict);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Wraps raw 3-bytes-per-pixel RGB data (top-down rows) in a PNG with a
  /// white margin around the picture — barcode strips embedded in PDFs are
  /// usually cropped tight, and detectors need a quiet zone. The IDAT is
  /// zlib-compressed (stdlib) with filter type 0 per row. Returns null when
  /// [raw] does not hold width×height×3 bytes.
  static Uint8List? _rgbToPng(List<int> raw, int width, int height) {
    final expected = width * height * 3;
    if (raw.length < expected) return null;
    final marginX = width < 40 ? width : width ~/ 4;
    final marginY = height < 40 ? height : height ~/ 4;
    final paddedW = width + marginX * 2;
    final paddedH = height + marginY * 2;
    final stride = paddedW * 3;

    // White canvas with the source rows copied into the middle.
    final canvasLen = paddedH * stride;
    final pixels = Uint8List(canvasLen)..fillRange(0, canvasLen, 0xFF);
    for (var y = 0; y < height; y++) {
      final dstStart = (marginY + y) * stride + marginX * 3;
      pixels.setRange(dstStart, dstStart + width * 3, raw, y * width * 3);
    }

    // Scanlines: each row prefixed with filter byte 0 (None). Thin barcode
    // strips are repeated vertically — ML Kit's 1D detection needs the bars
    // to have enough height, and identical rows are equivalent to a taller
    // barcode with the same payload.
    final rowRepeat =
        paddedH < 300 ? (300 / paddedH).ceil().clamp(1, 12) : 1;
    final scan = Uint8List(paddedH * rowRepeat * (stride + 1));
    var scanPos = 0;
    for (var rep = 0; rep < rowRepeat; rep++) {
      for (var y = 0; y < paddedH; y++) {
        scan[scanPos] = 0; // filter type None
        scan.setRange(
          scanPos + 1,
          scanPos + 1 + stride,
          pixels,
          y * stride,
        );
        scanPos += stride + 1;
      }
    }
    final idat = ZLibCodec(level: 1).encode(scan);
    final pngHeight = paddedH * rowRepeat;

    final out = BytesBuilder();
    out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // signature

    final ihdr = ByteData(13);
    ihdr.setUint32(0, paddedW, Endian.big);
    ihdr.setUint32(4, pngHeight, Endian.big);
    ihdr.setUint8(8, 8); // bit depth
    ihdr.setUint8(9, 2); // color type: truecolor RGB
    ihdr.setUint8(10, 0); // compression
    ihdr.setUint8(11, 0); // filter
    ihdr.setUint8(12, 0); // interlace
    out.add(_pngChunk('IHDR', ihdr.buffer.asUint8List()));
    out.add(_pngChunk('IDAT', idat));
    out.add(_pngChunk('IEND', const []));
    return out.toBytes();
  }

  static Uint8List _pngChunk(String type, List<int> data) {
    final chunk = BytesBuilder();
    final len = ByteData(4)..setUint32(0, data.length, Endian.big);
    chunk.add(len.buffer.asUint8List());
    chunk.add(type.codeUnits);
    chunk.add(data);
    final crc = ByteData(4)
      ..setUint32(0, _crc32(<int>[...type.codeUnits, ...data]), Endian.big);
    chunk.add(crc.buffer.asUint8List());
    return chunk.toBytes();
  }

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(List<int> data, [int crc = 0]) {
    crc ^= 0xFFFFFFFF;
    for (final byte in data) {
      crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }

  // --- PDF object scanning -------------------------------------------------

  /// Scans the latin1-decoded PDF for `n 0 obj … endobj` objects and cuts
  /// each into dict part and stream payload. Latin1 maps bytes 1:1, so the
  /// string offsets equal the byte offsets and [bytes] can be sliced.
  static Map<int, _PdfObject> _scanObjects(String pdf, Uint8List bytes) {
    final objects = <int, _PdfObject>{};
    for (final m in _objHeaderRe.allMatches(pdf)) {
      final number = int.parse(m.group(1)!);
      final dictStart = m.end;
      final streamIdx = pdf.indexOf('stream', dictStart);
      final nextObj = _objHeaderRe
          .allMatches(pdf, m.end)
          .map((n) => n.start)
          .fold<int?>(null, (a, b) => a == null ? b : (b < a ? b : a));
      final endObj = pdf.indexOf('endobj', dictStart);

      String dict;
      Uint8List? payload;
      if (streamIdx != -1 &&
          (nextObj == null || streamIdx < nextObj) &&
          (endObj == -1 || streamIdx < endObj)) {
        dict = pdf.substring(dictStart, streamIdx);
        var dataStart = streamIdx + 'stream'.length;
        if (pdf.startsWith('\r\n', dataStart)) dataStart += 2;
        if (pdf.startsWith('\n', dataStart)) dataStart += 1;
        final dataEnd = pdf.indexOf('endstream', dataStart);
        if (dataEnd != -1) {
          payload = Uint8List.sublistView(bytes, dataStart, dataEnd);
        }
      } else {
        dict = pdf.substring(dictStart, endObj == -1 ? pdf.length : endObj);
      }
      objects[number] = _PdfObject(number, dict, payload);
    }
    return objects;
  }

  // --- ToUnicode CMaps -----------------------------------------------------

  /// Parses `beginbfrange`/`beginbfchar` entries of a ToUnicode CMap into a
  /// CID -> glyph-string table. Supports the range form with single target
  /// (`<a> <b> <c>`) and with an array of targets (`<a> <b> [<c1> <c2> …]`),
  /// which is what the Qt-produced voucher PDFs use. Both block types are
  /// scoped to their begin/end markers — matching globally would pair up the
  /// hex tokens *inside* a bfrange array as bogus bfchar entries.
  static Map<int, String>? _parseCMap(_PdfObject? obj) {
    if (obj == null) return null;
    final cmap = obj.decodedString();
    if (cmap == null) return null;
    final map = <int, String>{};

    for (final block in _bfrangeBlockRe.allMatches(cmap)) {
      for (final m in _bfrangeRe.allMatches(block.group(1)!)) {
        final start = int.parse(m.group(1)!, radix: 16);
        final end = int.parse(m.group(2)!, radix: 16);
        final single = m.group(3);
        final array = m.group(4);
        if (array != null) {
          final targets = _hexTokenRe
              .allMatches(array)
              .map((t) => _hexToString(t.group(1)!))
              .toList();
          for (var i = 0; start + i <= end && i < targets.length; i++) {
            map[start + i] = targets[i];
          }
        } else if (single != null) {
          final base = _hexToString(single);
          for (var cid = start; cid <= end; cid++) {
            map[cid] = _incrementedGlyph(base, cid - start);
          }
        }
      }
    }

    for (final block in _bfcharBlockRe.allMatches(cmap)) {
      for (final m in _bfcharRe.allMatches(block.group(1)!)) {
        map[int.parse(m.group(1)!, radix: 16)] = _hexToString(m.group(2)!);
      }
    }
    return map;
  }

  /// Advances the last UTF-16 code unit of a range target by [delta]
  /// (standard bfrange semantics for single-unit targets).
  static String _incrementedGlyph(String base, int delta) {
    if (base.isEmpty || delta == 0) return base;
    final units = base.codeUnits;
    final last = units.last + delta;
    return String.fromCharCodes([...units.sublist(0, units.length - 1), last]);
  }

  // --- Content streams -----------------------------------------------------

  static String _extractStreamText(String content, Map<String, _FontInfo> fonts) {
    final buffer = StringBuffer();
    String? currentFont;
    for (final m in _textOpRe.allMatches(content)) {
      final fontSwitch = m.group(1);
      if (fontSwitch != null) {
        currentFont = fontSwitch;
        continue;
      }
      if (m.group(0) == 'BT') {
        buffer.writeln();
        continue;
      }
      final font = fonts[currentFont];
      final hex = m.group(2);
      if (hex != null) {
        // One or more consecutive hex strings before Tj each carry glyphs.
        for (final t in _hexTokenRe.allMatches(hex)) {
          buffer.write(_decodeHexShow(t.group(1)!, font));
        }
        continue;
      }
      final array = m.group(3);
      if (array != null) {
        for (final t in _hexTokenRe.allMatches(array)) {
          buffer.write(_decodeHexShow(t.group(1)!, font));
        }
        continue;
      }
      final literal = m.group(4);
      if (literal != null) {
        buffer.write(_decodeLiteralShow(literal, font));
      }
    }
    return buffer.toString();
  }

  static String _decodeHexShow(String hexBody, _FontInfo? font) {
    final hex = hexBody.replaceAll(RegExp(r'\s'), '');
    if (hex.isEmpty) return '';
    final twoByte = font?.isTwoByte ?? false;
    final step = twoByte ? 4 : 2;
    final buffer = StringBuffer();
    for (var i = 0; i + step <= hex.length; i += step) {
      final cid = int.parse(hex.substring(i, i + step), radix: 16);
      buffer.write(font?.cmap?[cid] ?? '');
    }
    return buffer.toString();
  }

  static String _decodeLiteralShow(String raw, _FontInfo? font) {
    final bytes = _unescapeLiteral(raw);
    if (font?.cmap == null) return latin1.decode(bytes, allowInvalid: true);
    final step = font!.isTwoByte ? 2 : 1;
    final buffer = StringBuffer();
    for (var i = 0; i + step <= bytes.length; i += step) {
      var cid = 0;
      for (var b = 0; b < step; b++) {
        cid = (cid << 8) | bytes[i + b];
      }
      buffer.write(font.cmap![cid] ?? '');
    }
    return buffer.toString();
  }

  /// Unescapes PDF literal-string escapes into bytes.
  static Uint8List _unescapeLiteral(String raw) {
    final out = BytesBuilder();
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c != r'\') {
        out.addByte(raw.codeUnitAt(i) & 0xFF);
        continue;
      }
      i++;
      if (i >= raw.length) break;
      final e = raw[i];
      switch (e) {
        case 'n':
          out.addByte(10);
        case 'r':
          out.addByte(13);
        case 't':
          out.addByte(9);
        case 'b':
          out.addByte(8);
        case 'f':
          out.addByte(12);
        case r'\':
        case '(':
        case ')':
          out.addByte(e.codeUnitAt(0) & 0xFF);
        default:
          // Octal escape: up to three digits.
          if (e.contains(RegExp('[0-7]'))) {
            var value = 0;
            var digits = 0;
            while (digits < 3 &&
                i < raw.length &&
                RegExp('[0-7]').hasMatch(raw[i])) {
              value = value * 8 + int.parse(raw[i]);
              i++;
              digits++;
            }
            i--;
            out.addByte(value & 0xFF);
          } else {
            out.addByte(e.codeUnitAt(0) & 0xFF);
          }
      }
    }
    return out.toBytes();
  }

  // --- Field extraction ----------------------------------------------------

  /// The printed card number: grouped digit blocks ("2112 2462 7680 2960 28"
  /// or a 16-digit "9840 1234 5678 9012"), or a bare 15-22 digit run.
  static String? _findCardNumber(String text) {
    final grouped = _groupedNumberRe.allMatches(text);
    for (final m in grouped) {
      final digits = m.group(0)!.replaceAll(' ', '');
      if (digits.length >= 15 && digits.length <= 22) return digits;
    }
    final bare = RegExp(r'(?<!\d)\d{16}(?!\d)').firstMatch(text);
    if (bare != null) return bare.group(0);
    return null;
  }

  static String? _findPin(String text) {
    final m =
        RegExp(r'PIN\s*[:\-]?\s*(\d{4})(?!\d)').firstMatch(text) ??
            RegExp(r'(?<![\dA-Za-z])PIN\D{0,8}?(\d{4})(?!\d)')
                .firstMatch(text);
    return m?.group(1);
  }

  static String? _findSerial(String text) {
    final card = _findCardNumber(text);
    for (final m in _digitRunRe.allMatches(text)) {
      final run = m.group(0)!;
      if (run != card) return run;
    }
    return null;
  }

  static double? _findValue(String text) {
    final m = _valueRe.firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  static final _objHeaderRe = RegExp(r'(?<=\s)(\d+)\s+0\s+obj');
  static final _fontDictRe = RegExp(r'/Font\s*<<([\s\S]*?)>>');
  static final _fontRefRe = RegExp(r'/(F\w+)\s+(\d+)\s+0\s+R');
  static final _toUnicodeRe = RegExp(r'/ToUnicode\s+(\d+)\s+0\s+R');
  static final _bfrangeBlockRe = RegExp(r'beginbfrange([\s\S]*?)endbfrange');
  static final _bfcharBlockRe = RegExp(r'beginbfchar([\s\S]*?)endbfchar');
  static final _bfrangeRe = RegExp(
    r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(?:<([0-9A-Fa-f]+)>|\[([\s\S]*?)\])',
  );
  static final _bfcharRe = RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>');
  static final _hexTokenRe = RegExp(r'<([0-9A-Fa-f\s]+)>');
  static final _textOpRe = RegExp(
    r'/(\w+)\s+[\d.]+\s+Tf'
    r'|BT'
    r'|((?:<[0-9A-Fa-f\s]+>\s*)+)\s*Tj'
    r'|\[((?:[^\[\]\\]|\\[\s\S])*?)\]\s*TJ'
    r'|\(((?:\\.|[^\\()])*)\)\s*(?:Tj|\x27)',
  );
  static final _groupedNumberRe =
      RegExp(r'(?<!\d)((?:\d{4}[ ]){2,5}\d{2,4})(?!\d)');
  static final _digitRunRe = RegExp(r'(?<!\d)\d{16,20}(?!\d)');
  static final _valueRe = RegExp(r'(\d{1,5}(?:[.,]\d{1,2})?)\s*(?:CHF|Fr\.?)(?!\w)');
}

class _PdfObject {
  _PdfObject(this.number, this.dict, this.payload);

  final int number;
  final String dict;
  final Uint8List? payload;

  /// The stream payload inflated (FlateDecode) or raw; null for objects
  /// without a stream. Returns latin1 text — good enough for operators and
  /// CMaps, which are ASCII-structured.
  String? decodedString() {
    final payload = this.payload;
    if (payload == null) return null;
    List<int> data = payload;
    try {
      data = ZLibCodec().decode(payload);
    } catch (_) {
      // Uncompressed or unsupported filter; use the raw bytes.
    }
    return latin1.decode(data, allowInvalid: true);
  }
}

class _FontInfo {
  _FontInfo({required this.isTwoByte, this.cmap});

  final bool isTwoByte;
  final Map<int, String>? cmap;
}

/// Decodes a UTF-16BE hex string (CMap targets) into a Dart string.
String _hexToString(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  final units = <int>[];
  for (var i = 0; i + 4 <= clean.length; i += 4) {
    units.add(int.parse(clean.substring(i, i + 4), radix: 16));
  }
  return String.fromCharCodes(units);
}
