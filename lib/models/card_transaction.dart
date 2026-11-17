import 'package:flutter/foundation.dart';

/// Kind of balance change recorded in the activity log.
enum CardTransactionType { activation, spend, reload, edit }

CardTransactionType? cardTransactionTypeFromRaw(String? raw) {
  for (final type in CardTransactionType.values) {
    if (type.name == raw) return type;
  }
  return null;
}

/// One row of the "Recent Activity" history for a gift card. Amounts are
/// signed deltas: negative for spending, positive for loads/top-ups.
@immutable
class CardTransaction {
  const CardTransaction({
    this.id,
    required this.cardId,
    required this.type,
    this.amount,
    this.balanceAfter,
    this.note,
    required this.createdAt,
  });

  final int? id;
  final int cardId;
  final CardTransactionType type;

  /// Signed change applied to the balance, in the card currency. Null when
  /// the event is purely informational.
  final double? amount;

  /// Balance directly after the event, when it is known.
  final double? balanceAfter;
  final String? note;

  /// Epoch milliseconds.
  final int createdAt;

  CardTransaction copyWith({
    int? id,
    int? cardId,
    CardTransactionType? type,
    double? amount,
    double? balanceAfter,
    String? note,
    int? createdAt,
  }) {
    return CardTransaction(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toDbMap() {
    final map = <String, Object?>{
      'cardId': cardId,
      'type': type.name,
      'amount': amount,
      'balanceAfter': balanceAfter,
      'note': note,
      'createdAt': createdAt,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  static CardTransaction fromDbMap(Map<String, Object?> map) {
    double? parseAmount(Object? raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    return CardTransaction(
      id: map['id'] as int?,
      cardId: map['cardId'] as int,
      type: cardTransactionTypeFromRaw(map['type'] as String?) ??
          CardTransactionType.edit,
      amount: parseAmount(map['amount']),
      balanceAfter: parseAmount(map['balanceAfter']),
      note: map['note'] as String?,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CardTransaction &&
      other.id == id &&
      other.cardId == cardId &&
      other.type == type &&
      other.amount == amount &&
      other.balanceAfter == balanceAfter &&
      other.note == note &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, cardId, type, amount, balanceAfter, note, createdAt);
}
