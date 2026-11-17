import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/gift_card.dart';
import '../services/balance_service.dart';
import '../services/gifty_api.dart';
import '../state/providers.dart';

/// Visible WebView fallback: when the hidden automation stalls (captcha,
/// bot checks), the user completes the balance check on screen. The same
/// fetch/XHR hook captures the API answer, and the app saves the result
/// automatically once it parses.
class ManualCheckScreen extends ConsumerStatefulWidget {
  const ManualCheckScreen({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<ManualCheckScreen> createState() => _ManualCheckScreenState();
}

class _ManualCheckScreenState extends ConsumerState<ManualCheckScreen> {
  InAppWebViewController? _controller;
  Timer? _pollTimer;
  bool _saved = false;
  String? _responseMessage;
  bool _ready = false;
  bool _prefilled = false;
  DateTime? _integralSince;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  GiftCard? _findCard() {
    final cards = ref.read(cardListProvider).value ?? const <GiftCard>[];
    for (final c in cards) {
      if (c.id == widget.cardId) return c;
    }
    return null;
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      final controller = _controller;
      if (controller == null || _saved || !mounted) return;
      try {
        // Prefill the form from the stored card once the page has rendered:
        // the user only solves the captcha and taps ABFRAGEN.
        if (!_prefilled) {
          final card = _findCard();
          if (card != null) {
            final raw = await controller
                .evaluateJavascript(
                  source: kLidlChPrefillScript
                      .replaceAll('__CARD__', card.cardNumber)
                      .replaceAll('__PIN__', card.pin),
                )
                .timeout(const Duration(seconds: 8), onTimeout: () => null);
            final result = raw?.toString().replaceAll('"', '').trim();
            if (result == 'filled') _prefilled = true;
          }
        }
        final hookRaw = await controller.evaluateJavascript(
          source:
              '(function(){ return window.__lidlGiftResult ? String(window.__lidlGiftResult) : ""; })();',
        ).timeout(const Duration(seconds: 8), onTimeout: () => null);
        final payload = _decodeString(hookRaw);
        GiftyApiOutcome? hookOutcome;
        if (payload != null && payload.isNotEmpty) {
          hookOutcome = GiftyApiParser.parse(payload);
          if (hookOutcome != null) {
            if (GiftyApiParser.needsPageConfirmation(hookOutcome)) {
              // Possible minor-unit amount (10375 rappen = 103.75 CHF):
              // hold off saving and let the page-text path below confirm
              // against the rendered "103.75 CHF" panel.
              _integralSince ??= DateTime.now();
            } else {
              await _handleOutcome(hookOutcome);
            }
          }
        }
        if (_saved || !mounted) return;

        final textRaw = await controller.evaluateJavascript(
          source:
              '(function(){ return document.body ? document.body.innerText : ""; })();',
        ).timeout(const Duration(seconds: 8), onTimeout: () => null);
        final pageText = _decodeString(textRaw) ?? '';
        final parsed = BalanceParser.extractFromPageText(pageText);
        if (parsed.isSuccess) {
          await _save(parsed);
        } else if (hookOutcome != null &&
            GiftyApiParser.needsPageConfirmation(hookOutcome) &&
            _integralSince != null &&
            DateTime.now().difference(_integralSince!) >
                const Duration(seconds: 8)) {
          // The page never rendered a parseable panel — trust the API
          // value rather than losing the result.
          await _handleOutcome(hookOutcome);
        }
      } catch (_) {
        // Mid-navigation; retry on next tick.
      }
    });
  }

  Future<void> _handleOutcome(GiftyApiOutcome outcome) async {
    if (outcome.errorKey != null) {
      setState(() {
        _responseMessage =
            outcome.errorDetail ?? outcome.errorKey;
      });
      return;
    }
    if (outcome.result.isSuccess) {
      await _save(outcome.result);
    }
  }

  Future<void> _save(BalanceResult result) async {
    final card = _findCard();
    if (card == null || _saved) return;
    _saved = true;
    _pollTimer?.cancel();

    await ref.read(cardListProvider.notifier).updateCard(card.copyWith(
          balance: result.balance!,
          status: result.status,
          expiryDate: result.expiryDate,
          clearExpiryDate: result.expiryDate == null,
          lastRefreshed: DateTime.now().millisecondsSinceEpoch,
        ));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).balanceSavedMsg(
        result.balance!.toStringAsFixed(2),
      )),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusText = _responseMessage != null
        ? l10n.manualCheckResponse(_responseMessage!)
        : (_ready ? l10n.manualCheckReady : l10n.manualCheckLoading);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manualCheckTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFE7EEFF), // chip blue from the theme
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(statusText,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(l10n.manualCheckHint,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(kPrimarySource.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  transparentBackground: false,
                  userAgent: kChromeMobileUserAgent,
                ),
              initialUserScripts: UnmodifiableListView<UserScript>([
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
              onWebViewCreated: (controller) => _controller = controller,
              onLoadStop: (_, _) {
                if (mounted) setState(() => _ready = true);
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _decodeString(Object? raw) {
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
}
