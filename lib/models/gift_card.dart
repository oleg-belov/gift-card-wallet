/// Status of a Lidl gift card as reported by the balance-check page.
enum GiftCardStatus { aktiv, eingeloest, abgelaufen, unbekannt }

/// Minimum age of the last successful sync before an automatic refresh may
/// query Lidl again — keeps the polite-request rate low without the user
/// thinking about it. Explicit per-card refreshes bypass this.
const Duration kRefreshCooldown = Duration(hours: 2);

GiftCardStatus giftCardStatusFromRaw(String? raw) {
  switch (raw) {
    case 'aktiv':
      return GiftCardStatus.aktiv;
    case 'eingeloest':
      return GiftCardStatus.eingeloest;
    case 'abgelaufen':
      return GiftCardStatus.abgelaufen;
    default:
      return GiftCardStatus.unbekannt;
  }
}

/// German display label for a status, matching the wording of the portal.
String giftCardStatusLabel(GiftCardStatus status) {
  switch (status) {
    case GiftCardStatus.aktiv:
      return 'Aktiv';
    case GiftCardStatus.eingeloest:
      return 'Eingelöst';
    case GiftCardStatus.abgelaufen:
      return 'Abgelaufen';
    case GiftCardStatus.unbekannt:
      return 'Unbekannt';
  }
}

/// A single Lidl Switzerland gift card, stored locally on the device.
class GiftCard {
  GiftCard({
    required this.id,
    required this.cardNumber,
    required this.pin,
    this.nickname,
    this.balance = 0,
    this.initialBalance,
    this.currency = 'CHF',
    this.status = GiftCardStatus.unbekannt,
    this.expiryDate,
    this.lastRefreshed,
    this.isManuallyEdited = false,
    this.isFavorite = false,
    this.barcodeFormat,
    this.barcodeValue,
  });

  /// Creates a card that has not been saved yet (id assigned by the database).
  factory GiftCard.draft({
    required String cardNumber,
    required String pin,
    String? nickname,
    String? barcodeValue,
  }) {
    return GiftCard(
      id: null,
      cardNumber: cardNumber,
      pin: pin,
      nickname: nickname,
      barcodeValue: barcodeValue,
    );
  }

  final int? id;
  final String cardNumber;
  final String pin;
  final String? nickname;
  final double balance;

  /// Balance when the card entered the wallet: set from the first successful
  /// fetch or manual entry; online refreshes only change [balance].
  final double? initialBalance;
  final String currency;
  final GiftCardStatus status;

  /// ISO 8601 date (`YYYY-MM-DD`) so lexicographic order equals date order.
  final String? expiryDate;

  /// Epoch milliseconds of the last successful online sync.
  final int? lastRefreshed;
  final bool isManuallyEdited;

  /// Pinned cards surface through the Favorites filter in the wallet.
  final bool isFavorite;

  /// Barcode symbology detected during the scan (e.g. 'code128', 'ean13')
  /// so the checkout screen renders the same barcode the card carries.
  final String? barcodeFormat;

  /// Full barcode payload when it differs from the printed card number —
  /// GS1-128 element strings (AI 01 GTIN + AI 90 card number) as carried by
  /// real Lidl vouchers. Rendered at checkout so a cashier scanner reads the
  /// same bars the physical voucher has; null falls back to [cardNumber].
  final String? barcodeValue;

  /// The data to encode for the cashier's scanner.
  String get checkoutBarcode => barcodeValue ?? cardNumber;

  /// Fraction of the initial balance that is still left (0..1), or null when
  /// the initial amount is unknown — the UI hides progress bars then.
  double? get usageRatio {
    final initial = initialBalance;
    if (initial == null || initial <= 0) return null;
    return (balance / initial).clamp(0.0, 1.0);
  }

  GiftCard copyWith({
    int? id,
    String? cardNumber,
    String? pin,
    String? nickname,
    double? balance,
    double? initialBalance,
    bool clearInitialBalance = false,
    String? currency,
    GiftCardStatus? status,
    String? expiryDate,
    bool clearExpiryDate = false,
    int? lastRefreshed,
    bool clearLastRefreshed = false,
    bool? isManuallyEdited,
    bool? isFavorite,
    String? barcodeFormat,
    String? barcodeValue,
  }) {
    return GiftCard(
      id: id ?? this.id,
      cardNumber: cardNumber ?? this.cardNumber,
      pin: pin ?? this.pin,
      nickname: nickname ?? this.nickname,
      balance: balance ?? this.balance,
      initialBalance:
          clearInitialBalance ? null : (initialBalance ?? this.initialBalance),
      currency: currency ?? this.currency,
      status: status ?? this.status,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      lastRefreshed:
          clearLastRefreshed ? null : (lastRefreshed ?? this.lastRefreshed),
      isManuallyEdited: isManuallyEdited ?? this.isManuallyEdited,
      isFavorite: isFavorite ?? this.isFavorite,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
      barcodeValue: barcodeValue ?? this.barcodeValue,
    );
  }

  /// True when the expiry date is known and lies strictly before [today].
  /// [today] is a pure function argument so tests stay deterministic.
  bool isExpired(DateTime today) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    final todayIso = _isoDate(today);
    return expiry.compareTo(todayIso) < 0;
  }

  /// Whole days from [today] until expiry (negative if already expired).
  int? daysUntilExpiry(DateTime today) {
    final expiry = expiryDate;
    if (expiry == null) return null;
    final parts = expiry.split('-');
    final expiryDateTime = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    return expiryDateTime.difference(todayUtc).inDays;
  }

  /// A card belongs in the archive when it is spent or expired. Emptiness is
  /// only considered confirmed after a successful sync or a manual edit — a
  /// freshly added card (never synced) stays in the wallet so it remains
  /// visible and refreshable even if its first online fetch fails.
  bool isArchived(DateTime today) {
    if (isExpired(today)) return true;
    if (balance > 0) return false;
    return lastRefreshed != null || isManuallyEdited;
  }

  /// True when this card should appear in the active wallet and be refreshed.
  bool isActive(DateTime today) => !isArchived(today);

  /// True when an online refresh makes sense for this card: it sits in the
  /// wallet and is neither expired nor already known to be spent.
  bool isRefreshable(DateTime today) {
    if (isExpired(today)) return false;
    if (status == GiftCardStatus.abgelaufen) return false;
    return balance > 0 || (lastRefreshed == null && !isManuallyEdited);
  }

  /// True while the last successful sync is younger than [kRefreshCooldown]
  /// — automatic refreshes skip the network and keep showing the cached
  /// values. A card never synced is never cooling down.
  bool isRefreshCoolingDown(DateTime now) {
    final last = lastRefreshed;
    if (last == null) return false;
    return now.difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        ) <
        kRefreshCooldown;
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The balance column is TEXT-affinity since schema v3 (it stores
  /// ciphertext once encryption is enabled), so plaintext values can come
  /// back either as a number or as a numeric string.
  static double _balanceFromDb(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }

  Map<String, Object?> toDbMap() {
    final map = <String, Object?>{
      'cardNumber': cardNumber,
      'pin': pin,
      'nickname': nickname,
      'balance': balance,
      'initialBalance': initialBalance,
      'currency': currency,
      'status': status.name,
      'expiryDate': expiryDate,
      'lastRefreshed': lastRefreshed,
      'isManuallyEdited': isManuallyEdited ? 1 : 0,
      'isFavorite': isFavorite ? 1 : 0,
      'barcodeFormat': barcodeFormat,
      'barcodeValue': barcodeValue,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  static GiftCard fromDbMap(Map<String, Object?> map) {
    return GiftCard(
      id: map['id'] as int?,
      cardNumber: map['cardNumber'] as String,
      pin: map['pin'] as String,
      nickname: map['nickname'] as String?,
      balance: _balanceFromDb(map['balance']),
      initialBalance: _balanceFromNullableDb(map['initialBalance']),
      currency: (map['currency'] as String?) ?? 'CHF',
      status: GiftCardStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => GiftCardStatus.unbekannt,
      ),
      expiryDate: map['expiryDate'] as String?,
      lastRefreshed: map['lastRefreshed'] as int?,
      isManuallyEdited: (map['isManuallyEdited'] as int? ?? 0) == 1,
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
      barcodeFormat: map['barcodeFormat'] as String?,
      barcodeValue: map['barcodeValue'] as String?,
    );
  }

  /// Like [_balanceFromDb] but preserves "no value" (null column).
  static double? _balanceFromNullableDb(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }
}
