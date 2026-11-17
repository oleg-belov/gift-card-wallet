import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'l10n/generated/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The cryptography_flutter plugin (AES-GCM/PBKDF2 via platform APIs,
  // pure-Dart fallback elsewhere) registers itself automatically.
  // The database must exist before any provider reads it.
  final db = await openCardDatabase();
  // Decided before the first frame so the gate shows setup vs. unlock
  // without a visible flash.
  final cryptoConfigured = await readCryptoConfig(db) != null;
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        cryptoConfiguredProvider.overrideWithValue(cryptoConfigured),
      ],
      child: const LidlGiftCardApp(),
    ),
  );
}

class LidlGiftCardApp extends ConsumerWidget {
  const LidlGiftCardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeOverride = ref.watch(localeProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: localeOverride,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const AppGate(),
    );
  }
}

/// Root gate: shows the PIN screen (setup or unlock) until the app is
/// unlocked, and locks again whenever the app leaves the foreground.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // The app is no longer visible; forget the key so data at rest stays
      // encrypted. No-op when the gate is already closed.
      ref.read(lockStateProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(lockStateProvider);
    switch (lockState) {
      case AppLockState.unlocked:
        return const HomeScreen();
      case AppLockState.setup:
        return const LockScreen(mode: LockScreenMode.setup);
      case AppLockState.locked:
        return const LockScreen(mode: LockScreenMode.unlock);
    }
  }
}
