import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

/// The blue wallet hero: total balance, active-card chip, remaining-value
/// progress and the two primary actions (scan / enter code).
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({
    super.key,
    required this.onScan,
    required this.onEnterCode,
  });

  final VoidCallback onScan;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cards = ref.watch(activeCardsProvider);
    final total = ref.watch(totalActiveBalanceProvider);
    final theme = Theme.of(context);

    final initialSum = cards.fold<double>(
      0,
      (sum, c) => sum + (c.initialBalance ?? 0),
    );
    // Only meaningful when every card has a known initial amount.
    final bool progressKnown = cards.isNotEmpty && initialSum > 0;
    final ratio = progressKnown ? (total / initialSum).clamp(0.0, 1.0) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        boxShadow: AppColors.cardGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.heroTotalLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.yellow,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.activeCardsChip(cards.length),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${total.toStringAsFixed(2)} ${cards.isEmpty ? 'CHF' : cards.first.currency}',
            style: theme.textTheme.displayLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          if (ratio != null) ...[
            ClipRRect(
              borderRadius: AppRadius.pill,
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(AppColors.yellow),
              ),
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  label: Text(l10n.scanCardCta, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEnterCode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54, width: 1.4),
                  ),
                  icon: const Icon(Icons.keyboard_outlined, size: 20),
                  label:
                      Text(l10n.enterCodeCta, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
