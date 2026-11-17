import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/gift_card.dart';
import '../theme/app_theme.dart';
import '../utils/app_text.dart';

/// A single card row in the wallet: white pebble card with an icon avatar,
/// right-aligned balance, validity chips — and a red urgency strip plus
/// border when the card expires within 14 days.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.today,
    required this.onOpen,
  });

  final GiftCard card;
  final DateTime today;
  final VoidCallback onOpen;

  bool get _isUrgent {
    final days = card.daysUntilExpiry(today);
    return days != null && days >= 0 && days <= 14;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final urgent = _isUrgent;
    final title = (card.nickname != null && card.nickname!.isNotEmpty)
        ? card.nickname!
        : _maskedNumber();
    final balanceColor = card.balance > 0 ? AppColors.slate : AppColors.slateMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: urgent ? AppColors.red : AppColors.outline,
            width: urgent ? 1.8 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (urgent) _UrgencyStrip(card: card, today: today),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconAvatar(urgent: urgent, favorite: card.isFavorite),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.cardEndingIn(_last4()),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              l10n.balanceLabel,
                              style: theme.textTheme.bodySmall,
                            ),
                            Text(
                              '${card.balance.toStringAsFixed(2)} ${card.currency}',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: balanceColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CountdownBadge(card: card, today: today),
                        _StatusBadge(card: card),
                        if (card.expiryDate != null)
                          _Pill(
                            icon: Icons.event_outlined,
                            label: l10n.validUntil(DateFormat('dd.MM.yyyy')
                                .format(DateTime.parse(card.expiryDate!))),
                          ),
                        if (card.isManuallyEdited)
                          _Pill(
                            icon: Icons.edit_outlined,
                            label: l10n.manuallyEdited,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.chipBlue,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(
                              Icons.qr_code_2,
                              size: 20,
                              color: AppColors.blue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l10n.showBarcode,
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(color: AppColors.blue),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: AppColors.blue,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _maskedNumber() {
    final n = card.cardNumber;
    if (n.length <= 4) return n;
    return '•••• ${n.substring(n.length - 4)}';
  }

  String _last4() {
    final n = card.cardNumber;
    return n.length <= 4 ? n : n.substring(n.length - 4);
  }
}

/// Red banner across the top of a card that expires within 14 days.
class _UrgencyStrip extends StatelessWidget {
  const _UrgencyStrip({required this.card, required this.today});

  final GiftCard card;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = card.daysUntilExpiry(today)!;
    final date = DateFormat('dd.MM.yyyy').format(DateTime.parse(card.expiryDate!));

    return Container(
      color: AppColors.red,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.urgentStripLine(l10n.expiresInDays(days), date),
              style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: AppRadius.pill,
            ),
            child: Text(
              l10n.urgentBadge,
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAvatar extends StatelessWidget {
  const _IconAvatar({required this.urgent, required this.favorite});

  final bool urgent;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: urgent ? AppColors.blue : AppColors.yellow,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.card_giftcard,
              color: urgent ? Colors.white : AppColors.slate,
              size: 24,
            ),
          ),
          if (favorite)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Icon(Icons.star, size: 13, color: AppColors.blue),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.card, required this.today});

  final GiftCard card;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = card.daysUntilExpiry(today);

    final (Color bg, Color fg, IconData? icon) = card.isExpired(today)
        ? (AppColors.redContainer, Color(0xFFB0000C), null)
        : days == null
            ? (AppColors.outline, AppColors.slateMuted, null)
            : days <= 14
                ? (AppColors.redContainer, Color(0xFFB0000C), null)
                : days <= 45
                    ? (AppColors.yellow, AppColors.slate, null)
                    : (AppColors.chipBlue, AppColors.blue, Icons.event_available);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            days == null
                ? l10n.expiryUnknown
                : card.isExpired(today)
                    ? l10n.expired
                    : l10n.expiresInDays(days),
            style: theme.textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.card});

  final GiftCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.chipBlue,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.chipBlueDeep),
      ),
      child: Text(
        localizedStatusLabel(l10n, card.status),
        style: theme.textTheme.labelSmall?.copyWith(color: AppColors.blue),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.chipBlue,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.blue),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.blue),
          ),
        ],
      ),
    );
  }
}
