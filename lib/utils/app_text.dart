import '../l10n/generated/app_localizations.dart';
import '../models/gift_card.dart';
import '../services/balance_service.dart';

/// Maps a machine-readable refresh error key to a localized message.
String localizedRefreshError(
  AppLocalizations l10n,
  String? key,
  String? detail,
) {
  final base = switch (key) {
    RefreshErrors.cancelled => l10n.errCancelled,
    RefreshErrors.webviewStart => l10n.errWebviewStart,
    RefreshErrors.loadFailed => l10n.errLoadFailed,
    RefreshErrors.formNotReady => l10n.errFormNotReady,
    RefreshErrors.fillFailed => l10n.errFillFailed,
    RefreshErrors.noResult => l10n.errNoResult,
    RefreshErrors.cardNotFound => l10n.errCardNotFound,
    RefreshErrors.apiError => l10n.errApiError,
    RefreshErrors.generic || null => l10n.errQueryFailedGeneric,
    _ => key,
  };
  return detail == null || detail.isEmpty ? base : '$base ($detail)';
}

/// Localized display label for a card status.
String localizedStatusLabel(AppLocalizations l10n, GiftCardStatus status) {
  switch (status) {
    case GiftCardStatus.aktiv:
      return l10n.statusAktiv;
    case GiftCardStatus.eingeloest:
      return l10n.statusEingeloest;
    case GiftCardStatus.abgelaufen:
      return l10n.statusAbgelaufen;
    case GiftCardStatus.unbekannt:
      return l10n.statusUnbekannt;
  }
}
