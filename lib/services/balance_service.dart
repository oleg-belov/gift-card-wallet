import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'gifty_api.dart';
import 'gifty_api_client.dart';
import 'parser.dart';

export 'parser.dart' show BalanceParser, BalanceResult, RefreshErrors;

/// Balance-check sources, tried in order per card.
///
/// 1. lidl.ch "Guthabenabfrage": the form lives in the main frame
///    (Vue component AGiftyBalanceCheck) and FriendlyCaptcha solves itself
///    via proof-of-work, so the whole flow can run in a hidden WebView.
/// 2. lidl-giftcards.ch balance-check: the TX-Gate form is embedded in a
///    cross-origin iframe and cannot be scripted from the parent page; we
///    load the iframe URL directly with a Referer header and fall back to a
///    generic fill heuristic.
class BalanceCheckSource {
  const BalanceCheckSource({
    required this.label,
    required this.url,
    this.referer,
    this.fillScript,
    this.fallbackFillScript = false,
  });

  final String label;
  final String url;
  final String? referer;

  /// Selector-based fill script for known page structures; when null the
  /// generic heuristic fill is used.
  final String? fillScript;
  final bool fallbackFillScript;
}

const BalanceCheckSource kPrimarySource = BalanceCheckSource(
  label: 'lidl.ch',
  url:
      'https://www.lidl.ch/c/de-CH/guthabenabfrage-fuer-einkaufsgutscheine/s10077601',
  fillScript: kLidlChFillScript,
);

const BalanceCheckSource kFallbackSource = BalanceCheckSource(
  label: 'lidl-giftcards.ch',
  url: 'https://balancechecks.tx-gate.com/balancechecks/balance.php?cid=64',
  referer: 'https://www.lidl-giftcards.ch/de-ch/balance-check',
  fallbackFillScript: true,
);

const List<BalanceCheckSource> kBalanceCheckSources = [
  kPrimarySource,
  kFallbackSource,
];

/// The JSON API the balance form posts to (captured live, November 2026):
/// `{"cardNumber","pinNumber","country","locale","frcCaptchaToken"}`.
const String kGiftyApiUrl =
    'https://www.lidl.ch/explore/giftyBalanceV2/gifty';

/// Android WebView user agents carry a "; wv" marker that bot filters
/// (Lidl's edge is served by Myra) use to block the balance API — the POST
/// then answers with a challenge body ("/") instead of JSON and the form
/// shows "Bitte gültige Daten eingeben". A clean Chrome Mobile UA passes.
const String kChromeMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 16; SM-S928B) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/157.0.0.0 Mobile Safari/537.36';

/// JavaScript injected at document start. Hooks fetch + XHR so the app can
/// read the balance API response (e.g. /giftyBalanceV2/gifty) exactly, and
/// dismisses cookie-consent overlays that would sit on top of forms.
/// Auto-accepts the cookie-consent wall Lidl shows before the balance
/// form renders ("Bevor es weitergeht… / Zustimmen"). Runs in ALL frames
/// (consent managers often live in iframes) on a timer, so it catches the
/// dialog whenever it appears. Clicking repeatedly is harmless.
const String kConsentScript = r'''
(function() {
  if (window.__lidlConsentTimer) return;
  window.__lidlConsentTimer = setInterval(function() {
    var candidates = document.querySelectorAll(
      'button, [role="button"], input[type="button"], input[type="submit"], a');
    for (var i = 0; i < candidates.length; i++) {
      var b = candidates[i];
      if (!b) continue;
      var rect = b.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) continue;
      var text = (b.innerText || b.textContent || '').replace(/\s+/g, ' ').trim();
      if (/^(Zustimmen|Alles\s*Zustimmen|Alle\s*akzeptieren|Akzeptieren|Accept(\s*all)?|Agree)$/i.test(text)) {
        b.click();
        return;
      }
    }
  }, 1000);
})();
''';

const String kHookScript = '''
(function() {
  if (window.__lidlGiftHooked) return;
  window.__lidlGiftHooked = true;
  window.__lidlGiftResult = null;
  window.__lidlGiftRequest = null;
  var HOOK = '/giftyBalanceV2/gifty';
  function store(text) { window.__lidlGiftResult = text; }
  try {
    if (window.fetch) {
      var origFetch = window.fetch;
      window.fetch = function() {
        var args = arguments;
        var url = typeof args[0] === 'string' ? args[0]
                  : (args[0] && args[0].url) || '';
        try {
          var body = (args[1] && args[1].body) || '';
          if (url.indexOf(HOOK) !== -1 && body) {
            window.__lidlGiftRequest = String(body);
          }
        } catch (e) {}
        return origFetch.apply(this, arguments).then(function(resp) {
          try {
            var respUrl = resp.url || '';
            if (url.indexOf(HOOK) !== -1 || respUrl.indexOf(HOOK) !== -1) {
              resp.clone().text().then(store).catch(function() {});
            }
          } catch (e) {}
          return resp;
        });
      };
    }
    var XHR = XMLHttpRequest.prototype;
    var origOpen = XHR.open;
    XHR.open = function(method, url) { this.__lidlUrl = url; return origOpen.apply(this, arguments); };
    var origSend = XHR.send;
    XHR.send = function() {
      var xhr = this;
      xhr.addEventListener('load', function() {
        try {
          if (xhr.__lidlUrl && xhr.__lidlUrl.indexOf(HOOK) !== -1) {
            store(xhr.responseText);
          }
        } catch (e) {}
      });
      return origSend.apply(this, arguments);
    };
  } catch (e) {}
  // Auto-dismiss common cookie-consent buttons (lidl-giftcards.ch).
  document.addEventListener('DOMContentLoaded', function() {
    var candidates = document.querySelectorAll(
      '.cookie-alert-extended-button, button[id*=consent], button[class*=consent]');
    for (var i = 0; i < candidates.length; i++) candidates[i].click();
  });
})();
''';

/// Fill-only script for the visible manual-check page: fills card number
/// and PIN so the user only solves the captcha and taps ABFRAGEN.
/// Placeholders __CARD__ and __PIN__ are replaced before injection.
const String kLidlChPrefillScript = '''
(function() {
  var root = document.querySelector('.AGiftyBalanceCheck');
  if (!root) return 'no-form';
  var card = root.querySelector('.AGiftyBalanceCheck__input-card-number input');
  var pin = root.querySelector('input[type="password"]');
  if (!card || !pin) return 'no-inputs';
  function setVueValue(el, val) {
    var desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    desc.set.call(el, val);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  setVueValue(card, '__CARD__');
  setVueValue(pin, '__PIN__');
  return 'filled';
})();
''';

/// Fill + submit script for the lidl.ch AGiftyBalanceCheck Vue form.
/// Placeholders __CARD__ and __PIN__ are replaced before injection.
const String kLidlChFillScript = '''
(function() {
  var root = document.querySelector('.AGiftyBalanceCheck');
  if (!root) return 'no-form';
  var card = root.querySelector('.AGiftyBalanceCheck__input-card-number input');
  var pin = root.querySelector('input[type="password"]');
  if (!card || !pin) return 'no-inputs';
  function setVueValue(el, val) {
    var desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    desc.set.call(el, val);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  setVueValue(card, '__CARD__');
  setVueValue(pin, '__PIN__');
  var btn = null;
  var buttons = root.querySelectorAll('button');
  for (var i = 0; i < buttons.length; i++) {
    if (/ABFRAGEN/i.test(buttons[i].textContent || '')) { btn = buttons[i]; break; }
  }
  if (!btn) return 'no-button';
  btn.click();
  return 'submitted';
})();
''';

/// Generic fill for unknown forms: first visible text-ish input = card,
/// first password or 4-digit numeric input = PIN, first matching button
/// submits.
const String kGenericFillScript = '''
(function() {
  var inputs = Array.prototype.slice.call(document.querySelectorAll('input'))
    .filter(function(el) { return !el.disabled && el.type !== 'hidden' && el.type !== 'checkbox'; });
  if (!inputs.length) return 'no-inputs';
  var card = inputs[0];
  var pin = null;
  for (var i = 1; i < inputs.length; i++) {
    if (inputs[i].type === 'password' || inputs[i].type === 'tel' || inputs[i].type === 'number') { pin = inputs[i]; break; }
  }
  if (!pin) return 'no-pin';
  function setValue(el, val) {
    var desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    desc.set.call(el, val);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  setValue(card, '__CARD__');
  setValue(pin, '__PIN__');
  var btn = document.querySelector('button[type="submit"], input[type="submit"]');
  if (!btn) {
    var all = document.querySelectorAll('button');
    for (var j = 0; j < all.length; j++) {
      if (/ABFRAGEN|PRÜFEN|PRUEFEN|ANZEIGEN|PRÜF|CHECK|BALANCE/i.test(all[j].textContent || '')) { btn = all[j]; break; }
    }
  }
  if (!btn) return 'no-button';
  btn.click();
  return 'submitted';
})();
''';

/// Whether the fetch/XHR hook is injected into the balance page. Experiment
/// (2026-11-15): disabling it did NOT change the edge's behavior, so the
/// hook is not a bot signal and stays on — it gives the exact API payload.
const bool kFetchHookEnabled = true;

/// Direct Cronet POST (Chrome-grade TLS) with a fresh captcha token on the
/// retry attempt. FriendlyCaptcha tokens are SINGLE-USE — this only fires
/// AFTER the first in-page submission failed and the page was reloaded for
/// a fresh token, so it can no longer burn attempt 1's submission. The
/// in-page submit still follows on the same fresh page if the edge
/// challenges the Cronet request.
const bool kDirectApiEnabled = true;

/// Debug-only test hook: forces the first in-page submission attempt to
/// fail so the attempt-2 retry (fresh page → direct Cronet POST → in-page)
/// can be exercised end-to-end without waiting for a real edge challenge.
/// Set at build time:
/// `flutter build apk --debug --dart-define=E2E_FORCE_FIRST_ATTEMPT_FAIL=true`
/// Always false in release builds (the kDebugMode gate).
const bool kDebugForceFirstAttemptFail =
    kDebugMode &&
    bool.fromEnvironment('E2E_FORCE_FIRST_ATTEMPT_FAIL');

/// Outcome of a single card check.
class RefreshOutcome {
  RefreshOutcome({
    required this.result,
    this.errorKey,
    this.errorDetail,
    this.needsCaptchaHelp = false,
  });

  final BalanceResult result;

  /// Locale-neutral error key (see [RefreshErrors]); null on success.
  final String? errorKey;

  /// Optional technical detail (source label, JS return value, API message).
  final String? errorDetail;
  final bool needsCaptchaHelp;
}

/// Error keys are locale-neutral strings (see [RefreshErrors] in
/// parser.dart, re-exported here) mapped to localized text in the UI.

/// Reads the solved FriendlyCaptcha token and the page cookies via plain DOM
/// access — no fetch hooking, so the page stays untouched for the edge.
const String kReadCaptchaScript = '''
(function() {
  var frc = document.querySelector('input[name="frc-captcha-solution"]');
  return JSON.stringify({
    token: frc ? String(frc.value || '') : '',
    cookie: String(document.cookie || '')
  });
})();
''';

/// Drives the hidden WebView through the balance-check pages.
class BalanceService {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  int _token = 0; // incremented to cancel in-flight polling loops
  GiftyApiClient? _apiClient;

  static const _pageLoadTimeout = Duration(seconds: 12);
  // FriendlyCaptcha's proof-of-work difficulty varies per challenge —
  // measured on an emulator: ~5 s in one run, >30 s in another.
  static const _captchaWaitTimeout = Duration(seconds: 25);
  static const _resultTimeout = Duration(seconds: 15);
  static const _pollInterval = Duration(milliseconds: 500);
  static const _stallNotifyAfter = Duration(seconds: 5);

  /// Hard overall budget for one checkCard call across all ladder attempts.
  /// Keeps the UI from hanging on a slow edge: the pre-warmed fast path
  /// finishes in well under this, a cold path typically lands ~25 s, and
  /// anything past the deadline surfaces as a failure with the manual
  /// captcha option one tap away.
  static const _checkDeadline = Duration(seconds: 35);

  Future<void> ensureStarted() async {
    if (_headless != null) return;
    final headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        userAgent: kChromeMobileUserAgent,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        if (kFetchHookEnabled)
          UserScript(
            source: kHookScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        UserScript(
          source: kConsentScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      ]),
    );
    await headless.run();
    _headless = headless;
    _controller = headless.webViewController;
  }

  bool _prewarmed = false;
  int _prewarmGen = 0;

  /// Loads the primary balance page ahead of time so its form is rendered
  /// and FriendlyCaptcha has already solved itself by the time the user
  /// taps "Check Balance" — the query then needs no page-load/PoW wait.
  /// Fire-and-forget; safe to call repeatedly (runs once per session, and
  /// a checkCard resets the flag so later checks re-warm after use).
  Future<void> prewarm() async {
    if (_prewarmed) return;
    _prewarmed = true;
    final gen = ++_prewarmGen;
    try {
      await ensureStarted();
      final controller = _controller;
      if (controller == null) {
        _prewarmed = false;
        return;
      }
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(kPrimarySource.url)),
      );
      // Wait until the form + captcha are ready, then keep the page parked.
      await _poll(
        timeout: _pageLoadTimeout + _captchaWaitTimeout,
        isCancelled: () => gen != _prewarmGen,
        probe: () async => _isFormReady(controller, kPrimarySource),
      );
      if (kDebugMode) {
        debugPrint('E2E: prewarm done');
      }
    } catch (_) {
      _prewarmed = false;
    }
  }

  Future<void> dispose() async {
    _token++;
    await _headless?.dispose();
    _headless = null;
    _controller = null;
  }

  /// Runs one card through all sources until a parseable result appears.
  Future<RefreshOutcome> checkCard({
    required String cardNumber,
    required String pin,
    void Function()? onStalled,
  }) async {
    _prewarmed = false; // this check consumes the parked page's token
    final myToken = ++_token;
    final deadline = DateTime.now().add(_checkDeadline);
    bool deadlineHit() => DateTime.now().isAfter(deadline);
    bool stalledNotified = false;

    String? lastErrorKey;
    String? lastErrorDetail;
    await ensureStarted();
    final controller = _controller;
    if (controller == null) {
      return RefreshOutcome(
        result: BalanceResult(raw: 'failed'),
        errorKey: RefreshErrors.webviewStart,
        needsCaptchaHelp: true,
      );
    }

    for (final source in kBalanceCheckSources) {
      // The primary source gets a 3-attempt ladder. FriendlyCaptcha tokens
      // are SINGLE-USE, so every attempt needs its own page reload (fresh
      // token):
      //   1-2: in-page submit (the proven transport),
      //   3:   direct Cronet POST — Chrome-grade TLS for when the edge is
      //        tough on WebView clients. Direct-only: a challenged Cronet
      //        request consumes its token, so nothing follows it.
      final attempts = source.fillScript != null ? 3 : 1;

      for (var attempt = 1; attempt <= attempts; attempt++) {
        if (attempt > 1) {
          // Budget spent — surface a failure instead of hanging.
          if (deadlineHit()) {
            if (kDebugMode) {
              debugPrint('CHECK RESULT ${source.label}: '
                  'key=noResult detail=(deadline hit)');
            }
            return RefreshOutcome(
              result: BalanceResult(raw: 'timeout'),
              errorKey: RefreshErrors.noResult,
              errorDetail: '${source.label} (timeout)',
              needsCaptchaHelp: true,
            );
          }
          // The edge throttles rapid-fire bursts — space the attempts out.
          await Future<void>.delayed(Duration(seconds: 4 * (attempt - 1)));
          if (myToken != _token || deadlineHit()) {
            if (kDebugMode) {
              debugPrint('CHECK RESULT ${source.label}: '
                  'key=noResult detail=(deadline hit during backoff)');
            }
            return RefreshOutcome(
              result: BalanceResult(raw: 'timeout'),
              errorKey: RefreshErrors.noResult,
              errorDetail: '${source.label} (timeout)',
              needsCaptchaHelp: true,
            );
          }
        }
        try {
          await controller
              .loadUrl(
                urlRequest: URLRequest(
                  url: WebUri(source.url),
                  headers: source.referer != null
                      ? {'Referer': source.referer!}
                      : null,
                ),
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => false,
              );
        } catch (e) {
          lastErrorKey = RefreshErrors.loadFailed;
          lastErrorDetail = '${source.label} ($e)';
          continue;
        }

        // Retries must wait for the reload to actually take over: the
        // ready-probe below would otherwise pass instantly on the stale
        // page (its captcha input may still hold the consumed token, and
        // the widget can re-solve there). JS globals do not survive
        // navigation — stamp the old document and wait for the stamp to
        // disappear.
        if (attempt > 1) {
          try {
            await controller.evaluateJavascript(
              source: 'window.__lidlGen = $attempt;',
            );
          } catch (_) {
            // Mid-navigation; the poll below handles it.
          }
          final navigated = await _poll(
            timeout: _pageLoadTimeout,
            isCancelled: () => myToken != _token || deadlineHit(),
            probe: () async {
              final raw = await _runJs(controller, '''
(function() {
  return JSON.stringify({
    gen: (window.__lidlGen === undefined) ? "" : String(window.__lidlGen)
  });
})();
''');
              final map = _asJsonMap(raw);
              if (map == null) return null;
              // Empty gen = the stamp is gone = a new document is in charge.
              return (map['gen'] as String?)?.isEmpty == true ? true : null;
            },
          );
          if (navigated != true) {
            lastErrorKey = RefreshErrors.formNotReady;
            lastErrorDetail = '${source.label} (reload)';
            continue;
          }
        }

        // Wait for the form + (primary source) captcha to become ready.
        final ready = await _poll(
          timeout: _pageLoadTimeout + _captchaWaitTimeout,
          isCancelled: () => myToken != _token || deadlineHit(),
          onTick: (elapsed) {
            if (!stalledNotified &&
                elapsed >= _stallNotifyAfter &&
                onStalled != null) {
              stalledNotified = true;
              onStalled();
            }
          },
          probe: () async => _isFormReady(controller, source),
        );

        if (myToken != _token) {
          return RefreshOutcome(
            result: BalanceResult(raw: 'cancelled'),
            errorKey: RefreshErrors.cancelled,
          );
        }

        if (ready != true) {
          lastErrorKey = RefreshErrors.formNotReady;
          lastErrorDetail = source.label;
          if (kDebugMode) {
            debugPrint('CHECK RESULT ${source.label}: '
                'key=formNotReady detail=(form never rendered)');
          }
          continue;
        }

        // Direct Cronet POST with this attempt's fresh token — only on the
        // last attempt, never after an in-page submission consumed the same
        // page's token. Returns null on an edge challenge; the in-page
        // submit below still takes its shot on this fresh page (worst case:
        // the known "captcha verification failed" answer).
        if (kDirectApiEnabled &&
            source.fillScript != null &&
            attempt == attempts) {
          final captcha =
              _asJsonMap(await _runJs(controller, kReadCaptchaScript));
          final captchaToken = captcha?['token'] as String? ?? '';
          if (captchaToken.length > 10) {
            final direct = await _tryDirectApi(
              cardNumber: cardNumber,
              pin: pin,
              captchaToken: captchaToken,
              cookies: captcha?['cookie'] as String? ?? '',
            );
            if (direct != null) return direct;
          }
        }

        final fillScript = source.fillScript ?? kGenericFillScript;
        final resolvedFill = fillScript
            .replaceAll('__CARD__', cardNumber)
            .replaceAll('__PIN__', pin);
        final filled = _asString(await _runJs(controller, resolvedFill));
        if (kDebugMode) {
          debugPrint('CHECK ${source.label}: fill=$filled (attempt $attempt)');
        }
        if (filled != 'submitted') {
          lastErrorKey = RefreshErrors.fillFailed;
          lastErrorDetail = '${source.label} ($filled)';
          continue;
        }

        // Wait for the API hook to capture a response, or the page text to
        // contain the result values.
        final result = await _awaitResult(
          controller,
          myToken,
          deadline: deadline,
          fillScript: resolvedFill,
        );
        if (myToken != _token) {
          return RefreshOutcome(
            result: BalanceResult(raw: 'cancelled'),
            errorKey: RefreshErrors.cancelled,
          );
        }
        if (result != null) {
          if (kDebugForceFirstAttemptFail && attempt <= 2) {
            // Test hook: pretend the in-page attempts failed so the ladder
            // reaches attempt 3 (fresh page → direct Cronet POST).
            if (kDebugMode) {
              debugPrint('E2E: FORCED attempt-$attempt failure — retrying');
            }
            lastErrorKey = RefreshErrors.noResult;
            lastErrorDetail = '${source.label} (forced)';
            continue;
          }
          if (kDebugMode) {
            final raw = result.result.raw;
            debugPrint('CHECK RESULT ${source.label}: key=${result.errorKey} '
                'detail=${result.errorDetail} '
                'raw=${raw.length > 400 ? raw.substring(0, 400) : raw}');
          }
          return result;
        }
        lastErrorKey = RefreshErrors.noResult;
        lastErrorDetail = source.label;
      }
    }

    return RefreshOutcome(
      result: BalanceResult(raw: 'failed'),
      errorKey: lastErrorKey ?? RefreshErrors.generic,
      errorDetail: lastErrorDetail,
      needsCaptchaHelp: true,
    );
  }

  /// Returns `true` when the page is ready to fill, `null` while it is
  /// still loading — never `false`, because the generic poll treats any
  /// non-null probe result as final (a plain `false` ended polling after a
  /// single probe, failing every check instantly).
  Future<bool?> _isFormReady(
    InAppWebViewController controller,
    BalanceCheckSource source,
  ) async {
    final raw = await _runJs(controller, '''
(function() {
  var frc = document.querySelector('input[name="frc-captcha-solution"]');
  var form = document.querySelector('.AGiftyBalanceCheck');
  var inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"])').length;
  return JSON.stringify({
    form: !!form,
    captchaSolved: !!(frc && frc.value && frc.value.length > 10),
    inputCount: inputs
  });
})();
''');
    final map = _asJsonMap(raw);
    if (kDebugMode) debugPrint('PROBE ${source.label}: $map');
    if (map == null) return null;
    if (source.fillScript != null) {
      // Primary source: form rendered AND FriendlyCaptcha proof-of-work done.
      return (map['form'] == true && map['captchaSolved'] == true) ? true : null;
    }
    // Fallback source: any usable inputs on the page.
    return ((map['inputCount'] as int? ?? 0) > 0) ? true : null;
  }

  Future<RefreshOutcome?> _awaitResult(
    InAppWebViewController controller,
    int myToken, {
    required DateTime deadline,
    required String? fillScript,
  }) async {
    String previousText = '';
    bool fcResubmitted = false;
    RefreshOutcome? hookStash;
    DateTime? hookStashAt;
    final outcome = await _poll<RefreshOutcome?>(
      timeout: _resultTimeout,
      isCancelled: () => myToken != _token || DateTime.now().isAfter(deadline),
      probe: () async {
        // 1) Read the visible page text every tick — it is the formatted
        //    truth and the cross-check for minor-unit amounts.
        final text = await _runJs(
          controller,
          '(function(){ return document.body ? document.body.innerText : ""; })();',
        );
        final pageText = _asString(text) ?? '';
        final pageChanged = pageText != previousText;
        BalanceResult? pageCandidate;
        if (pageChanged) {
          previousText = pageText;
          final parsed = BalanceParser.extractFromPageText(pageText);
          if (kDebugMode) {
            debugPrint('E2E: probe page='
                '${pageText.length > 150 ? pageText.substring(0, 150) : pageText} '
                '→ balance=${parsed.balance} status=${parsed.status}');
          }
          if (parsed.isSuccess) pageCandidate = parsed;
        }

        // 2) Exact API response captured by the fetch/XHR hook.
        final hookRaw = await _runJs(
          controller,
          '(function(){ return window.__lidlGiftResult ? String(window.__lidlGiftResult) : ""; })();',
        );
        final hookPayload = _asString(hookRaw);
        if (kDebugMode && hookPayload != null && hookPayload.isNotEmpty) {
          debugPrint('E2E: hook payload='
              '${hookPayload.length > 200 ? hookPayload.substring(0, 200) : hookPayload}');
          final requestRaw = await _runJs(
            controller,
            '(function(){ return window.__lidlGiftRequest ? String(window.__lidlGiftRequest) : ""; })();',
          );
          final requestBody = _asString(requestRaw) ?? '';
          if (requestBody.isNotEmpty) {
            // Show what the form actually submitted (token truncated).
            debugPrint('E2E: hook request='
                '${requestBody.length > 220 ? requestBody.substring(0, 220) : requestBody}');
          }
        }
        if (hookPayload != null && hookPayload.isNotEmpty) {
          // The site sometimes runs a two-step submit: the first click goes
          // out before the captcha token exists, the API answers
          // "frcCAPTCHA verification failed", the widget then solves, and
          // the form must be clicked again. Handle it automatically.
          if (!fcResubmitted &&
              fillScript != null &&
              hookPayload.contains('frcCAPTCHA verification failed')) {
            fcResubmitted = true;
            if (kDebugMode) {
              debugPrint('E2E: fc token rejected — waiting for solve, '
                  'then resubmitting');
            }
            await _poll(
              timeout: _captchaWaitTimeout,
              isCancelled: () =>
                  myToken != _token || DateTime.now().isAfter(deadline),
              probe: () async => _isFormReady(controller, kPrimarySource),
            );
            final again = _asString(await _runJs(controller, fillScript));
            if (kDebugMode) {
              debugPrint('E2E: fc resubmit=$again');
            }
            return null; // keep polling — the hook captures the new answer
          }
          final fromApi = GiftyApiParser.parse(hookPayload);
          if (fromApi != null) {
            final outcome = RefreshOutcome(
              result: fromApi.result,
              errorKey: fromApi.errorKey,
              errorDetail: fromApi.errorDetail,
            );
            // Minor-unit guard: the API reports some balances in rappen
            // (an integer 10375 means 103.75 CHF). Confirm against the
            // rendered panel before trusting such a value.
            if (!GiftyApiParser.needsPageConfirmation(fromApi)) {
              return outcome;
            }
            final pageBalance = pageCandidate?.balance;
            if (pageBalance != null) {
              final apiBalance = fromApi.result.balance ?? 0;
              if ((apiBalance / 100 - pageBalance).abs() < 0.005) {
                outcome.result.balance = pageBalance;
                if (kDebugMode) {
                  debugPrint('E2E: minor-unit fix api=$apiBalance '
                      '→ page=$pageBalance');
                }
              }
              return outcome;
            }
            // Result panel not rendered yet — hold the answer briefly so
            // the page can confirm the unit; otherwise keep the API value.
            hookStash ??= outcome;
            hookStashAt ??= DateTime.now();
            if (DateTime.now().difference(hookStashAt!) >
                const Duration(seconds: 6)) {
              return hookStash;
            }
            return null;
          }
        }

        // 3) Fallback: scan the visible page text.
        if (pageCandidate != null) {
          return RefreshOutcome(result: pageCandidate);
        }
        if (pageChanged) {
          if (pageText.contains('Bitte gültige Daten eingeben') ||
              pageText.toLowerCase().contains('error')) {
            final errKey = _apiErrorFromPage(pageText);
            return RefreshOutcome(
              result: BalanceParser.extractFromPageText(pageText),
              errorKey: errKey,
            );
          }
        }
        return null;
      },
    );
    return outcome;
  }

  /// Posts the balance request directly (Cronet, Chrome-grade TLS) and maps
  /// the JSON answer. Returns null when the endpoint answered with a
  /// non-JSON body (edge challenge) — the caller then falls back to the
  /// in-page submit.
  Future<RefreshOutcome?> _tryDirectApi({
    required String cardNumber,
    required String pin,
    required String captchaToken,
    required String cookies,
  }) async {
    _apiClient ??= GiftyApiClient();
    final body = await _apiClient!.fetchBalance(
      cardNumber: cardNumber,
      pin: pin,
      captchaToken: captchaToken,
      cookies: cookies,
    );
    if (kDebugMode) {
      final raw = jsonEncode(body);
      debugPrint('E2E: direct api body='
          '${raw.length > 300 ? raw.substring(0, 300) : raw}');
    }
    if (body == null) return null;
    final payload = jsonEncode(body);
    final outcome = GiftyApiParser.parse(payload);
    if (outcome == null) return null;
    if (kDebugMode) {
      // Same "CHECK RESULT" prefix as the in-page path — the smoke suite
      // waits for this marker regardless of which path delivered the answer.
      final raw = jsonEncode(outcome.result.raw);
      debugPrint('CHECK RESULT direct-cronet: key=${outcome.errorKey} '
          'detail=${outcome.errorDetail} '
          'raw=${raw.length > 400 ? raw.substring(0, 400) : raw}');
    }
    return RefreshOutcome(
      result: outcome.result,
      errorKey: outcome.errorKey,
      errorDetail: outcome.errorDetail,
    );
  }

  String? _apiErrorFromPage(String pageText) {
    if (pageText.contains('Bitte gültige Daten eingeben')) {
      return RefreshErrors.cardNotFound;
    }
    return RefreshErrors.apiError;
  }

  /// Normalizes WebView results: Android JSON-encodes string returns
  /// ("\"submitted\""), iOS may return raw values.
  String? _asString(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      final s = raw.trim();
      if (s.startsWith('"') && s.endsWith('"')) {
        try {
          return jsonDecode(s) as String;
        } catch (_) {
          return s;
        }
      }
      return s;
    }
    return raw.toString();
  }

  Future<Object?> _runJs(
    InAppWebViewController controller,
    String source,
  ) async {
    try {
      // A wedged webview can hang evaluateJavascript forever — the check
      // deadline only bounds the poll loop, not a hanging probe. Bound
      // every single JS call.
      return await controller.evaluateJavascript(source: source).timeout(
            const Duration(seconds: 8),
            onTimeout: () => 'js-timeout',
          );
    } catch (e) {
      return 'js-error: $e';
    }
  }

  /// Polls [probe] until it returns non-null or [timeout] elapses.
  Future<T?> _poll<T>({
    required Duration timeout,
    required Future<T?> Function() probe,
    required bool Function() isCancelled,
    void Function(Duration elapsed)? onTick,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled()) return null;
      onTick?.call(timeout - deadline.difference(DateTime.now()));
      try {
        final result = await probe();
        if (result != null) return result;
      } catch (_) {
        // Page mid-navigation; keep polling.
      }
      await Future<void>.delayed(_pollInterval);
    }
    return null;
  }

  Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      var s = raw.trim();
      // Android WebView JSON-encodes string results ("\"...\"").
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        if (decoded is String) {
          final inner = jsonDecode(decoded);
          if (inner is Map) return Map<String, dynamic>.from(inner);
        }
      } catch (_) {}
    }
    return null;
  }
}
