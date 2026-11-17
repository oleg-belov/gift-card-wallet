/// Decoding for codes captured by the camera scanner or the file import.
///
/// Real Lidl voucher barcodes (verified against a genuine PDF voucher,
/// November 2026) are GS1-128 Code 128 element strings:
///
/// ```
/// 01 04067534210134 90 211224627680296028
/// │  │              │  └─ AI (90): the printed card number
/// │  │              └─ AI (90) marker, retailer-defined data
/// │  └─ AI (01): GTIN-14 of the voucher product (one per denomination)
/// └─ AI (01) marker
/// ```
///
/// The balance-check portal however only accepts the bare card number, and
/// older/physical cards carry plain digit strings — both are handled here.
library;

class ScannedCode {
  const ScannedCode({required this.cardNumber, this.barcodeValue});

  /// The number the balance portal accepts (AI 90 content for GS1 codes).
  final String cardNumber;

  /// The full barcode payload when it is an element string, so the checkout
  /// screen can render exactly the bars the physical voucher carries.
  /// Null for bare digit strings, where card number and payload are equal.
  final String? barcodeValue;
}

/// Parses a raw scanned value into a [ScannedCode], or null when the value
/// cannot be a gift-card code.
ScannedCode? parseScannedCode(String raw) {
  var value = raw.trim();
  // Symbology identifiers ("]C1" for GS1-128) and GS/RS group separators
  // emitted by some scanners are not part of the logical content.
  if (value.startsWith(']C1') || value.startsWith(']e0') || value.startsWith(']Q3')) {
    value = value.substring(3).trim();
  }
  value = value
      .replaceAll('\u{001D}', '')
      .replaceAll('\u{001E}', '')
      .replaceAll(' ', '');

  // GS1 element string: AI (01) GTIN-14 followed by AI (90) card number.
  final gs1 = RegExp(r'^01(\d{14})90(\d{15,22})$').firstMatch(value);
  if (gs1 != null) {
    return ScannedCode(cardNumber: gs1.group(2)!, barcodeValue: value);
  }

  // Bare card number (Lidl portal accepts 15-22 digits).
  if (RegExp(r'^\d{15,22}$').hasMatch(value)) {
    return ScannedCode(cardNumber: value);
  }
  return null;
}
