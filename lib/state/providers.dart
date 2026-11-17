import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database.dart';
import '../models/card_transaction.dart';
import '../models/gift_card.dart';
import '../services/balance_service.dart';
import '../services/crypto_service.dart';

/// Overridden in main() with the database opened before runApp().
final databaseProvider = Provider<Database>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

/// Overridden in main() with whether a crypto config (an app PIN) already
/// exists in the settings table.
final cryptoConfiguredProvider = Provider<bool>((ref) {
  throw UnimplementedError(
    'cryptoConfiguredProvider must be overridden in main()',
  );
});

/// The single crypto session; holds the PIN-derived key only while unlocked.
final cryptoProvider = Provider<CardCrypto>((ref) {
  return CardCrypto();
});

final cardDaoProvider = Provider<CardDao>((ref) {
  return CardDao(ref.watch(databaseProvider), crypto: ref.watch(cryptoProvider));
});

final transactionDaoProvider = Provider<TransactionDao>((ref) {
  return TransactionDao(
    ref.watch(databaseProvider),
    crypto: ref.watch(cryptoProvider),
  );
});

final balanceServiceProvider = Provider<BalanceService>((ref) {
  return BalanceService();
});

/// Prefill for the card entry sheet, deferred across an app lock: picking a
/// file in the system picker pauses the app, which locks the wallet and
/// unmounts the scan tab. The import result is stashed here and the scan
/// tab reopens the sheet right after the next unlock.
class PendingCardImport {
  const PendingCardImport({
    required this.cardNumber,
    this.pin,
    this.detectedValue,
    this.barcodeValue,
    this.barcodeFormat,
  });

  final String cardNumber;
  final String? pin;
  final double? detectedValue;
  final String? barcodeValue;
  final String? barcodeFormat;
}

final pendingCardImportProvider = StateProvider<PendingCardImport?>((ref) => null);

/// Settings key under which the manually chosen app language is persisted.
const kLocaleSettingKey = 'locale';

/// The app language picked in the UI; null means "follow the device".
final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier(ref);
});

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier(this._ref) : super(null) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final db = _ref.read(databaseProvider);
    final value = await getSetting(db, kLocaleSettingKey);
    if (value != null && mounted) {
      state = Locale(value);
    }
  }

  /// Toggles between English and German and persists the choice.
  Future<void> toggle() async {
    final current = state?.languageCode ??
        // Fall back to the device language when the user has not chosen yet.
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'de'
            ? 'de'
            : 'en');
    final next = current == 'de' ? 'en' : 'de';
    state = Locale(next);
    await setSetting(_ref.read(databaseProvider), kLocaleSettingKey, next);
  }
}

/// Where the app is in the PIN gate lifecycle.
enum AppLockState { setup, locked, unlocked }

/// Drives the app-lock gate: first-run PIN setup, unlocking, and locking
/// (which forgets the derived key so data at rest is ciphertext-only).
class LockNotifier extends StateNotifier<AppLockState> {
  LockNotifier(this._ref)
    : super(_readConfigured(_ref)
          ? AppLockState.locked
          : AppLockState.setup) {
    _configured = _readConfigured(_ref);
  }

  final Ref _ref;

  /// Whether a crypto config exists. [cryptoConfiguredProvider] is a startup
  /// snapshot (false during first-run) and must be tracked as it changes,
  /// otherwise locking after setup lands back on the setup screen.
  bool _configured = false;

  static bool _readConfigured(Ref ref) => ref.read(cryptoConfiguredProvider);

  /// First-run setup: derives the key from [pin], encrypts any pre-existing
  /// plaintext rows and stores the crypto config.
  Future<void> setup(String pin) async {
    final db = _ref.read(databaseProvider);
    final crypto = _ref.read(cryptoProvider);
    await enableEncryption(db, crypto, pin);
    _configured = true;
    state = AppLockState.unlocked;
    assert(() {
      debugPrint('E2E: wallet setup done');
      return true;
    }());
  }

  /// Verifies [pin] against the stored config and unlocks. Throws
  /// [WrongPinException] when the PIN is wrong.
  Future<void> unlock(String pin) async {
    final db = _ref.read(databaseProvider);
    final crypto = _ref.read(cryptoProvider);
    final config = await readCryptoConfig(db);
    if (config == null) {
      state = AppLockState.setup;
      return;
    }
    await crypto.unlock(pin, config);
    // The card list may hold a stale/empty state from before the lock.
    await _ref.read(cardListProvider.notifier).reload();
    state = AppLockState.unlocked;
    // Load + pre-solve the balance page in the background so a check the
    // user starts seconds later doesn't wait for page load and captcha.
    unawaited(_ref.read(balanceServiceProvider).prewarm());
    assert(() {
      debugPrint('E2E: wallet unlocked');
      return true;
    }());
  }

  /// Forgets the derived key and shows the PIN screen again.
  void lock() {
    if (state != AppLockState.unlocked) return;
    _ref.read(cryptoProvider).lock();
    // Drop decrypted cards from memory and cancel a refresh queue that
    // could no longer persist results.
    _ref.read(cardListProvider.notifier).reset();
    _ref.read(refreshProvider.notifier).stop();
    state = _configured ? AppLockState.locked : AppLockState.setup;
  }

  /// Re-encrypts all rows under a new PIN after verifying [oldPin].
  /// Throws [WrongPinException] when the old PIN is wrong.
  Future<void> changePin(String oldPin, String newPin) async {
    final db = _ref.read(databaseProvider);
    final crypto = _ref.read(cryptoProvider);
    await changeCardPin(db, crypto, oldPin, newPin);
  }
}

final lockStateProvider =
    StateNotifierProvider<LockNotifier, AppLockState>((ref) {
  return LockNotifier(ref);
});

/// Outcome of adding a card to the wallet.
enum AddCardStatus { added, duplicate }

class AddCardResult {
  const AddCardResult.added(this.id)
      : status = AddCardStatus.added,
        existing = null;

  const AddCardResult.duplicate(this.existing)
      : status = AddCardStatus.duplicate,
        id = null;

  final AddCardStatus status;
  final int? id;

  /// The card already in the wallet, set on duplicates.
  final GiftCard? existing;

  bool get isDuplicate => status == AddCardStatus.duplicate;
}

/// Holds every stored card; UI derives filtered views from this.
class CardListNotifier extends StateNotifier<AsyncValue<List<GiftCard>>> {
  CardListNotifier(this._dao, this._transactionDao)
    : super(const AsyncValue.loading()) {
    reload();
  }

  final CardDao _dao;
  final TransactionDao _transactionDao;

  Future<void> reload() async {
    try {
      final cards = await _dao.getAll();
      state = AsyncValue.data(cards);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Drops all decrypted card data from memory (used when the app locks).
  void reset() {
    state = const AsyncValue.data([]);
  }

  /// Inserts [draft] unless a card with the same number already exists.
  /// Duplicate imports (scanned twice, PDF re-imported) return the existing
  /// card instead of creating a second row.
  Future<AddCardResult> addCard(GiftCard draft) async {
    final existing = await _dao.getByCardNumber(draft.cardNumber);
    if (existing != null) {
      return AddCardResult.duplicate(existing);
    }
    final id = await _dao.insert(draft);
    await reload();
    return AddCardResult.added(id);
  }

  /// Persists [card]; records an `edit` activity entry when the balance
  /// changed (manual corrections, mark-as-empty, unarchive restores).
  Future<void> updateCard(GiftCard card) async {
    GiftCard? old;
    for (final c in state.value ?? const <GiftCard>[]) {
      if (c.id == card.id) {
        old = c;
        break;
      }
    }
    await _dao.update(card);
    final delta = old == null ? 0.0 : card.balance - old.balance;
    if (old != null && card.id != null && delta.abs() > 0.0001) {
      await _recordSilently(
        CardTransaction(
          cardId: card.id!,
          type: CardTransactionType.edit,
          amount: delta,
          balanceAfter: card.balance,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    await reload();
  }

  Future<void> setFavorite(GiftCard card, bool favorite) async {
    await _dao.update(card.copyWith(isFavorite: favorite));
    await reload();
  }

  Future<void> deleteCard(int id) async {
    await _dao.delete(id);
    await _recordSilentlyDeletion(id);
    await reload();
  }

  /// Deletes every archived card that was spent (balance 0, not expired) and
  /// its activity log. Returns the number of removed cards.
  Future<int> deleteSpentHistory(DateTime today) async {
    final cards = state.value ?? const <GiftCard>[];
    final spent = cards
        .where(
          (c) =>
              c.id != null &&
              c.isArchived(today) &&
              !c.isExpired(today) &&
              c.balance == 0,
        )
        .toList();
    for (final card in spent) {
      await _dao.delete(card.id!);
      await _recordSilentlyDeletion(card.id!);
    }
    if (spent.isNotEmpty) await reload();
    return spent.length;
  }

  /// Activity rows must never break a card mutation: a locked crypto session
  /// or a full disk should not lose the balance update itself.
  Future<void> _recordSilently(CardTransaction transaction) async {
    try {
      await _transactionDao.insert(transaction);
    } on StateError {
      // Crypto session locked mid-write; skip the history row.
    }
  }

  Future<void> _recordSilentlyDeletion(int cardId) async {
    try {
      await _transactionDao.deleteForCard(cardId);
    } on StateError {
      // Same as above — deletion of the card takes precedence.
    }
  }
}

final cardListProvider =
    StateNotifierProvider<CardListNotifier, AsyncValue<List<GiftCard>>>(
  (ref) => CardListNotifier(
    ref.watch(cardDaoProvider),
    ref.watch(transactionDaoProvider),
  ),
);

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

final activeCardsProvider = Provider<List<GiftCard>>((ref) {
  final cards = ref.watch(cardListProvider).value ?? const <GiftCard>[];
  final today = _today();
  return cards.where((c) => c.isActive(today)).toList()..sort(_byExpiryThenId);
});

final archivedCardsProvider = Provider<List<GiftCard>>((ref) {
  final cards = ref.watch(cardListProvider).value ?? const <GiftCard>[];
  final today = _today();
  return cards.where((c) => c.isArchived(today)).toList()
    ..sort(_byExpiryThenId);
});

final totalActiveBalanceProvider = Provider<double>((ref) {
  return ref
      .watch(activeCardsProvider)
      .fold(0.0, (sum, c) => sum + c.balance);
});

/// Balance history of one card, newest first. Watching [cardListProvider]
/// keeps it in sync after refreshes, edits and deletions.
final cardTransactionsProvider =
    FutureProvider.family<List<CardTransaction>, int>((ref, cardId) async {
  ref.watch(cardListProvider);
  final dao = ref.watch(transactionDaoProvider);
  return dao.listForCard(cardId);
});

/// Aggregates for the archive screen's stat cards.
class ArchivedStats {
  const ArchivedStats({
    required this.count,
    required this.spentCount,
    required this.expiredCount,
    required this.totalRedeemed,
  });

  final int count;
  final int spentCount;
  final int expiredCount;

  /// Sum of the initial amounts of fully spent cards (unknown ones skipped).
  final double totalRedeemed;
}

final archivedStatsProvider = Provider<ArchivedStats>((ref) {
  final cards = ref.watch(archivedCardsProvider);
  final today = _today();
  final spent = cards.where((c) => !c.isExpired(today)).toList();
  return ArchivedStats(
    count: cards.length,
    spentCount: spent.length,
    expiredCount: cards.length - spent.length,
    totalRedeemed:
        spent.fold(0.0, (sum, c) => sum + (c.initialBalance ?? 0)),
  );
});

int _byExpiryThenId(GiftCard a, GiftCard b) {
  final aExp = a.expiryDate;
  final bExp = b.expiryDate;
  if (aExp == null && bExp == null) return a.id!.compareTo(b.id!);
  if (aExp == null) return 1;
  if (bExp == null) return -1;
  final cmp = aExp.compareTo(bExp);
  if (cmp != 0) return cmp;
  return a.id!.compareTo(b.id!);
}

/// Progress of the online refresh queue shown on the home screen.
enum RefreshPhase { idle, running, captchaStall, done }

class RefreshState {
  const RefreshState({
    this.phase = RefreshPhase.idle,
    this.total = 0,
    this.completed = 0,
    this.currentLabel = '',
    this.currentCardId,
    this.errorKey,
    this.errorDetail,
  });

  final RefreshPhase phase;
  final int total;
  final int completed;
  final String currentLabel;
  final int? currentCardId;

  /// Locale-neutral error key (see [RefreshErrors]) + technical detail.
  final String? errorKey;
  final String? errorDetail;

  RefreshState copyWith({
    RefreshPhase? phase,
    int? total,
    int? completed,
    String? currentLabel,
    int? currentCardId,
    String? errorKey,
    String? errorDetail,
    bool clearError = false,
  }) {
    return RefreshState(
      phase: phase ?? this.phase,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      currentLabel: currentLabel ?? this.currentLabel,
      currentCardId: currentCardId ?? this.currentCardId,
      errorKey: clearError ? null : (errorKey ?? this.errorKey),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    );
  }
}

/// Runs cards through the hidden WebView one at a time and persists results.
class RefreshNotifier extends StateNotifier<RefreshState> {
  RefreshNotifier(this._ref) : super(const RefreshState());

  final Ref _ref;
  bool _paused = false;

  bool get isRunning => state.phase == RefreshPhase.running;

  /// Cancels the queue. Called when the app locks; the next loop iteration
  /// (and a persistence attempt that finds the crypto session locked) stops.
  void stop() {
    _paused = true;
    state = const RefreshState();
  }

  /// Refreshes every refreshable card, earliest expiry first. Cards synced
  /// within the cooldown window are skipped (cached values shown); explicit
  /// per-card queries bypass the cooldown.
  Future<void> refreshAll() async {
    if (isRunning) return;
    final dao = _ref.read(cardDaoProvider);
    final service = _ref.read(balanceServiceProvider);
    final cards = await dao.getRefreshable(DateTime.now());

    state = RefreshState(
      phase: RefreshPhase.running,
      total: cards.length,
      completed: 0,
    );

    await _runQueue(cards, service, dao);
  }

  /// Fetches the initial values for a freshly added card.
  Future<RefreshOutcome> refreshSingle(GiftCard card) async {
    // The hidden WebView serves one query at a time — a second concurrent
    // check would cancel the running one (single-use tokens too). The
    // detail button shows a spinner while running, so this only guards
    // race taps.
    if (isRunning) {
      return RefreshOutcome(
        result: BalanceResult(raw: 'busy'),
        errorKey: RefreshErrors.cancelled,
      );
    }
    final dao = _ref.read(cardDaoProvider);
    final service = _ref.read(balanceServiceProvider);
    state = RefreshState(
      phase: RefreshPhase.running,
      total: 1,
      completed: 0,
      currentLabel: card.nickname ?? card.cardNumber,
      // Single-card refreshes must point the queue at their card too, so the
      // captcha banner and the Balance tab can open the manual check.
      currentCardId: card.id,
    );
    final outcome = await _processCard(card, service, dao, updateUi: false);
    state = state.copyWith(
      phase: RefreshPhase.done,
      completed: 1,
      errorKey: outcome.errorKey,
      errorDetail: outcome.errorDetail,
      clearError: outcome.errorKey == null,
    );
    // Re-park a solved page for the next query.
    unawaited(service.prewarm());
    return outcome;
  }

  Future<void> _runQueue(
    List<GiftCard> cards,
    BalanceService service,
    CardDao dao,
  ) async {
    for (final card in cards) {
      if (_paused) {
        // User opened the manual check screen; it resumes the queue via
        // [resumeAfterManual].
        state = state.copyWith(phase: RefreshPhase.captchaStall);
        return;
      }
      state = state.copyWith(
        currentLabel: card.nickname ?? _maskedNumber(card.cardNumber),
        currentCardId: card.id,
      );
      final outcome = await _processCard(card, service, dao);
      if (outcome.needsCaptchaHelp) {
        _paused = true;
        state = state.copyWith(
          phase: RefreshPhase.captchaStall,
          errorKey: outcome.errorKey,
          errorDetail: outcome.errorDetail,
        );
        return;
      }
    }
    state = state.copyWith(
      phase: RefreshPhase.done,
      completed: state.total,
    );
  }

  Future<RefreshOutcome> _processCard(
    GiftCard card,
    BalanceService service,
    CardDao dao, {
    bool updateUi = true,
  }) async {
    final outcome = await service.checkCard(
      cardNumber: card.cardNumber,
      pin: card.pin,
      onStalled: () {
        if (mounted && updateUi) {
          state = state.copyWith(phase: RefreshPhase.captchaStall);
        }
      },
    );

    if (outcome.result.isSuccess) {
      final newBalance = outcome.result.balance!;
      final isFirstSync = card.lastRefreshed == null;
      final updated = card.copyWith(
        balance: newBalance,
        // The add-time amount: set from the first successful fetch and kept
        // afterwards — later syncs only change the remaining balance.
        initialBalance: card.initialBalance ?? (isFirstSync ? newBalance : null),
        status: outcome.result.status,
        expiryDate: outcome.result.expiryDate,
        clearExpiryDate: outcome.result.expiryDate == null,
        lastRefreshed: DateTime.now().millisecondsSinceEpoch,
      );
      if (kDebugMode) {
        debugPrint('SYNC: card ${card.id} balance '
            '${outcome.result.balance} status ${outcome.result.status}');
      }
      try {
        await dao.update(updated);
        if (updated.id != null) {
          await _recordBalanceChange(
            cardId: updated.id!,
            previousBalance: card.balance,
            newBalance: newBalance,
            isFirstSync: isFirstSync,
          );
        }
        await _ref.read(cardListProvider.notifier).reload();
      } on StateError {
        // The app locked while the fetch was in flight; the key is gone so
        // the result cannot be persisted. The next refresh will pick it up.
      }
      if (updateUi) {
        state = state.copyWith(completed: state.completed + 1);
      }
    } else {
      if (kDebugMode) {
        debugPrint('SYNC: card ${card.id} failed: '
            '${outcome.errorKey} (${outcome.errorDetail})');
      }
      if (updateUi) {
        // A cancelled query (app locked, superseded by another refresh) is
        // not an error — surfacing it would show "Cancelled" forever, since
        // the snackbar/banner is displayed while the app is paused and the
        // dismiss timer only runs after unlock.
        final cancelled = outcome.errorKey == RefreshErrors.cancelled;
        state = state.copyWith(
          completed: state.completed + 1,
          errorKey: cancelled ? null : outcome.errorKey,
          errorDetail: cancelled ? null : outcome.errorDetail,
          clearError: cancelled,
        );
      }
    }
    return outcome;
  }

  /// Appends the matching activity row for a persisted balance change:
  /// activation on the first sync, spend/reload for later deltas.
  Future<void> _recordBalanceChange({
    required int cardId,
    required double previousBalance,
    required double newBalance,
    required bool isFirstSync,
  }) async {
    final delta = newBalance - previousBalance;
    final CardTransactionType type;
    final double? amount;
    if (isFirstSync) {
      type = CardTransactionType.activation;
      amount = newBalance;
    } else if (delta < 0) {
      type = CardTransactionType.spend;
      amount = delta;
    } else if (delta > 0) {
      type = CardTransactionType.reload;
      amount = delta;
    } else {
      // Same balance as before — nothing worth logging.
      return;
    }
    try {
      await _ref.watch(transactionDaoProvider).insert(
            CardTransaction(
              cardId: cardId,
              type: type,
              amount: amount,
              balanceAfter: newBalance,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    } on StateError {
      // Crypto session locked mid-queue; the card update above already
      // failed in that case too.
    }
  }

  /// Called when the manual check screen finished (or was dismissed) so the
  /// remaining cards can continue refreshing.
  Future<void> resumeAfterManual() async {
    _paused = false;
    if (state.phase == RefreshPhase.captchaStall) {
      state = state.copyWith(
        phase: RefreshPhase.idle,
        clearError: true,
      );
      await refreshAll();
    }
  }

  void dismissStatus() {
    if (state.phase == RefreshPhase.done || state.phase == RefreshPhase.captchaStall) {
      state = const RefreshState();
    }
  }

  static String _maskedNumber(String number) {
    if (number.length <= 4) return number;
    return '•••• ${number.substring(number.length - 4)}';
  }
}

final refreshProvider =
    StateNotifierProvider<RefreshNotifier, RefreshState>(
  (ref) => RefreshNotifier(ref),
);
