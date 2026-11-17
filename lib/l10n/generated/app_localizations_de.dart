// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Geschenkkarten-Wallet';

  @override
  String get unofficialLabel =>
      'Inoffizielle Lidl-Wallet · Nur für den Privatgebrauch';

  @override
  String get personalUseNotice =>
      'Inoffizielle App zur Verwaltung deiner Lidl-Geschenkkarten. Unabhängig entwickelt und nur für den Privatgebrauch.';

  @override
  String get walletTab => 'Wallet';

  @override
  String get archiveTab => 'Archiv';

  @override
  String get refreshAll => 'Alle aktualisieren';

  @override
  String get emptyWalletBody =>
      'Keine aktiven Karten.\nScanne eine Geschenkkarte, um sie hinzuzufügen – leere oder abgelaufene Karten landen automatisch im Archiv.';

  @override
  String totalBalance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gesamtguthaben ($count Karten aktiv)',
      one: 'Gesamtguthaben (1 Karte aktiv)',
      zero: 'Gesamtguthaben (keine aktiven Karten)',
    );
    return '$_temp0';
  }

  @override
  String get expiryUnknown => 'Gültigkeitsdatum unbekannt';

  @override
  String get expired => 'Abgelaufen';

  @override
  String get expiresToday => 'Läuft heute ab';

  @override
  String get expiresTomorrow => 'Läuft morgen ab';

  @override
  String expiresInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Läuft in $days Tagen ab',
      one: 'Läuft morgen ab',
      zero: 'Läuft heute ab',
    );
    return '$_temp0';
  }

  @override
  String get manuallyEdited => 'Manuell bearbeitet';

  @override
  String get statusAktiv => 'Aktiv';

  @override
  String get statusEingeloest => 'Eingelöst';

  @override
  String get statusAbgelaufen => 'Abgelaufen';

  @override
  String get statusUnbekannt => 'Unbekannt';

  @override
  String get captchaDefaultTitle => 'Sicherheitsprüfung blockiert die Abfrage';

  @override
  String get captchaBannerAction =>
      'Tippen, um die Prüfung auf dem Bildschirm abzuschließen';

  @override
  String get cardTitle => 'Geschenkkarte';

  @override
  String get cardDeleted => 'Diese Karte wurde gelöscht.';

  @override
  String get refreshOnlineTooltip => 'Online abfragen';

  @override
  String get editTooltip => 'Manuell bearbeiten';

  @override
  String get balanceLabel => 'Guthaben';

  @override
  String get statusLabel => 'Status';

  @override
  String get expiryLabel => 'Gültigkeitsdatum';

  @override
  String get lastUpdatedLabel => 'Zuletzt aktualisiert';

  @override
  String get neverSynced => 'nie (manuell oder noch nie synchronisiert)';

  @override
  String get markEmpty => 'Als leer markieren';

  @override
  String get balanceUpdated => 'Guthaben aktualisiert';

  @override
  String get queryFailed => 'Abfrage fehlgeschlagen';

  @override
  String get editTitle => 'Manuell bearbeiten';

  @override
  String get balanceField => 'Guthaben (CHF)';

  @override
  String get invalidAmount => 'Ungültiger Betrag';

  @override
  String get expiryField => 'Gültigkeitsdatum (JJJJ-MM-TT, leer = unbekannt)';

  @override
  String get invalidExpiryFormat => 'Format: JJJJ-MM-TT';

  @override
  String get nicknameField => 'Notiz / Spitzname';

  @override
  String get save => 'Speichern';

  @override
  String get archiveEmpty =>
      'Das Archiv ist leer.\n\nHier landen Karten mit 0.00 CHF oder abgelaufenem Gültigkeitsdatum – nur als Referenz.';

  @override
  String get deleteCardTitle => 'Karte löschen?';

  @override
  String get deleteCardBody =>
      'Die gespeicherten Daten dieser Karte werden endgültig entfernt.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get scanTitle => 'Karte scannen';

  @override
  String get manual => 'Manuell';

  @override
  String get cardDetected => 'Karte erkannt';

  @override
  String get pinField => 'PIN (4 Ziffern)';

  @override
  String get invalidPin => 'Bitte 4 Ziffern eingeben';

  @override
  String get noteField => 'Notiz (optional)';

  @override
  String get noteHint => 'z. B. Geburtstagskarte';

  @override
  String get saveAndFetch => 'Speichern & Guthaben abfragen';

  @override
  String get scanHint => 'Barcode der Geschenkkarte in den Rahmen halten';

  @override
  String cameraUnavailable(String error) {
    return 'Kamera nicht verfügbar.\n$error';
  }

  @override
  String get manualEntryTitle => 'Manuell eingeben';

  @override
  String get cardNumberField => 'Kartennummer (18-20 Ziffern)';

  @override
  String get invalidCardNumber => 'Bitte 15-22 Ziffern eingeben';

  @override
  String get saveAndQuery => 'Speichern & abfragen';

  @override
  String savedBalanceMsg(String amount) {
    return 'Karte gespeichert – Guthaben: $amount CHF';
  }

  @override
  String savedFetchFailedMsg(String error) {
    return 'Karte gespeichert. Online-Abfrage schlug fehl: $error';
  }

  @override
  String get manualCheckTitle => 'Manuelle Abfrage';

  @override
  String get manualCheckLoading => 'Seite lädt…';

  @override
  String get manualCheckReady => 'Bereit – Abfrage ausfüllen.';

  @override
  String manualCheckResponse(String message) {
    return 'Antwort: $message';
  }

  @override
  String get manualCheckHint =>
      'Bitte Kartennummer und PIN auf der Seite eingeben und absenden – die App übernimmt das Ergebnis automatisch.';

  @override
  String balanceSavedMsg(String amount) {
    return 'Guthaben gespeichert: $amount CHF';
  }

  @override
  String get noCardInEdit => 'Keine Karte in Bearbeitung.';

  @override
  String get errCancelled => 'Abgebrochen';

  @override
  String get errWebviewStart => 'WebView konnte nicht gestartet werden';

  @override
  String get errLoadFailed => 'Konnte Seite nicht laden';

  @override
  String get errFormNotReady => 'Formular oder Sicherheitsprüfung nicht bereit';

  @override
  String get errFillFailed => 'Ausfüllen fehlgeschlagen';

  @override
  String get errNoResult => 'Kein Ergebnis erhalten';

  @override
  String get errQueryFailedGeneric => 'Guthaben konnte nicht abgefragt werden';

  @override
  String get errCardNotFound => 'Karte nicht gefunden oder PIN falsch';

  @override
  String get errApiError => 'Karte konnte nicht abgefragt werden';

  @override
  String get languageTooltip => 'Sprache / Language';

  @override
  String get lockSetupTitle => 'Wallet schützen';

  @override
  String get lockSetupSubtitle =>
      'Wählen Sie eine 4-stellige PIN. Ihre Kartendaten werden damit verschlüsselt gespeichert.';

  @override
  String get lockSetupWarning =>
      'Wenn Sie diese PIN vergessen, können gespeicherte Karten nicht mehr entschlüsselt werden — die App-Daten müssten gelöscht und alle Karten neu angelegt werden.';

  @override
  String get appPinField => 'App-PIN (4 Ziffern)';

  @override
  String get confirmAppPinField => 'App-PIN wiederholen';

  @override
  String get lockSetupButton => 'Schutz aktivieren';

  @override
  String get lockUnlockTitle => 'App-PIN eingeben';

  @override
  String get lockUnlockButton => 'Entsperren';

  @override
  String get wrongPin => 'Falsche PIN.';

  @override
  String get pinMismatch => 'Die PINs stimmen nicht überein.';

  @override
  String tooManyAttempts(int seconds) {
    return 'Zu viele Versuche. Bitte in $seconds s erneut versuchen.';
  }

  @override
  String get changePinMenu => 'PIN ändern';

  @override
  String get changePinTitle => 'App-PIN ändern';

  @override
  String get currentPinField => 'Aktuelle PIN';

  @override
  String get newPinField => 'Neue PIN (4 Ziffern)';

  @override
  String get confirmNewPinField => 'Neue PIN wiederholen';

  @override
  String get pinChangedMsg => 'App-PIN geändert.';

  @override
  String get cardsTab => 'Karten';

  @override
  String get scanTab => 'Scannen';

  @override
  String get balanceCheckTab => 'Guthaben';

  @override
  String get profileTab => 'Profil';

  @override
  String get heroTotalLabel => 'GUTHABEN INSGESAMT';

  @override
  String activeCardsChip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Karten aktiv',
      one: '1 Karte aktiv',
    );
    return '$_temp0';
  }

  @override
  String get scanCardCta => 'Karte scannen';

  @override
  String get enterCodeCta => 'Code eingeben';

  @override
  String get filterAllActive => 'Alle aktiv';

  @override
  String get filterExpiringSoon => 'Läuft bald ab';

  @override
  String get filterFavorites => 'Favoriten';

  @override
  String get showBarcode => 'Barcode anzeigen';

  @override
  String viewArchivedRow(int count) {
    return 'Alte Karten gesucht? Archivierte Karten ansehen ($count)';
  }

  @override
  String get urgentBadge => 'DRINGEND';

  @override
  String urgentStripLine(String countdown, String date) {
    return '$countdown ($date)';
  }

  @override
  String validUntil(String date) {
    return 'Gültig bis $date';
  }

  @override
  String cardEndingIn(String last4) {
    return 'Karte endet auf •••• $last4';
  }

  @override
  String ofInitialAmount(String amount) {
    return 'von $amount';
  }

  @override
  String get scanModeBarcode => 'Barcode';

  @override
  String get scanModeCardPin => 'Karte & PIN';

  @override
  String get scanModeFile => 'Bild/PDF';

  @override
  String get pdfImportNoData =>
      'Keine Kartendaten im PDF gefunden. Bitte Codes manuell eingeben.';

  @override
  String get pdfImportFailed => 'Diese Datei konnte nicht gelesen werden';

  @override
  String pdfAmountDetected(String amount) {
    return 'Betrag erkannt: $amount – wird beim Online-Check verifiziert';
  }

  @override
  String get whereToFindCodes => 'Wo finde ich Kartencodes?';

  @override
  String get backOfPhysicalCard => 'Rückseite der Karte';

  @override
  String digitNumberLabel(int digits) {
    return '$digits-stellige Nummer';
  }

  @override
  String get scratchPinLabel => 'Rubbel-PIN';

  @override
  String get quickPaste => 'Schnell einfügen';

  @override
  String get pinScratchHint =>
      'Vorsichtig rubbeln, um die 4-stellige PIN freizulegen';

  @override
  String get nicknameOptional => 'Karten-Spitzname';

  @override
  String get nicknameHint => 'Hilft, die Karte an der Kasse wiederzuerkennen';

  @override
  String get checkingBalance => 'Lidl-Guthabenabfrage läuft…';

  @override
  String get cardVerifiedTitle => 'Karte erfolgreich verifiziert';

  @override
  String get cardVerifiedBody =>
      'Gültige Lidl-Karte erkannt. Das Guthaben wird in Ihrer Wallet gespeichert.';

  @override
  String get checkBalanceAndSave => 'Guthaben prüfen & Karte speichern';

  @override
  String get saveAnyway => 'Trotzdem speichern';

  @override
  String get openManualCheck => 'Guthabenseite öffnen — Captcha lösen';

  @override
  String cardAlreadyImported(String name) {
    return 'Diese Karte ist bereits in der Wallet ($name)';
  }

  @override
  String get verificationFailedTitle => 'Guthabenabfrage fehlgeschlagen';

  @override
  String get scanBarcodeInstead => 'Stattdessen Barcode scannen';

  @override
  String get giftCardLabel => 'GESCHENKKARTE';

  @override
  String get currentBalance => 'Aktuelles Guthaben';

  @override
  String get securityPin => 'Sicherheits-PIN';

  @override
  String get maxBrightnessNote => 'Maximale Helligkeit für das Scannen aktiv';

  @override
  String get barcodeModeLabel => 'Barcode';

  @override
  String get qrModeLabel => 'QR-Code';

  @override
  String get tapToExpand => 'Tippen für Vollbild an der Kasse';

  @override
  String get recentActivity => 'Letzte Aktivität';

  @override
  String get viewAll => 'Alle anzeigen';

  @override
  String get activityActivation => 'Kartenaktivierung';

  @override
  String get activityInitialLoad => 'Erstaufladung';

  @override
  String get activitySpend => 'Einkauf';

  @override
  String get activityReload => 'Aufladung';

  @override
  String get activityEdit => 'Manuelle Korrektur';

  @override
  String get archiveThisCard => 'Karte archivieren';

  @override
  String get archivedFootnote =>
      'Archivierte Karten bleiben in Ihrem Archiv zugänglich.';

  @override
  String get restoreToWallet => 'Zurück in die Wallet';

  @override
  String get favoriteAdd => 'Zu Favoriten hinzufügen';

  @override
  String get favoriteRemove => 'Aus Favoriten entfernen';

  @override
  String expiryBannerLine(String date) {
    return 'Gültigkeitsdatum: $date';
  }

  @override
  String daysRemaining(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage verbleibend!',
      one: '1 Tag verbleibend!',
    );
    return '$_temp0';
  }

  @override
  String get useInStore =>
      'In jeder Lidl-Filiale oder online auf lidl.ch einlösbar';

  @override
  String get fullScreenBarcode => 'Kassen-Barcode';

  @override
  String get cardArchivedMsg => 'Karte archiviert';

  @override
  String get cardRestoredMsg => 'Karte zurück in die Wallet';

  @override
  String get revealPin => 'PIN anzeigen';

  @override
  String get hidePin => 'PIN verbergen';

  @override
  String get archiveSearchHint =>
      'Nach Jahr, Name oder letzten Ziffern filtern…';

  @override
  String get spentArchiveLabel => 'Verbraucht';

  @override
  String get totalRedeemed => 'Insgesamt eingelöst';

  @override
  String get cardsCountLabel => 'Kartenanzahl';

  @override
  String get storedVouchers => 'Gespeicherte Gutscheine';

  @override
  String get filterAllArchived => 'Alle archiviert';

  @override
  String get filterFullySpent => 'Voll verbraucht';

  @override
  String get filterExpired => 'Abgelaufen';

  @override
  String get fullyRedeemed => 'Vollständig eingelöst';

  @override
  String unspentAmount(String amount) {
    return '$amount ungenutzt';
  }

  @override
  String expiredOn(String date) {
    return 'Abgelaufen am $date';
  }

  @override
  String spentOn(String date) {
    return 'Verbraucht am $date';
  }

  @override
  String get viewDetails => 'Details ansehen';

  @override
  String get clearSpentHistory => 'Verbrauchte Karten löschen';

  @override
  String get clearSpentHistoryBody =>
      'Dadurch werden Einträge mit Restguthaben 0.00 endgültig entfernt.';

  @override
  String clearedHistoryMsg(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Karten entfernt',
      one: '1 Karte entfernt',
    );
    return '$_temp0';
  }

  @override
  String get balanceCheckTitle => 'Guthabenabfrage';

  @override
  String get balanceCheckIntro =>
      'Öffne die Lidl-Guthabenseite für deine Karte, wenn ein Captcha die automatische Abfrage blockiert.';

  @override
  String get pickCardToCheck => 'Karte für die Abfrage wählen';

  @override
  String get openBalancePage => 'Guthabenseite öffnen';

  @override
  String refreshQueueStatus(int completed, int total) {
    return 'Prüfe $completed/$total…';
  }

  @override
  String get currentlyChecking => 'Wird gerade geprüft';

  @override
  String get nothingToCheck => 'Aktuell sind keine Karten abfragebereit.';

  @override
  String get profileTitle => 'Profil & Einstellungen';

  @override
  String get languageSection => 'Sprache';

  @override
  String get languageEnglish => 'Englisch';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get statsSection => 'Übersicht';

  @override
  String get statTotalCards => 'Karten';

  @override
  String get statActiveCards => 'Aktiv';

  @override
  String get statArchivedCards => 'Archiviert';

  @override
  String get statTotalBalance => 'Gesamtguthaben';

  @override
  String get securitySection => 'Sicherheit';

  @override
  String get lockNow => 'Jetzt sperren';

  @override
  String get dataSection => 'Daten';

  @override
  String get aboutSection => 'Über die App';

  @override
  String get aboutBody =>
      'Karten werden lokal auf diesem Gerät gespeichert. Guthaben werden über die öffentliche Lidl-Guthabenabfrage ermittelt.';

  @override
  String get confirmClearTitle => 'Verbrauchte Karten löschen?';
}
