import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'lock_screen.dart';

/// Profile tab: language, wallet stats, security (PIN / lock) and data
/// housekeeping.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cards = ref.watch(cardListProvider).value ?? const [];
    final active = ref.watch(activeCardsProvider);
    final archived = ref.watch(archivedCardsProvider);
    final total = ref.watch(totalActiveBalanceProvider);
    final currentLanguage = Localizations.localeOf(context).languageCode;
    final currency = active.isEmpty ? 'CHF' : active.first.currency;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionHeader(title: l10n.statsSection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: l10n.statTotalCards,
                  value: '${cards.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: l10n.statActiveCards,
                  value: '${active.length}',
                  highlight: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: l10n.statArchivedCards,
                  value: '${archived.length}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppColors.cardGlow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.statTotalBalance.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${total.toStringAsFixed(2)} $currency',
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.savings_outlined,
                    color: AppColors.yellow, size: 34),
              ],
            ),
          ),
        ),
        _SectionHeader(title: l10n.languageSection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                _LanguageOption(
                  label: l10n.languageEnglish,
                  code: 'en',
                  selected: currentLanguage == 'en',
                ),
                _LanguageOption(
                  label: l10n.languageGerman,
                  code: 'de',
                  selected: currentLanguage == 'de',
                ),
              ],
            ),
          ),
        ),
        _SectionHeader(title: l10n.securitySection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password, color: AppColors.blue),
                  title: Text(l10n.changePinMenu,
                      style: theme.textTheme.titleMedium),
                  trailing:
                      const Icon(Icons.chevron_right, color: AppColors.slateMuted),
                  onTap: () => showChangePinSheet(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.lock_outline, color: AppColors.blue),
                  title:
                      Text(l10n.lockNow, style: theme.textTheme.titleMedium),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.slateMuted),
                  onTap: () => ref.read(lockStateProvider.notifier).lock(),
                ),
              ],
            ),
          ),
        ),
        _SectionHeader(title: l10n.aboutSection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chipBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.appTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.blue),
                ),
                const SizedBox(height: 6),
                Text(l10n.personalUseNotice, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(l10n.aboutBody, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.yellow : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? AppColors.yellowDark : AppColors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineMedium),
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends ConsumerWidget {
  const _LanguageOption({
    required this.label,
    required this.code,
    required this.selected,
  });

  final String label;
  final String code;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Expanded(
      child: Material(
        color: selected ? AppColors.chipBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final notifier = ref.read(localeProvider.notifier);
            final current = Localizations.localeOf(context).languageCode;
            // Only write when the choice actually changes.
            if (current != code) await notifier.toggle();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? AppColors.blue : AppColors.slate,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  code.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? AppColors.blue : AppColors.slateMuted,
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
