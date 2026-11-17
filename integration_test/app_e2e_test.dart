import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lidl_gift_card/db/database.dart';
import 'package:lidl_gift_card/main.dart';
import 'package:lidl_gift_card/state/providers.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// On-device end-to-end journey (run on an emulator/device):
///
/// ```
/// flutter test integration_test/app_e2e_test.dart -d <device>
/// ```
///
/// Drives the REAL app with the REAL sqflite database and crypto: PIN
/// setup → wallet → add the real voucher card via the entry sheet → the
/// online check fails (Lidl's WAF blocks WebViews; see README) → save
/// anyway → duplicate import is blocked. The network check makes this take
/// roughly two minutes; everything before it is seconds.
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // Fresh install state for every run: remove the previous database before
  // the app opens it, so the PIN gate starts in setup mode.
  final dbDir = await getDatabasesPath();
  final dbPath = p.join(dbDir, 'lidl_gift_card.db');
  await deleteDatabase(dbPath);
  final db = await openCardDatabase();
  final cryptoConfigured = await readCryptoConfig(db) != null;

  const cardNumber = '211224627680296028';
  const voucherPin = '7195';
  const appPin = '1357';

  Future<void> settleUntil(
    WidgetTester tester,
    Finder finder, {
    required Duration timeout,
    Duration step = const Duration(milliseconds: 250),
  }) async {
    // Integration tests run against live plugin futures; plain pumpAndSettle
    // would stop at the first frame gap. Poll on real time instead.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(step);
    }
    fail('Timed out waiting for ${finder.toString()} '
        '(looked for ${timeout.inSeconds}s)');
  }

  testWidgets('full journey: setup → import → save → duplicate blocked',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          cryptoConfiguredProvider.overrideWithValue(cryptoConfigured),
        ],
        child: const LidlGiftCardApp(),
      ),
    );
    await tester.pump();

    // --- First run: the PIN setup screen -------------------------------
    expect(find.text('Protect your wallet'), findsOneWidget);
    final pinFields = find.byType(TextFormField);
    expect(pinFields, findsNWidgets(2));
    await tester.enterText(pinFields.at(0), appPin);
    await tester.enterText(pinFields.at(1), appPin);
    await tester.pump();
    await tester.tap(find.text('Enable protection'));
    await settleUntil(tester, find.textContaining('No active cards.'),
        timeout: const Duration(minutes: 2));

    // --- Add the real voucher card through the entry sheet -------------
    await tester.tap(find.text('Enter Code'));
    await settleUntil(tester, find.text('Check Balance & Save Card'),
        timeout: const Duration(seconds: 10));

    final sheetFields = find.byType(TextFormField);
    expect(sheetFields, findsNWidgets(3)); // number, PIN, nickname
    await tester.enterText(sheetFields.at(0), cardNumber);
    await tester.enterText(sheetFields.at(1), voucherPin);
    await tester.pump();

    // The online check runs through the hidden WebView and fails against
    // Lidl's WAF (see README "Known limitation") — that is the expected
    // path here; it just has to take its time.
    await tester.tap(find.text('Check Balance & Save Card'));
    await settleUntil(tester, find.text('Balance check failed'),
        timeout: const Duration(minutes: 5));
    expect(find.text('Save anyway'), findsOneWidget);

    await tester.tap(find.text('Save anyway'));
    await settleUntil(tester, find.textContaining('6028'),
        timeout: const Duration(seconds: 10));

    // The card landed in the wallet exactly once.
    expect(find.text('1 active card'), findsOneWidget);
    expect(find.textContaining('Card ending in'), findsOneWidget);

    // --- Duplicate protection ------------------------------------------
    await tester.tap(find.text('Enter Code'));
    await settleUntil(tester, find.text('Check Balance & Save Card'),
        timeout: const Duration(seconds: 10));
    await tester.enterText(find.byType(TextFormField).at(0), cardNumber);
    await tester.enterText(find.byType(TextFormField).at(1), voucherPin);
    await tester.pump();
    await tester.tap(find.text('Check Balance & Save Card'));

    // The duplicate check runs before any network call — instant.
    await settleUntil(
      tester,
      find.textContaining('already in your wallet'),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('Save anyway'), findsNothing);

    // Close the sheet (X in the header) — still exactly one card.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await settleUntil(tester, find.textContaining('TOTAL BALANCE'),
        timeout: const Duration(seconds: 10));
    expect(find.text('1 active card'), findsOneWidget);

    // (Lock-gate lifecycle behavior is covered by test/lock_gate_test.dart
    // on the host — synthetic transitions would trip Flutter's lifecycle
    // assertions here, since the runner already paused the real activity.)
  }, timeout: const Timeout(Duration(minutes: 12)));
}
