import 'dart:convert';

import 'parser.dart';

/// Pure parser for the JSON answer of `POST /explore/giftyBalanceV2/gifty`,
/// shared by the hidden-WebView service and the visible manual-check screen.
///
/// Success shape (verified against a live card, November 2026):
/// ```json
/// {
///   "card_id": "e429933a-…",
///   "status": "ACTIVE",
///   "card_number": "211224627680296028",
///   "serial_number": "200000000018022770",
///   "balance": { "amount": 0, "currency": "CHF" },
///   "activated_at": "2026-10-09 06:44:42",
///   "expires_at": "2031-10-31 22:59:59",
///   "lot": { … }
/// }
/// ```
/// Notes: `status` is an English word ("ACTIVE"/"REDEEMED"/…), the balance is
/// a nested object with an integer `amount`, and `expires_at` is an ISO
/// timestamp — a fully spent card keeps status "ACTIVE" with amount 0.
/// Error shape: `{"code": 4002, "message": "…", "description": "…"}`.
class GiftyApiParser {
  GiftyApiParser._();

  /// Outcome for a JSON map payload: [GiftyApiOutcome.errorKey] is null on
  /// success. Returns null when the payload is not a JSON object or parses to
  /// no usable result — the caller then falls back to the page-text scan.
  static GiftyApiOutcome? parse(String rawPayload) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      return null;
    }
    if (body == null) return null;

    // API error shape: {"code":4002,"message":"...","description":"..."}
    final hasBalanceLike =
        body.keys.any(_looksLikeBalanceKey) || _deepFindBalance(body) != null;
    if (!hasBalanceLike && body['message'] != null) {
      final description = (body['description'] ?? body['message']).toString();
      // 4002 = card number rejected; anything else surfaces as a generic
      // API error with the description as detail.
      final isCardNumberError = body['code'] == 4002 ||
          description.toLowerCase().contains('card number');
      return GiftyApiOutcome(
        result: BalanceResult(raw: rawPayload),
        errorKey: isCardNumberError
            ? RefreshErrors.cardNotFound
            : RefreshErrors.apiError,
        errorDetail: isCardNumberError ? null : description,
      );
    }

    final result = BalanceResult(raw: rawPayload);
    result.balance = _deepFindBalance(body);
    final amountWasInteger = _amountWasInteger(body);
    final statusText = _deepFindString(body, _looksLikeStatusKey);
    if (statusText != null) result.status = BalanceParser.parseStatus(statusText);
    final expiryText = _deepFindString(body, _looksLikeExpiryKey) ??
        _deepFindDateValue(body);
    if (expiryText != null) result.expiryDate = BalanceParser.parseExpiry(expiryText);

    if (result.isSuccess) {
      return GiftyApiOutcome(result: result, amountIsInteger: amountWasInteger);
    }
    return null;
  }

  /// True when the balance amount arrived as a bare integer. The gifty API
  /// reports minor units (rappen) for some cards — 10375 means 103.75 CHF —
  /// but whole-franc balances would be integers too. Callers confirm the
  /// unit against the rendered page before trusting such a value.
  static bool _amountWasInteger(Map<String, dynamic> body) {
    final v = _deepFindRawBalance(body);
    return v is int;
  }

  static Object? _deepFindRawBalance(Object? node) {
    if (node is Map<String, dynamic>) {
      for (final entry in node.entries) {
        if (_looksLikeBalanceKey(entry.key)) {
          final v = entry.value;
          if (v is num) return v;
        }
      }
      for (final v in node.values) {
        final r = _deepFindRawBalance(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _deepFindRawBalance(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// True when the API balance is an integer big enough to be ambiguous
  /// between "whole francs" and "rappen" — callers should confirm it against
  /// the rendered page (which shows the formatted truth) before saving.
  static bool needsPageConfirmation(GiftyApiOutcome outcome) {
    final b = outcome.result.balance;
    return outcome.amountIsInteger && b != null && b >= 20;
  }

  static bool _looksLikeBalanceKey(String key) =>
      RegExp(r'balance|amount|guthaben|value|restbetrag', caseSensitive: false)
          .hasMatch(key);

  static bool _looksLikeStatusKey(String key) =>
      RegExp(r'status|state', caseSensitive: false).hasMatch(key);

  static bool _looksLikeExpiryKey(String key) =>
      RegExp(r'expir|valid|gültig|gueltig|until|date', caseSensitive: false)
          .hasMatch(key);

  static double? _deepFindBalance(Object? node) {
    if (node is Map<String, dynamic>) {
      for (final entry in node.entries) {
        if (_looksLikeBalanceKey(entry.key)) {
          final v = entry.value;
          final parsed = v is num
              ? v.toDouble()
              : v is String
                  ? BalanceParser.parseBalance(v)
                  : null;
          if (parsed != null) return parsed;
        }
      }
      for (final v in node.values) {
        final r = _deepFindBalance(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _deepFindBalance(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  static String? _deepFindString(Object? node, bool Function(String key) match) {
    if (node is Map<String, dynamic>) {
      for (final entry in node.entries) {
        final v = entry.value;
        if (match(entry.key) && v is String && v.isNotEmpty) return v;
      }
      for (final v in node.values) {
        final r = _deepFindString(v, match);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _deepFindString(v, match);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Finds any string value anywhere in the payload containing a
  /// DD.MM.YYYY or ISO date.
  static String? _deepFindDateValue(Object? node) {
    final dateRe = RegExp(r'\d{1,2}\.\d{1,2}\.\d{4}|\d{4}-\d{2}-\d{2}');
    if (node is Map<String, dynamic>) {
      for (final v in node.values) {
        final r = _deepFindDateValue(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _deepFindDateValue(v);
        if (r != null) return r;
      }
    } else if (node is String && dateRe.hasMatch(node)) {
      return node;
    }
    return null;
  }
}

/// The result of parsing one gifty API payload.
class GiftyApiOutcome {
  GiftyApiOutcome({
    required this.result,
    this.errorKey,
    this.errorDetail,
    this.amountIsInteger = false,
  });

  final BalanceResult result;

  /// Locale-neutral error key (see [RefreshErrors]); null on success.
  final String? errorKey;
  final String? errorDetail;

  /// True when the balance arrived as a bare integer — possibly minor
  /// units (rappen). See [GiftyApiParser.needsPageConfirmation].
  final bool amountIsInteger;
}
