import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/gift_card.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/card_tile.dart';
import '../widgets/hero_balance_card.dart';
import 'archive_screen.dart';
import 'card_detail_screen.dart';
import 'scan_add_screen.dart';

enum _WalletFilter { all, expiring, favorites }

/// Wallet tab: blue hero, filter chips and the active card list.
class WalletTab extends ConsumerStatefulWidget {
  const WalletTab({super.key, required this.onScanRequested});

  /// Called when the hero's "Scan Card" CTA is pressed (the shell switches
  /// to the scan tab).
  final VoidCallback onScanRequested;

  @override
  ConsumerState<WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends ConsumerState<WalletTab> {
  _WalletFilter _filter = _WalletFilter.all;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(activeCardsProvider);
    final archivedCount = ref.watch(archivedCardsProvider).length;
    final today = DateTime.now();
    final l10n = AppLocalizations.of(context);

    final expiringCount =
        cards.where((c) => _isExpiringSoon(c, today)).length;
    final favoritesCount = cards.where((c) => c.isFavorite).length;
    final filtered = _filter == _WalletFilter.all
        ? cards
        : cards
            .where(
              (c) => _filter == _WalletFilter.expiring
                  ? _isExpiringSoon(c, today)
                  : c.isFavorite,
            )
            .toList();

    if (ref.watch(cardListProvider).isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: () => ref.read(refreshProvider.notifier).refreshAll(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          HeroBalanceCard(
            onScan: widget.onScanRequested,
            onEnterCode: () => showManualEntrySheet(context, ref),
          ),
          const SizedBox(height: 8),
          if (cards.isEmpty)
            _EmptyWallet()
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterChip(
                    label: l10n.filterAllActive,
                    count: cards.length,
                    selected: _filter == _WalletFilter.all,
                    onTap: () => setState(() => _filter = _WalletFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: l10n.filterExpiringSoon,
                    count: expiringCount,
                    selected: _filter == _WalletFilter.expiring,
                    alertDot: expiringCount > 0,
                    onTap: () =>
                        setState(() => _filter = _WalletFilter.expiring),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: l10n.filterFavorites,
                    count: favoritesCount,
                    selected: _filter == _WalletFilter.favorites,
                    icon: Icons.star_rounded,
                    onTap: () =>
                        setState(() => _filter = _WalletFilter.favorites),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.emptyWalletBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ...filtered.map(
                (card) => CardTile(
                  card: card,
                  today: today,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CardDetailScreen(cardId: card.id!),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (archivedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ArchivedLinkRow(
                count: archivedCount,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _isExpiringSoon(GiftCard card, DateTime today) {
    final days = card.daysUntilExpiry(today);
    return days != null && days >= 0 && days <= 14;
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
    this.alertDot = false,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool alertDot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Material(
        color: selected ? AppColors.yellow : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.yellowDark : AppColors.outline,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? AppColors.slate : AppColors.slateMuted,
                  ),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      color: selected ? AppColors.slate : AppColors.slateMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                if (alertDot && !selected)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? AppColors.slate : AppColors.slateMuted,
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

/// "Looking for old cards?" row linking to the archive screen.
class _ArchivedLinkRow extends StatelessWidget {
  const _ArchivedLinkRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.chipBlue,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: AppColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.viewArchivedRow(count),
                  style:
                      theme.textTheme.labelLarge?.copyWith(color: AppColors.blue),
                ),
              ),
              const Icon(Icons.arrow_forward, size: 18, color: AppColors.blue),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWallet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.yellow,
            ),
            child: const Icon(
              Icons.card_giftcard,
              size: 44,
              color: AppColors.slate,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.emptyWalletBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
