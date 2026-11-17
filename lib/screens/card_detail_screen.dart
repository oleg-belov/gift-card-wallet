import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/card_transaction.dart';
import '../models/gift_card.dart';
import '../services/parser.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_text.dart';
import '../widgets/barcode_view.dart';
import '../widgets/lidl_badge.dart';
import 'manual_check_screen.dart';

/// Checkout view: blue hero with balance and refresh, expiry warning,
/// full-brightness scannable barcode (barcode/QR toggle, fullscreen for the
/// cashier), recent activity and the archive/restore actions.
class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  double? _brightnessBefore;
  bool _pinVisible = false;
  bool _useQr = false;
  bool _refreshFailed = false;

  GiftCard? _currentCard() {
    final cards = ref.watch(cardListProvider).value ?? const <GiftCard>[];
    for (final c in cards) {
      if (c.id == widget.cardId) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _raiseBrightness();
  }

  Future<void> _raiseBrightness() async {
    try {
      _brightnessBefore = await ScreenBrightness.instance.application;
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
    } catch (_) {
      // Brightness control unavailable; barcode contrast still helps.
    }
  }

  @override
  void dispose() {
    _restoreBrightness();
    super.dispose();
  }

  Future<void> _restoreBrightness() async {
    try {
      if (_brightnessBefore != null) {
        await ScreenBrightness.instance
            .setApplicationScreenBrightness(_brightnessBefore!);
      } else {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      }
    } catch (_) {}
  }

  Future<void> _refresh(GiftCard card) async {
    final l10n = AppLocalizations.of(context);
    final outcome =
        await ref.read(refreshProvider.notifier).refreshSingle(card);
    if (!mounted) return;
    // A cancelled query (app locked or superseded mid-run) is not an error —
    // surfacing it would leave a "Cancelled" snackbar hanging over the
    // wallet, since the dismiss timer only runs after the next unlock.
    if (outcome.errorKey == RefreshErrors.cancelled) return;
    final messenger = ScaffoldMessenger.of(context);
    if (outcome.result.isSuccess) {
      if (mounted) setState(() => _refreshFailed = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.balanceUpdated)));
    } else {
      // Keep the failure visible on the page (the 8-second snackbar is easy
      // to miss on a long ladder) with the manual captcha escape hatch.
      if (mounted) setState(() => _refreshFailed = true);
      messenger.showSnackBar(SnackBar(
        content: Text(
          '${l10n.queryFailed}: ${localizedRefreshError(l10n, outcome.errorKey, outcome.errorDetail)}',
        ),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  void _openManualCheck(GiftCard card) {
    setState(() => _refreshFailed = false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualCheckScreen(cardId: card.id!),
      ),
    );
  }

  Future<void> _archiveCard(GiftCard card) async {
    await ref.read(cardListProvider.notifier).updateCard(
          card.copyWith(
            balance: 0,
            isManuallyEdited: true,
            lastRefreshed: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).cardArchivedMsg)));
    Navigator.of(context).pop();
  }

  Future<void> _restoreCard(GiftCard card) async {
    final l10n = AppLocalizations.of(context);
    // Without a usable initial amount (unknown, or 0.00 from a save-anyway
    // card — restoring with balance 0 would re-archive it instantly) the
    // user picks the restored balance in the edit sheet.
    if (card.initialBalance == null || card.initialBalance! <= 0) {
      _showEditSheet(card);
      return;
    }
    await ref.read(cardListProvider.notifier).updateCard(
          card.copyWith(
            balance: card.initialBalance,
            isManuallyEdited: true,
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.cardRestoredMsg)));
    Navigator.of(context).pop();
  }

  void _showAllActivity(List<CardTransaction> transactions) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) => _ActivityRow(
            transaction: transactions[index],
            currency: _currentCard()?.currency ?? 'CHF',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _currentCard();
    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).cardTitle)),
        body: Center(
          child: Text(AppLocalizations.of(context).cardDeleted),
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = DateTime.now();
    final archived = card.isArchived(today);
    final expired = card.isExpired(today);
    final lastUpdated = card.lastRefreshed == null
        ? null
        : DateFormat('dd.MM.yyyy HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(card.lastRefreshed!),
          );
    final expiryText = card.expiryDate == null
        ? l10n.expiryUnknown
        : DateFormat('dd.MM.yyyy').format(DateTime.parse(card.expiryDate!));

    return Scaffold(
      appBar: AppBar(
        title: Text(card.nickname ?? l10n.cardTitle),
        actions: [
          IconButton(
            icon: Icon(
              card.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: card.isFavorite ? AppColors.yellowDark : null,
            ),
            tooltip: card.isFavorite ? l10n.favoriteRemove : l10n.favoriteAdd,
            onPressed: () => ref
                .read(cardListProvider.notifier)
                .setFavorite(card, !card.isFavorite),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshOnlineTooltip,
            onPressed: () => _refresh(card),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.editTooltip,
            onPressed: () => _showEditSheet(card),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroCardFace(
              card: card,
              onRefresh: () => _refresh(card),
            ),
            if (_refreshFailed) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.redContainer,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.red),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 22, color: AppColors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.verificationFailedTitle,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _openManualCheck(card),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: Text(l10n.openManualCheck,
                            overflow: TextOverflow.ellipsis, maxLines: 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Card number + security PIN.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.cardNumberField, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '••••  ••••  ••••  ',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  letterSpacing: 2,
                                  color: AppColors.slateMuted,
                                ),
                              ),
                              Text(
                                _last4(card.cardNumber),
                                style: theme.textTheme.headlineSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(l10n.securityPin, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _pinVisible ? card.pin : '••••',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(letterSpacing: 3),
                            ),
                            IconButton(
                              icon: Icon(
                                _pinVisible
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              tooltip:
                                  _pinVisible ? l10n.hidePin : l10n.revealPin,
                              onPressed: () =>
                                  setState(() => _pinVisible = !_pinVisible),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Expiry banner.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ExpiryBanner(card: card, expired: expired, expiryText: expiryText),
            ),
            const SizedBox(height: 12),

            // Barcode island.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.chipBlue,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.brightness_high,
                              size: 15, color: AppColors.blue),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              l10n.maxBrightnessNote,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.blue),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.chipBlue,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SegmentToggle(
                            label: l10n.barcodeModeLabel,
                            selected: !_useQr,
                            onTap: () => setState(() => _useQr = false),
                          ),
                          _SegmentToggle(
                            label: l10n.qrModeLabel,
                            selected: _useQr,
                            onTap: () => setState(() => _useQr = true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _showFullScreenBarcode,
                      child: Container(
                        color: Colors.transparent,
                        child: BarcodeView(
                          data: card.checkoutBarcode,
                          barcodeFormat: _useQr ? 'qr' : card.barcodeFormat,
                          showText: false,
                          width: 300,
                          height: _useQr ? 180 : 110,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      // Show what the barcode encodes (the GS1 payload when
                      // the voucher carried one) so the caption always
                      // matches the bars above it.
                      _groupDigits(card.checkoutBarcode),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(letterSpacing: 2),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showFullScreenBarcode,
                        icon: const Icon(Icons.fullscreen, size: 20),
                        label: Text(l10n.tapToExpand,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Details rows (status, expiry, last sync).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: l10n.statusLabel,
                      value: localizedStatusLabel(l10n, card.status),
                    ),
                    const Divider(height: 1),
                    _DetailRow(label: l10n.expiryLabel, value: expiryText),
                    const Divider(height: 1),
                    _DetailRow(
                      label: l10n.lastUpdatedLabel,
                      value: lastUpdated ?? l10n.neverSynced,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Recent activity.
            _ActivitySection(
              cardId: widget.cardId,
              currency: card.currency,
              onViewAll: _showAllActivity,
            ),
            const SizedBox(height: 12),

            // Primary actions.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: archived && !expired
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.unarchive_outlined),
                      label: Text(l10n.restoreToWallet),
                      onPressed: () => _restoreCard(card),
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(l10n.archiveThisCard),
                      onPressed: () => _archiveCard(card),
                    ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  l10n.archivedFootnote,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenBarcode() {
    final card = _currentCard();
    if (card == null) return;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.fullScreenBarcode,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.all(16),
                child: BarcodeView(
                  data: card.checkoutBarcode,
                  barcodeFormat: _useQr ? 'qr' : card.barcodeFormat,
                  showText: false,
                  width: 360,
                  height: _useQr ? 300 : 160,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _groupDigits(card.checkoutBarcode),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 48),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
                label: Text(MaterialLocalizations.of(context)
                    .closeButtonTooltip),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditSheet(GiftCard card) {
    final l10n = AppLocalizations.of(context);
    final balanceCtrl =
        TextEditingController(text: card.balance.toStringAsFixed(2));
    final expiryCtrl = TextEditingController(text: card.expiryDate ?? '');
    final nicknameCtrl = TextEditingController(text: card.nickname ?? '');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.editTitle, style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextFormField(
                  controller: balanceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: l10n.balanceField),
                  validator: (v) {
                    final parsed =
                        double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (parsed == null || parsed < 0) {
                      return l10n.invalidAmount;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: expiryCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.expiryField,
                    hintText: '2031-10-31',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return null;
                    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
                      return l10n.invalidExpiryFormat;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: nicknameCtrl,
                  decoration:
                      InputDecoration(labelText: l10n.nicknameField),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.save),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final newBalance =
                        double.parse(balanceCtrl.text.replaceAll(',', '.'));
                    final newExpiry = expiryCtrl.text.trim();
                    await ref
                        .read(cardListProvider.notifier)
                        .updateCard(card.copyWith(
                          balance: newBalance,
                          // First manual entry also fixes the initial amount.
                          initialBalance: card.initialBalance ?? newBalance,
                          expiryDate: newExpiry.isEmpty ? null : newExpiry,
                          clearExpiryDate: newExpiry.isEmpty,
                          nickname: nicknameCtrl.text.trim().isEmpty
                              ? null
                              : nicknameCtrl.text.trim(),
                          isManuallyEdited: true,
                        ));
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _last4(String number) =>
      number.length <= 4 ? number : number.substring(number.length - 4);

  static String _groupDigits(String number) {
    final buffer = StringBuffer();
    for (var i = 0; i < number.length; i++) {
      buffer.write(number[i]);
      if ((i + 1) % 4 == 0 && i + 1 != number.length) buffer.write(' ');
    }
    return buffer.toString();
  }
}

/// Blue gradient card face with the balance panel and refresh pill.
class _HeroCardFace extends ConsumerWidget {
  const _HeroCardFace({required this.card, required this.onRefresh});

  final GiftCard card;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final ratio = card.usageRatio;
    // While ANY online check is running (shared hidden WebView), the button
    // shows a spinner and is disabled — prevents concurrent double queries.
    final refresh = ref.watch(refreshProvider);
    final busy = refresh.phase == RefreshPhase.running;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppColors.cardGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LidlBadge(size: 30),
              const SizedBox(width: 10),
              Text(
                l10n.giftCardLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (card.nickname != null && card.nickname!.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      card.nickname!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.currentBalance,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              style: theme.textTheme.displayMedium
                                  ?.copyWith(color: AppColors.yellow),
                              children: [
                                TextSpan(
                                    text:
                                        '${card.balance.toStringAsFixed(2)} '),
                                TextSpan(
                                  text: card.currency,
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          if (card.initialBalance != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              l10n.ofInitialAmount(
                                '${card.initialBalance!.toStringAsFixed(2)} ${card.currency}',
                              ),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: busy ? null : onRefresh,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.blue,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.blue,
                              ),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(l10n.refreshOnlineTooltip,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (ratio != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.25),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.yellow),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yellow (or red for urgent) expiry warning banner.
class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({
    required this.card,
    required this.expired,
    required this.expiryText,
  });

  final GiftCard card;
  final bool expired;
  final String expiryText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = card.daysUntilExpiry(DateTime.now());
    final urgent = expired || (days != null && days <= 14);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: urgent
            ? AppColors.redContainer
            : card.expiryDate == null
                ? AppColors.chipBlue
                : AppColors.yellow.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: urgent ? AppColors.red : AppColors.yellowDark,
          width: urgent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            expired
                ? Icons.event_busy
                : Icons.warning_amber_rounded,
            size: 26,
            color: urgent ? AppColors.red : AppColors.yellowDark,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expired
                      ? l10n.expiredOn(expiryText)
                      // No "Expiry date: unknown" duplication.
                      : card.expiryDate == null
                          ? l10n.expiryUnknown
                          : l10n.expiryBannerLine(expiryText),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (expired)
                      _RedPill(label: l10n.expired)
                    else if (days != null && days <= 45)
                      _RedPill(label: l10n.daysRemaining(days))
                    else
                      Text(
                        l10n.useInStore,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RedPill extends StatelessWidget {
  const _RedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
            ),
      ),
    );
  }
}

class _SegmentToggle extends StatelessWidget {
  const _SegmentToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.yellow : Colors.transparent,
      borderRadius: AppRadius.pill,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? AppColors.slate : AppColors.slateMuted,
                ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

/// Recent activity: last 3 rows from the transaction log plus View-all.
class _ActivitySection extends ConsumerWidget {
  const _ActivitySection({
    required this.cardId,
    required this.currency,
    required this.onViewAll,
  });

  final int cardId;
  final String currency;
  final void Function(List<CardTransaction>) onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final transactionsAsync = ref.watch(cardTransactionsProvider(cardId));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, size: 18, color: AppColors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.recentActivity,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                TextButton(
                  onPressed: transactionsAsync.maybeWhen(
                    data: (list) => list.isEmpty ? null : () => onViewAll(list),
                    orElse: () => null,
                  ),
                  child: Text(l10n.viewAll),
                ),
              ],
            ),
            transactionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.errNoResult, style: theme.textTheme.bodySmall),
              ),
              data: (transactions) {
                if (transactions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l10n.neverSynced,
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final tx in transactions.take(3))
                      _ActivityRow(transaction: tx, currency: currency),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.transaction, required this.currency});

  final CardTransaction transaction;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final date = DateFormat('dd.MM.yyyy • HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(transaction.createdAt),
    );

    final (IconData icon, Color color, String title) = switch (transaction.type) {
      CardTransactionType.activation => (
          Icons.add_card,
          AppColors.blue,
          l10n.activityActivation
        ),
      CardTransactionType.spend => (
          Icons.shopping_cart_outlined,
          AppColors.red,
          l10n.activitySpend
        ),
      CardTransactionType.reload => (
          Icons.savings_outlined,
          AppColors.blue,
          l10n.activityReload
        ),
      CardTransactionType.edit => (
          Icons.edit_outlined,
          AppColors.slateMuted,
          l10n.activityEdit
        ),
    };

    final amount = transaction.amount;
    final String amountText;
    if (amount == null) {
      amountText = '';
    } else if (amount > 0) {
      amountText = '+${amount.toStringAsFixed(2)}';
    } else {
      amountText = amount.toStringAsFixed(2);
    }
    final amountColor = amount == null
        ? AppColors.slateMuted
        : amount > 0
            ? AppColors.blue
            : AppColors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(date, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (amountText.isNotEmpty)
            Text(
              '$amountText $currency',
              style: theme.textTheme.labelLarge?.copyWith(color: amountColor),
            ),
        ],
      ),
    );
  }
}
