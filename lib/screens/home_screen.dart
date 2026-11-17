import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/providers.dart';
import '../utils/app_text.dart';
import '../widgets/captcha_banner.dart';
import 'balance_check_tab.dart';
import 'lock_screen.dart';
import 'manual_check_screen.dart';
import 'profile_tab.dart';
import 'scan_add_screen.dart';
import 'wallet_tab.dart';

/// Main tabs for the wallet, scanning, balance checks and profile.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  Future<void> _openManualCheck([int? cardIdOverride]) async {
    final l10n = AppLocalizations.of(context);
    final cardId = cardIdOverride ?? ref.read(refreshProvider).currentCardId;
    if (cardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.noCardInEdit),
      ));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualCheckScreen(cardId: cardId),
      ),
    );
    // Resume the paused refresh queue when the manual check is done.
    if (mounted) {
      await ref.read(refreshProvider.notifier).resumeAfterManual();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final refresh = ref.watch(refreshProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Text(l10n.appTitle, overflow: TextOverflow.ellipsis),
        actions: [
          // In-app language toggle: EN <-> DE, persisted across restarts.
          IconButton(
            icon: Text(
              Localizations.localeOf(context).languageCode.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            tooltip: l10n.languageTooltip,
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'changePin',
                child: ListTile(
                  leading: const Icon(Icons.password),
                  title: Text(l10n.changePinMenu),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'changePin') showChangePinSheet(context);
            },
          ),
          if (refresh.phase == RefreshPhase.done &&
              refresh.errorKey != null)
            IconButton(
              icon: const Icon(Icons.error_outline),
              tooltip: localizedRefreshError(
                  l10n, refresh.errorKey, refresh.errorDetail),
              onPressed: () =>
                  ref.read(refreshProvider.notifier).dismissStatus(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.unofficialLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
          CaptchaBanner(onOpenManual: _openManualCheck),
          if (refresh.phase == RefreshPhase.running)
            LinearProgressIndicator(
              value: refresh.total == 0
                  ? null
                  : refresh.completed / refresh.total,
              minHeight: 3,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                WalletTab(
                  onScanRequested: () => setState(() => _tab = 1),
                ),
                ScanTab(
                  active: _tab == 1,
                  onCardSaved: (_) => setState(() => _tab = 0),
                ),
                BalanceCheckTab(
                  onOpenManualCheck: _openManualCheck,
                ),
                const ProfileTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.credit_card_outlined),
            selectedIcon: const Icon(Icons.credit_card),
            label: l10n.cardsTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: const Icon(Icons.qr_code_scanner),
            label: l10n.scanTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_offer_outlined),
            selectedIcon: const Icon(Icons.local_offer),
            label: l10n.balanceCheckTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.profileTab,
          ),
        ],
      ),
    );
  }
}
