import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_text.dart';

/// Urgency banner shown when a card refresh stalls (e.g. a security check
/// is blocking the hidden WebView). Tapping opens the visible manual check.
class CaptchaBanner extends ConsumerWidget {
  const CaptchaBanner({super.key, required this.onOpenManual});

  final VoidCallback onOpenManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refresh = ref.watch(refreshProvider);
    if (refresh.phase != RefreshPhase.captchaStall) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Material(
      color: AppColors.red,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          leading: const Icon(Icons.shield_outlined, color: Colors.white),
          title: Text(
            refresh.errorKey == null
                ? l10n.captchaDefaultTitle
                : localizedRefreshError(
                    l10n, refresh.errorKey, refresh.errorDetail),
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          subtitle: Text(
            l10n.captchaBannerAction,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () =>
                ref.read(refreshProvider.notifier).dismissStatus(),
          ),
          onTap: onOpenManual,
        ),
      ),
    );
  }
}
