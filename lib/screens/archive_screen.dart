import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/gift_card.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'card_detail_screen.dart';

/// History view: stats, search, spent/expired filters and the archived
/// card list (swipe to delete permanently).
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

enum _ArchiveFilter { all, spent, expired }

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  String _query = '';
  _ArchiveFilter _filter = _ArchiveFilter.all;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(archivedCardsProvider);
    final stats = ref.watch(archivedStatsProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = DateTime.now();

    final filtered = cards.where((card) {
      final expired = card.isExpired(today);
      if (_filter == _ArchiveFilter.spent && expired) return false;
      if (_filter == _ArchiveFilter.expired && !expired) return false;
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      final last4 = card.cardNumber.length <= 4
          ? card.cardNumber
          : card.cardNumber.substring(card.cardNumber.length - 4);
      final year = card.expiryDate?.split('-').first ?? '';
      return (card.nickname ?? '').toLowerCase().contains(q) ||
          last4.contains(q) ||
          year.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.archiveTab)),
      body: cards.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.archiveEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.blue, size: 22),
                      hintText: l10n.archiveSearchHint,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: l10n.spentArchiveLabel,
                          value:
                              '${stats.totalRedeemed.toStringAsFixed(2)} CHF',
                          caption: l10n.totalRedeemed,
                          icon: Icons.savings_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: l10n.cardsCountLabel,
                          value: '${stats.count}',
                          caption: l10n.storedVouchers,
                          icon: Icons.inventory_2_outlined,
                          iconColor: AppColors.yellow,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.chipBlue,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Row(
                      children: [
                        _ArchiveSegment(
                          label: l10n.filterAllArchived,
                          count: stats.count,
                          selected: _filter == _ArchiveFilter.all,
                          onTap: () =>
                              setState(() => _filter = _ArchiveFilter.all),
                        ),
                        _ArchiveSegment(
                          label: l10n.filterFullySpent,
                          count: stats.spentCount,
                          selected: _filter == _ArchiveFilter.spent,
                          onTap: () =>
                              setState(() => _filter = _ArchiveFilter.spent),
                        ),
                        _ArchiveSegment(
                          label: l10n.filterExpired,
                          count: stats.expiredCount,
                          alertDot: stats.expiredCount > 0,
                          selected: _filter == _ArchiveFilter.expired,
                          onTap: () =>
                              setState(() => _filter = _ArchiveFilter.expired),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.archiveEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                else
                  ...filtered.map(
                    (card) => _ArchivedCardTile(
                      card: card,
                      today: today,
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CardDetailScreen(cardId: card.id!),
                        ),
                      ),
                      onRestore: () => _restore(card),
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: stats.spentCount == 0
                        ? null
                        : () => _clearSpentHistory(),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(l10n.clearSpentHistory),
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.clearSpentHistoryBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _restore(GiftCard card) async {
    final l10n = AppLocalizations.of(context);
    if (card.initialBalance == null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CardDetailScreen(cardId: card.id!),
        ),
      );
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
  }

  Future<void> _clearSpentHistory() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.confirmClearTitle),
        content: Text(l10n.clearSpentHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(cardListProvider.notifier)
        .deleteSpentHistory(DateTime.now());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.clearedHistoryMsg(removed))));
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    this.iconColor = AppColors.blue,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chipBlue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.slateMuted,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor == AppColors.yellow
                      ? AppColors.yellow
                      : iconColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 14, color: AppColors.slate),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.headlineMedium),
          Text(caption, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ArchiveSegment extends StatelessWidget {
  const _ArchiveSegment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.alertDot = false,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool alertDot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Material(
        color: selected ? AppColors.yellow : Colors.transparent,
        borderRadius: AppRadius.pill,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    '$label ($count)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? AppColors.slate : AppColors.slateMuted,
                    ),
                  ),
                ),
                if (alertDot && !selected) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Muted card row for the archive: spent cards get a muted pill, expired
/// ones the red treatment. Swipe left to delete permanently.
class _ArchivedCardTile extends ConsumerWidget {
  const _ArchivedCardTile({
    required this.card,
    required this.today,
    required this.onOpen,
    required this.onRestore,
  });

  final GiftCard card;
  final DateTime today;
  final VoidCallback onOpen;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final expired = card.isExpired(today);
    final last4 = card.cardNumber.length <= 4
        ? card.cardNumber
        : card.cardNumber.substring(card.cardNumber.length - 4);
    final dateText = expired
        ? (card.expiryDate == null
            ? l10n.expired
            : l10n.expiredOn(DateFormat('dd.MM.yyyy')
                .format(DateTime.parse(card.expiryDate!))))
        : card.lastRefreshed == null
            ? l10n.neverSynced
            : l10n.spentOn(DateFormat('dd.MM.yyyy').format(
                DateTime.fromMillisecondsSinceEpoch(card.lastRefreshed!)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Dismissible(
        key: ValueKey(card.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (_) async {
          final l10n = AppLocalizations.of(context);
          return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.deleteCardTitle),
                  content: Text(l10n.deleteCardBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(l10n.delete),
                    ),
                  ],
                ),
              ) ??
              false;
        },
        onDismissed: (_) =>
            ref.read(cardListProvider.notifier).deleteCard(card.id!),
        child: Material(
          color: expired ? AppColors.redContainer : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(
              color: expired ? AppColors.red : AppColors.outline,
              width: expired ? 1.4 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.nickname ?? '•••• $last4',
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: expired
                              ? Colors.white
                              : AppColors.chipBlue,
                          borderRadius: AppRadius.pill,
                        ),
                        child: Text(
                          '•••• $last4',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                expired ? AppColors.red : AppColors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(dateText, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: expired
                          ? Colors.white
                          : AppColors.chipBlue,
                      borderRadius: AppRadius.pill,
                      border: expired
                          ? Border.all(color: AppColors.red)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          expired
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          size: 15,
                          color:
                              expired ? AppColors.red : AppColors.blue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            expired
                                ? (card.balance > 0
                                    ? l10n.unspentAmount(
                                        '${card.balance.toStringAsFixed(2)} ${card.currency}')
                                    : l10n.expired)
                                : l10n.fullyRedeemed,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: expired ? AppColors.red : AppColors.blue,
                            ),
                          ),
                        ),
                        Text(
                          expired
                              ? ''
                              : '${card.balance.toStringAsFixed(2)} / ${card.initialBalance?.toStringAsFixed(2) ?? '—'} ${card.currency}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: expired ? AppColors.red : AppColors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!expired)
                        OutlinedButton.icon(
                          onPressed: onRestore,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                          icon: const Icon(Icons.unarchive_outlined, size: 18),
                          label: Text(l10n.restoreToWallet),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: onOpen,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l10n.viewDetails),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
