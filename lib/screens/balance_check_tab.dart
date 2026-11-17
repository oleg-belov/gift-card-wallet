import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/gift_card.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'card_detail_screen.dart';
import 'manual_check_screen.dart';

/// Lists cards that can be checked on Lidl's balance page.
class BalanceCheckTab extends ConsumerWidget {
  const BalanceCheckTab({super.key, required this.onOpenManualCheck});

  /// Shell callback that opens [ManualCheckScreen] for the card currently
  /// held by the refresh queue (used when a refresh stalled on a captcha).
  final void Function(int cardId) onOpenManualCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(activeCardsProvider);
    final refresh = ref.watch(refreshProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = DateTime.now();
    final refreshable = cards.where((c) => c.isRefreshable(today)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(32),
            boxShadow: AppColors.cardGlow,
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 40, color: AppColors.yellow),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.balanceCheckTitle,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.balanceCheckIntro,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (refresh.phase == RefreshPhase.captchaStall ||
            refresh.phase == RefreshPhase.done && refresh.errorKey != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _QueueNotice(
              cardId: refresh.currentCardId ?? cards.firstOrNull?.id,
              onOpenManualCheck: onOpenManualCheck,
            ),
          ),
        if (refresh.phase == RefreshPhase.running)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.chipBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.refreshQueueStatus(
                          refresh.completed, refresh.total),
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.pickCardToCheck,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: theme.textTheme.labelMedium,
                ),
                onPressed: ref.read(refreshProvider.notifier).isRunning
                    ? null
                    : () => ref.read(refreshProvider.notifier).refreshAll(),
                icon: const Icon(Icons.sync, size: 18),
                label: Text(l10n.refreshAll),
              ),
            ],
          ),
        ),
        if (refreshable.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              l10n.nothingToCheck,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          ...refreshable.map((card) => _CheckableCardTile(
                card: card,
                onOpenDetails: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CardDetailScreen(cardId: card.id!),
                  ),
                ),
              )),
      ],
    );
  }
}

/// Shown when the refresh queue paused or errored: jump straight into the
/// visible manual check for the stalled card.
class _QueueNotice extends ConsumerWidget {
  const _QueueNotice({
    required this.cardId,
    required this.onOpenManualCheck,
  });

  final int? cardId;
  final void Function(int cardId) onOpenManualCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final refresh = ref.watch(refreshProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              refresh.phase == RefreshPhase.captchaStall
                  ? l10n.captchaBannerAction
                  : l10n.queryFailed,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Color(0xFFB0000C)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
            ),
            onPressed: cardId == null
                ? null
                : () => onOpenManualCheck(cardId!),
            child: Text(l10n.openBalancePage),
          ),
        ],
      ),
    );
  }
}

class _CheckableCardTile extends ConsumerWidget {
  const _CheckableCardTile({required this.card, required this.onOpenDetails});

  final GiftCard card;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final refresh = ref.watch(refreshProvider);
    final isCurrent = refresh.currentCardId == card.id &&
        (refresh.phase == RefreshPhase.running ||
            refresh.phase == RefreshPhase.captchaStall);
    final last4 = card.cardNumber.length <= 4
        ? card.cardNumber
        : card.cardNumber.substring(card.cardNumber.length - 4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: isCurrent
              ? const BorderSide(color: AppColors.yellowDark, width: 1.6)
              : const BorderSide(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onOpenDetails,
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.chipBlue,
                ),
                child: const Icon(Icons.credit_card, color: AppColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.nickname ?? '•••• $last4',
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${card.balance.toStringAsFixed(2)} ${card.currency}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrent) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l10n.currentlyChecking,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.yellowDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${refresh.completed < refresh.total ? refresh.completed + 1 : refresh.completed}/${refresh.total}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.slateMuted),
                    ),
                  ],
                ),
              ] else
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  onPressed: () async {
                    final id = card.id!;
                    // Point the queue at this card so the manual screen and
                    // the captcha banner resume in the right context. The
                    // row rebuilds once the refresh state changes (the
                    // button swaps for a progress label), so capture the
                    // navigator before awaiting — the widget that spawned
                    // the press may be gone afterwards.
                    final navigator = Navigator.of(context);
                    await ref
                        .read(refreshProvider.notifier)
                        .refreshSingle(card);
                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => ManualCheckScreen(cardId: id),
                      ),
                    );
                  },
                  child: Text(
                    l10n.openBalancePage,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
