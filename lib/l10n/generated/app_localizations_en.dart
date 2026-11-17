// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Gift Card Wallet';

  @override
  String get unofficialLabel => 'Unofficial Lidl wallet · Personal use only';

  @override
  String get personalUseNotice =>
      'Unofficial app for managing your own Lidl gift cards. Built independently for personal use only.';

  @override
  String get walletTab => 'Wallet';

  @override
  String get archiveTab => 'Archive';

  @override
  String get refreshAll => 'Refresh all';

  @override
  String get emptyWalletBody =>
      'No active cards.\nScan a gift card to add it — cards that are empty or expired move to the archive automatically.';

  @override
  String totalBalance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Total balance ($count active cards)',
      one: 'Total balance (1 active card)',
      zero: 'Total balance (no active cards)',
    );
    return '$_temp0';
  }

  @override
  String get expiryUnknown => 'Expiry date unknown';

  @override
  String get expired => 'Expired';

  @override
  String get expiresToday => 'Expires today';

  @override
  String get expiresTomorrow => 'Expires tomorrow';

  @override
  String expiresInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expires in $days days',
      one: 'Expires tomorrow',
      zero: 'Expires today',
    );
    return '$_temp0';
  }

  @override
  String get manuallyEdited => 'Manually edited';

  @override
  String get statusAktiv => 'Active';

  @override
  String get statusEingeloest => 'Redeemed';

  @override
  String get statusAbgelaufen => 'Expired';

  @override
  String get statusUnbekannt => 'Unknown';

  @override
  String get captchaDefaultTitle => 'A security check is blocking the query';

  @override
  String get captchaBannerAction => 'Tap to complete the check on screen';

  @override
  String get cardTitle => 'Gift card';

  @override
  String get cardDeleted => 'This card was deleted.';

  @override
  String get refreshOnlineTooltip => 'Query online';

  @override
  String get editTooltip => 'Edit manually';

  @override
  String get balanceLabel => 'Balance';

  @override
  String get statusLabel => 'Status';

  @override
  String get expiryLabel => 'Expiry date';

  @override
  String get lastUpdatedLabel => 'Last updated';

  @override
  String get neverSynced => 'never (manual or not yet synced)';

  @override
  String get markEmpty => 'Mark as empty';

  @override
  String get balanceUpdated => 'Balance updated';

  @override
  String get queryFailed => 'Query failed';

  @override
  String get editTitle => 'Edit manually';

  @override
  String get balanceField => 'Balance (CHF)';

  @override
  String get invalidAmount => 'Invalid amount';

  @override
  String get expiryField => 'Expiry date (YYYY-MM-DD, empty = unknown)';

  @override
  String get invalidExpiryFormat => 'Format: YYYY-MM-DD';

  @override
  String get nicknameField => 'Note / nickname';

  @override
  String get save => 'Save';

  @override
  String get archiveEmpty =>
      'The archive is empty.\n\nCards with a 0.00 CHF balance or an expired validity date end up here — for reference only.';

  @override
  String get deleteCardTitle => 'Delete card?';

  @override
  String get deleteCardBody =>
      'The stored data of this card will be removed permanently.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get scanTitle => 'Scan card';

  @override
  String get manual => 'Manual';

  @override
  String get cardDetected => 'Card detected';

  @override
  String get pinField => 'PIN (4 digits)';

  @override
  String get invalidPin => 'Please enter 4 digits';

  @override
  String get noteField => 'Note (optional)';

  @override
  String get noteHint => 'e.g. birthday card';

  @override
  String get saveAndFetch => 'Save & fetch balance';

  @override
  String get scanHint => 'Hold the gift card\'s barcode inside the frame';

  @override
  String cameraUnavailable(String error) {
    return 'Camera unavailable.\n$error';
  }

  @override
  String get manualEntryTitle => 'Manual entry';

  @override
  String get cardNumberField => 'Card number (18-20 digits)';

  @override
  String get invalidCardNumber => 'Please enter 15-22 digits';

  @override
  String get saveAndQuery => 'Save & query';

  @override
  String savedBalanceMsg(String amount) {
    return 'Card saved — balance: $amount CHF';
  }

  @override
  String savedFetchFailedMsg(String error) {
    return 'Card saved. Online query failed: $error';
  }

  @override
  String get manualCheckTitle => 'Manual check';

  @override
  String get manualCheckLoading => 'Loading page…';

  @override
  String get manualCheckReady => 'Ready — fill in the query.';

  @override
  String manualCheckResponse(String message) {
    return 'Response: $message';
  }

  @override
  String get manualCheckHint =>
      'Please enter the card number and PIN on the page and submit — the app picks up the result automatically.';

  @override
  String balanceSavedMsg(String amount) {
    return 'Balance saved: $amount CHF';
  }

  @override
  String get noCardInEdit => 'No card is currently being processed.';

  @override
  String get errCancelled => 'Cancelled';

  @override
  String get errWebviewStart => 'Could not start the WebView';

  @override
  String get errLoadFailed => 'Could not load the page';

  @override
  String get errFormNotReady => 'Form or security check not ready';

  @override
  String get errFillFailed => 'Filling the form failed';

  @override
  String get errNoResult => 'No result received';

  @override
  String get errQueryFailedGeneric => 'Could not query the balance';

  @override
  String get errCardNotFound => 'Card not found or PIN incorrect';

  @override
  String get errApiError => 'The card could not be queried';

  @override
  String get languageTooltip => 'Language / Sprache';

  @override
  String get lockSetupTitle => 'Protect your wallet';

  @override
  String get lockSetupSubtitle =>
      'Choose a 4-digit PIN. Your card data is encrypted with it on the device.';

  @override
  String get lockSetupWarning =>
      'If you forget this PIN, saved cards cannot be decrypted — the app data would have to be deleted and all cards re-added.';

  @override
  String get appPinField => 'App PIN (4 digits)';

  @override
  String get confirmAppPinField => 'Repeat app PIN';

  @override
  String get lockSetupButton => 'Enable protection';

  @override
  String get lockUnlockTitle => 'Enter app PIN';

  @override
  String get lockUnlockButton => 'Unlock';

  @override
  String get wrongPin => 'Wrong PIN.';

  @override
  String get pinMismatch => 'The PINs do not match.';

  @override
  String tooManyAttempts(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get changePinMenu => 'Change PIN';

  @override
  String get changePinTitle => 'Change app PIN';

  @override
  String get currentPinField => 'Current PIN';

  @override
  String get newPinField => 'New PIN (4 digits)';

  @override
  String get confirmNewPinField => 'Repeat new PIN';

  @override
  String get pinChangedMsg => 'App PIN changed.';

  @override
  String get cardsTab => 'Cards';

  @override
  String get scanTab => 'Scan';

  @override
  String get balanceCheckTab => 'Balance';

  @override
  String get profileTab => 'Profile';

  @override
  String get heroTotalLabel => 'TOTAL BALANCE';

  @override
  String activeCardsChip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active cards',
      one: '1 active card',
    );
    return '$_temp0';
  }

  @override
  String get scanCardCta => 'Scan Card';

  @override
  String get enterCodeCta => 'Enter Code';

  @override
  String get filterAllActive => 'All Active';

  @override
  String get filterExpiringSoon => 'Expiring Soon';

  @override
  String get filterFavorites => 'Favorites';

  @override
  String get showBarcode => 'Show Barcode';

  @override
  String viewArchivedRow(int count) {
    return 'Looking for old cards? View archived cards ($count)';
  }

  @override
  String get urgentBadge => 'URGENT';

  @override
  String urgentStripLine(String countdown, String date) {
    return '$countdown ($date)';
  }

  @override
  String validUntil(String date) {
    return 'Valid until $date';
  }

  @override
  String cardEndingIn(String last4) {
    return 'Card ending in •••• $last4';
  }

  @override
  String ofInitialAmount(String amount) {
    return 'of $amount';
  }

  @override
  String get scanModeBarcode => 'Barcode';

  @override
  String get scanModeCardPin => 'Card & PIN';

  @override
  String get scanModeFile => 'Image/PDF';

  @override
  String get pdfImportNoData =>
      'No card data found in this PDF. Please enter the codes manually.';

  @override
  String get pdfImportFailed => 'This file could not be read';

  @override
  String pdfAmountDetected(String amount) {
    return 'Amount detected: $amount — verified by the online check';
  }

  @override
  String get whereToFindCodes => 'Where to find card codes';

  @override
  String get backOfPhysicalCard => 'Back of physical card';

  @override
  String digitNumberLabel(int digits) {
    return '$digits-digit number';
  }

  @override
  String get scratchPinLabel => 'Scratch PIN';

  @override
  String get quickPaste => 'Quick paste';

  @override
  String get pinScratchHint => 'Scratch gently to reveal the 4-digit PIN';

  @override
  String get nicknameOptional => 'Card nickname';

  @override
  String get nicknameHint => 'Helps recognize this card at checkout';

  @override
  String get checkingBalance => 'Querying Lidl balance service…';

  @override
  String get cardVerifiedTitle => 'Card verified successfully';

  @override
  String get cardVerifiedBody =>
      'Valid Lidl card detected. The balance will be saved to your wallet.';

  @override
  String get checkBalanceAndSave => 'Check Balance & Save Card';

  @override
  String get saveAnyway => 'Save anyway';

  @override
  String get openManualCheck => 'Open balance page — solve the captcha';

  @override
  String cardAlreadyImported(String name) {
    return 'This card is already in your wallet ($name)';
  }

  @override
  String get verificationFailedTitle => 'Balance check failed';

  @override
  String get scanBarcodeInstead => 'Scan barcode instead';

  @override
  String get giftCardLabel => 'GIFT CARD';

  @override
  String get currentBalance => 'Current balance';

  @override
  String get securityPin => 'Security PIN';

  @override
  String get maxBrightnessNote => 'Max brightness enabled for scanning';

  @override
  String get barcodeModeLabel => 'Barcode';

  @override
  String get qrModeLabel => 'QR Code';

  @override
  String get tapToExpand => 'Tap to expand full screen for cashier';

  @override
  String get recentActivity => 'Recent activity';

  @override
  String get viewAll => 'View all';

  @override
  String get activityActivation => 'Card activation';

  @override
  String get activityInitialLoad => 'Initial load';

  @override
  String get activitySpend => 'Purchase';

  @override
  String get activityReload => 'Reload';

  @override
  String get activityEdit => 'Manual correction';

  @override
  String get archiveThisCard => 'Archive this card';

  @override
  String get archivedFootnote =>
      'Archived cards remain accessible in your archive.';

  @override
  String get restoreToWallet => 'Restore to wallet';

  @override
  String get favoriteAdd => 'Add to favorites';

  @override
  String get favoriteRemove => 'Remove from favorites';

  @override
  String expiryBannerLine(String date) {
    return 'Expiry date: $date';
  }

  @override
  String daysRemaining(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days remaining!',
      one: '1 day remaining!',
    );
    return '$_temp0';
  }

  @override
  String get useInStore => 'Use in any Lidl store or online at lidl.ch';

  @override
  String get fullScreenBarcode => 'Checkout barcode';

  @override
  String get cardArchivedMsg => 'Card archived';

  @override
  String get cardRestoredMsg => 'Card restored to wallet';

  @override
  String get revealPin => 'Show PIN';

  @override
  String get hidePin => 'Hide PIN';

  @override
  String get archiveSearchHint => 'Filter by year, name, or last digits…';

  @override
  String get spentArchiveLabel => 'Spent archive';

  @override
  String get totalRedeemed => 'Total redeemed';

  @override
  String get cardsCountLabel => 'Cards count';

  @override
  String get storedVouchers => 'Stored vouchers';

  @override
  String get filterAllArchived => 'All archived';

  @override
  String get filterFullySpent => 'Fully spent';

  @override
  String get filterExpired => 'Expired';

  @override
  String get fullyRedeemed => 'Fully redeemed';

  @override
  String unspentAmount(String amount) {
    return '$amount unspent';
  }

  @override
  String expiredOn(String date) {
    return 'Expired on $date';
  }

  @override
  String spentOn(String date) {
    return 'Spent on $date';
  }

  @override
  String get viewDetails => 'View details';

  @override
  String get clearSpentHistory => 'Clear spent cards history';

  @override
  String get clearSpentHistoryBody =>
      'This will remove zero-balance records permanently.';

  @override
  String clearedHistoryMsg(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards removed',
      one: '1 card removed',
    );
    return '$_temp0';
  }

  @override
  String get balanceCheckTitle => 'Balance check';

  @override
  String get balanceCheckIntro =>
      'Open Lidl’s balance page for any card when a captcha blocks the automatic check.';

  @override
  String get pickCardToCheck => 'Pick a card to check';

  @override
  String get openBalancePage => 'Open balance page';

  @override
  String refreshQueueStatus(int completed, int total) {
    return 'Checking $completed/$total…';
  }

  @override
  String get currentlyChecking => 'Currently checking';

  @override
  String get nothingToCheck => 'No cards can be checked right now.';

  @override
  String get profileTitle => 'Profile & settings';

  @override
  String get languageSection => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'German';

  @override
  String get statsSection => 'Overview';

  @override
  String get statTotalCards => 'Cards';

  @override
  String get statActiveCards => 'Active';

  @override
  String get statArchivedCards => 'Archived';

  @override
  String get statTotalBalance => 'Total balance';

  @override
  String get securitySection => 'Security';

  @override
  String get lockNow => 'Lock now';

  @override
  String get dataSection => 'Data';

  @override
  String get aboutSection => 'About';

  @override
  String get aboutBody =>
      'Cards are stored locally on this device. Balances are queried from Lidl\'s public balance-check page.';

  @override
  String get confirmClearTitle => 'Clear spent cards history?';
}
