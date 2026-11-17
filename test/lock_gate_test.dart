import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidl_gift_card/db/database.dart';
import 'package:lidl_gift_card/l10n/generated/app_localizations.dart';
import 'package:lidl_gift_card/main.dart';
import 'package:lidl_gift_card/models/gift_card.dart';
import 'package:lidl_gift_card/screens/lock_screen.dart';
import 'package:lidl_gift_card/services/crypto_service.dart';
import 'package:lidl_gift_card/state/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmpDir;
  late Database db;
  late CardCrypto crypto;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lidl_gc_gate_test');
    db = await openCardDatabase(path: '${tmpDir.path}/databases');
    crypto = CardCrypto(defaultIterations: 1000);
  });

  tearDown(() async {
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  /// Real-async DB/crypto work must run via [tester.runAsync]: testWidgets
  /// bodies execute in a FakeAsync zone where isolate round-trips (sqflite
  /// ffi, PBKDF2 futures) would otherwise never complete.
  Future<void> seedEncryptedWallet(WidgetTester tester) async {
    await tester.runAsync(() async {
      await enableEncryption(db, crypto, '1357');
      await CardDao(db, crypto: crypto).insert(
        GiftCard.draft(cardNumber: '24001234567890123456', pin: '4321'),
      );
    });
  }

  Future<void> pumpGate(WidgetTester tester, {required bool configured}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          cryptoConfiguredProvider.overrideWithValue(configured),
          cryptoProvider.overrideWithValue(crypto),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppGate(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(AppGate)));

  testWidgets('fresh install shows the setup screen', (tester) async {
    await pumpGate(tester, configured: false);
    expect(find.text('Protect your wallet'), findsOneWidget);
  });

  testWidgets('existing config shows the unlock screen, not setup',
      (tester) async {
    await seedEncryptedWallet(tester);

    await pumpGate(tester, configured: true);
    expect(find.text('Enter app PIN'), findsOneWidget);
    expect(find.text('Protect your wallet'), findsNothing);
    // The card list must not have been loaded while locked.
    expect(find.textContaining('5694'), findsNothing);
  });

  testWidgets('unlock with a wrong PIN is rejected and keeps the gate '
      'closed', (tester) async {
    await seedEncryptedWallet(tester);

    await pumpGate(tester, configured: true);
    final container = containerOf(tester);

    await tester.runAsync(() async {
      await expectLater(
        container.read(lockStateProvider.notifier).unlock('9999'),
        throwsA(isA<WrongPinException>()),
      );
    });
    await tester.pumpAndSettle();

    expect(find.text('Enter app PIN'), findsOneWidget);
    expect(find.textContaining('5694'), findsNothing);
    // The crypto session is still locked after the failed attempt.
    expect(container.read(cryptoProvider).isUnlocked, isFalse);
  });

  testWidgets('after first-run setup, backgrounding locks into unlock mode '
      '— never back into setup', (tester) async {
    // Regression: cryptoConfiguredProvider is a startup snapshot (false
    // during first-run). lock() must not consult it — after completing
    // setup, a background round-trip (e.g. the file picker) used to land on
    // the setup screen instead of the PIN gate.
    await pumpGate(tester, configured: false);
    expect(find.text('Protect your wallet'), findsOneWidget);

    final container = containerOf(tester);
    await tester.runAsync(() {
      return container.read(lockStateProvider.notifier).setup('1357');
    });
    // Construct the card list (and finish its DB round-trip) in the real
    // async zone, like unlock() does — HomeScreen would otherwise start the
    // load inside pumpAndSettle's fake-async zone, where sqflite_ffi never
    // completes and the loading spinner never settles.
    await tester.runAsync(() {
      return container.read(cardListProvider.notifier).reload();
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp('total balance', caseSensitive: false)),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(container.read(lockStateProvider), AppLockState.locked);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Enter app PIN'), findsOneWidget);
    expect(find.text('Protect your wallet'), findsNothing);
  });

  testWidgets('a pending file import replays into the entry sheet after '
      'the next unlock', (tester) async {
    // The system file picker pauses the app → wallet locks → the scan tab
    // unmounts. The picked voucher is stashed and must reopen prefilled.
    await seedEncryptedWallet(tester);
    await pumpGate(tester, configured: true);
    final container = containerOf(tester);

    container.read(pendingCardImportProvider.notifier).state =
        const PendingCardImport(
      cardNumber: '211224627680296028',
      pin: '7195',
      detectedValue: 100.0,
      barcodeFormat: 'code128',
    );

    await tester.runAsync(() {
      return container.read(lockStateProvider.notifier).unlock('1357');
    });
    await tester.pumpAndSettle();

    // The sheet opened, prefilled from the stashed voucher.
    expect(find.text('2112 2462 7680 2960 28'), findsOneWidget);
    expect(find.text('7195'), findsOneWidget);
    expect(find.textContaining('100.00 CHF'), findsOneWidget);
    // The wallet card (2400…) is a different number — no duplicate banner.
    expect(find.textContaining('already in your wallet'), findsNothing);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
  });

  testWidgets('a replayed import for a stored card shows the duplicate '
      'banner immediately', (tester) async {
    await seedEncryptedWallet(tester);
    // A card with the SAME number as the pending import is already stored.
    // unlock() re-reads the card list, so the sheet's on-open check sees it.
    await tester.runAsync(() async {
      await CardDao(db, crypto: crypto).insert(
        GiftCard.draft(cardNumber: '211224627680296028', pin: '7195'),
      );
    });
    await pumpGate(tester, configured: true);
    final container = containerOf(tester);

    container.read(pendingCardImportProvider.notifier).state =
        const PendingCardImport(cardNumber: '211224627680296028', pin: '7195');

    await tester.runAsync(() {
      return container.read(lockStateProvider.notifier).unlock('1357');
    });
    await tester.pumpAndSettle();

    expect(find.text('2112 2462 7680 2960 28'), findsOneWidget);
    expect(
      find.textContaining('already in your wallet'),
      findsOneWidget,
    );
  });

  testWidgets('correct PIN unlocks the wallet, backgrounding locks again',
      (tester) async {
    await seedEncryptedWallet(tester);

    await pumpGate(tester, configured: true);
    final container = containerOf(tester);

    await tester.runAsync(() {
      return container.read(lockStateProvider.notifier).unlock('1357');
    });
    await tester.pumpAndSettle();

    // Wallet is visible with the decrypted card. The hero label is
    // uppercase-styled ("TOTAL BALANCE") by the design system.
    expect(
      find.textContaining(RegExp('total balance', caseSensitive: false)),
      findsOneWidget,
    );
    // The decrypted card is available to the UI (rendering of the tile
    // itself is covered by the design sessions).
    final cards = container.read(cardListProvider).value ?? const [];
    expect(cards.single.cardNumber, '24001234567890123456');
    expect(cards.single.pin, '4321');
    expect(container.read(cryptoProvider).isUnlocked, isTrue);

    // App goes to the background: the key must be dropped and decrypted
    // cards must leave memory. (While paused the scheduler stops producing
    // frames, so the visible gate is asserted after the resume below.)
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(container.read(lockStateProvider), AppLockState.locked);
    expect(container.read(cryptoProvider).isUnlocked, isFalse);
    expect(container.read(cardListProvider).value ?? [], isEmpty);

    // Back in the foreground: the PIN gate is shown in unlock mode —
    // never in setup mode, which would imply the config was lost.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('Enter app PIN'), findsOneWidget);
    expect(find.text('Protect your wallet'), findsNothing);
  });
}
