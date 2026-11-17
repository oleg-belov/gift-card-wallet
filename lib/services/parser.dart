import '../models/gift_card.dart';

/// Parsers for the values shown by the lidl-giftcards.ch balance check:
/// Guthaben ("200.00 CHF"), Status ("Aktiv") and Gültigkeitsdatum ("31.10.2031").
class BalanceParser {
  /// Parses a balance string into a double.
  ///
  /// Accepts "200.00 CHF", "CHF 200.00", "2'000.00 CHF" (Swiss thousands
  /// separator), "1.999,90 CHF" (German decimal comma) and bare numbers.
  /// Returns null when no amount can be found.
  static double? parseBalance(String text) {
    final normalized = text
        .replaceAll('\u{00A0}', ' ') // non-breaking spaces around CHF
        .replaceAll('’', "'")
        .replaceAll("'", '')
        .trim();

    // German/Swiss decimal comma: digits , digits at the end of the amount.
    final commaMatch = RegExp(
      r'(\d{1,3}(?:\.\d{3})*|\d+),(\d{2})(?=\s*(?:CHF|Fr)?|$)',
    ).firstMatch(normalized);
    if (commaMatch != null && _hasDecimalCommaContext(normalized, commaMatch)) {
      final intPart = commaMatch.group(1)!.replaceAll('.', '');
      final fracPart = commaMatch.group(2)!;
      return double.tryParse('$intPart.$fracPart');
    }

    final dotMatch = RegExp(r'(\d+(?:\.\d{2})?)').firstMatch(normalized);
    if (dotMatch != null) {
      return double.tryParse(dotMatch.group(1)!);
    }
    return null;
  }

  static bool _hasDecimalCommaContext(String text, RegExpMatch match) {
    // A comma is a decimal separator when "CHF" follows the amount or the
    // integer part is grouped like 2.000,00. Bare "1,2" without CHF is
    // ambiguous and stays unparsed.
    final after = text.substring(match.end).trimLeft();
    return after.toUpperCase().startsWith('CHF') ||
        after.toUpperCase().startsWith('FR') ||
        match.group(1)!.contains('.');
  }

  /// Parses a status word into [GiftCardStatus].
  static GiftCardStatus parseStatus(String text) {
    final t = text.trim().toLowerCase();
    if (t.contains('abgelaufen') || t.contains('expired')) {
      return GiftCardStatus.abgelaufen;
    }
    if (t.contains('eingelöst') || t.contains('eingeloest') || t.contains('redeemed')) {
      return GiftCardStatus.eingeloest;
    }
    if (t.contains('aktiv') || t.contains('active') || t.contains('gültig') || t.contains('gueltig')) {
      return GiftCardStatus.aktiv;
    }
    return GiftCardStatus.unbekannt;
  }

  /// Converts a displayed date into the sortable ISO form "2031-10-31".
  /// Accepts the portal's "31.10.2031" (DD.MM.YYYY) and the API's
  /// "2031-10-31 22:59:59" (ISO with an optional trailing time). Returns
  /// null for anything unrecognized.
  static String? parseExpiry(String text) {
    final dot = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(text);
    if (dot != null) {
      final day = int.parse(dot.group(1)!);
      final month = int.parse(dot.group(2)!);
      final year = int.parse(dot.group(3)!);
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (iso != null) {
      final month = int.parse(iso.group(2)!);
      final day = int.parse(iso.group(3)!);
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return iso.group(0);
    }
    return null;
  }

  /// Fallback extraction: scans the whole visible page text and pulls out the
  /// three values in order (Guthaben, then Status, then Gültigkeitsdatum).
  /// Used when CSS selectors drift; each field may still come out null.
  static BalanceResult extractFromPageText(String pageText) {
    final result = BalanceResult(raw: pageText);

    final balanceMatch = RegExp(
      r"(\d[\d\.'’]*[,.]?\d{0,2})\s*(?:CHF|Fr\.?)",
    ).firstMatch(pageText) ??
        // Also accept the leading-currency word order: "CHF 200.00".
        RegExp(
          r"(?:CHF|Fr\.?)\s*(\d[\d\.'’]*[,.]?\d{0,2})",
        ).firstMatch(pageText);
    if (balanceMatch != null) {
      result.balance = parseBalance(balanceMatch.group(0)!);
    }

    for (final status in GiftCardStatus.values) {
      final label = giftCardStatusLabel(status);
      if (label != 'Unbekannt' && pageText.toLowerCase().contains(label.toLowerCase())) {
        // Prefer the most specific status word actually present; a card whose
        // page mentions "Abgelaufen" anywhere is treated as expired.
        result.status = status;
        break;
      }
    }

    final dateMatch = RegExp(r'\d{1,2}\.\d{1,2}\.\d{4}|\d{4}-\d{2}-\d{2}')
        .firstMatch(pageText);
    if (dateMatch != null) {
      result.expiryDate = parseExpiry(dateMatch.group(0)!);
    }

    return result;
  }
}

/// Locale-neutral error keys surfaced by fetchers; the UI maps them to
/// localized strings (see lib/utils/app_text.dart). Lives in the pure parser
/// so both the WebView service and the API payload parser can use it without
/// pulling in platform plugins.
class RefreshErrors {
  static const cancelled = 'cancelled';
  static const webviewStart = 'webviewStart';
  static const loadFailed = 'loadFailed';
  static const formNotReady = 'formNotReady';
  static const fillFailed = 'fillFailed';
  static const noResult = 'noResult';
  static const generic = 'generic';
  static const cardNotFound = 'cardNotFound';
  static const apiError = 'apiError';
}

/// The three values extracted from a balance-check result.
class BalanceResult {
  BalanceResult({
    required this.raw,
    this.balance,
    this.status = GiftCardStatus.unbekannt,
    this.expiryDate,
  });

  final String raw;
  double? balance;
  GiftCardStatus status = GiftCardStatus.unbekannt;
  String? expiryDate;

  bool get isSuccess => balance != null && status != GiftCardStatus.unbekannt;
}
