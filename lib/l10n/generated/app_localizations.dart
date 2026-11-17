import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift Card Wallet'**
  String get appTitle;

  /// No description provided for @unofficialLabel.
  ///
  /// In en, this message translates to:
  /// **'Unofficial Lidl wallet · Personal use only'**
  String get unofficialLabel;

  /// No description provided for @personalUseNotice.
  ///
  /// In en, this message translates to:
  /// **'Unofficial app for managing your own Lidl gift cards. Built independently for personal use only.'**
  String get personalUseNotice;

  /// No description provided for @walletTab.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletTab;

  /// No description provided for @archiveTab.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveTab;

  /// No description provided for @refreshAll.
  ///
  /// In en, this message translates to:
  /// **'Refresh all'**
  String get refreshAll;

  /// No description provided for @emptyWalletBody.
  ///
  /// In en, this message translates to:
  /// **'No active cards.\nScan a gift card to add it — cards that are empty or expired move to the archive automatically.'**
  String get emptyWalletBody;

  /// No description provided for @totalBalance.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Total balance (no active cards)} =1{Total balance (1 active card)} other{Total balance ({count} active cards)}}'**
  String totalBalance(int count);

  /// No description provided for @expiryUnknown.
  ///
  /// In en, this message translates to:
  /// **'Expiry date unknown'**
  String get expiryUnknown;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @expiresToday.
  ///
  /// In en, this message translates to:
  /// **'Expires today'**
  String get expiresToday;

  /// No description provided for @expiresTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Expires tomorrow'**
  String get expiresTomorrow;

  /// No description provided for @expiresInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}'**
  String expiresInDays(int days);

  /// No description provided for @manuallyEdited.
  ///
  /// In en, this message translates to:
  /// **'Manually edited'**
  String get manuallyEdited;

  /// No description provided for @statusAktiv.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusAktiv;

  /// No description provided for @statusEingeloest.
  ///
  /// In en, this message translates to:
  /// **'Redeemed'**
  String get statusEingeloest;

  /// No description provided for @statusAbgelaufen.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusAbgelaufen;

  /// No description provided for @statusUnbekannt.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get statusUnbekannt;

  /// No description provided for @captchaDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'A security check is blocking the query'**
  String get captchaDefaultTitle;

  /// No description provided for @captchaBannerAction.
  ///
  /// In en, this message translates to:
  /// **'Tap to complete the check on screen'**
  String get captchaBannerAction;

  /// No description provided for @cardTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift card'**
  String get cardTitle;

  /// No description provided for @cardDeleted.
  ///
  /// In en, this message translates to:
  /// **'This card was deleted.'**
  String get cardDeleted;

  /// No description provided for @refreshOnlineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Query online'**
  String get refreshOnlineTooltip;

  /// No description provided for @editTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit manually'**
  String get editTooltip;

  /// No description provided for @balanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balanceLabel;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @expiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiry date'**
  String get expiryLabel;

  /// No description provided for @lastUpdatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdatedLabel;

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'never (manual or not yet synced)'**
  String get neverSynced;

  /// No description provided for @markEmpty.
  ///
  /// In en, this message translates to:
  /// **'Mark as empty'**
  String get markEmpty;

  /// No description provided for @balanceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Balance updated'**
  String get balanceUpdated;

  /// No description provided for @queryFailed.
  ///
  /// In en, this message translates to:
  /// **'Query failed'**
  String get queryFailed;

  /// No description provided for @editTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit manually'**
  String get editTitle;

  /// No description provided for @balanceField.
  ///
  /// In en, this message translates to:
  /// **'Balance (CHF)'**
  String get balanceField;

  /// No description provided for @invalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Invalid amount'**
  String get invalidAmount;

  /// No description provided for @expiryField.
  ///
  /// In en, this message translates to:
  /// **'Expiry date (YYYY-MM-DD, empty = unknown)'**
  String get expiryField;

  /// No description provided for @invalidExpiryFormat.
  ///
  /// In en, this message translates to:
  /// **'Format: YYYY-MM-DD'**
  String get invalidExpiryFormat;

  /// No description provided for @nicknameField.
  ///
  /// In en, this message translates to:
  /// **'Note / nickname'**
  String get nicknameField;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @archiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'The archive is empty.\n\nCards with a 0.00 CHF balance or an expired validity date end up here — for reference only.'**
  String get archiveEmpty;

  /// No description provided for @deleteCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete card?'**
  String get deleteCardTitle;

  /// No description provided for @deleteCardBody.
  ///
  /// In en, this message translates to:
  /// **'The stored data of this card will be removed permanently.'**
  String get deleteCardBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan card'**
  String get scanTitle;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @cardDetected.
  ///
  /// In en, this message translates to:
  /// **'Card detected'**
  String get cardDetected;

  /// No description provided for @pinField.
  ///
  /// In en, this message translates to:
  /// **'PIN (4 digits)'**
  String get pinField;

  /// No description provided for @invalidPin.
  ///
  /// In en, this message translates to:
  /// **'Please enter 4 digits'**
  String get invalidPin;

  /// No description provided for @noteField.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteField;

  /// No description provided for @noteHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. birthday card'**
  String get noteHint;

  /// No description provided for @saveAndFetch.
  ///
  /// In en, this message translates to:
  /// **'Save & fetch balance'**
  String get saveAndFetch;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the gift card\'s barcode inside the frame'**
  String get scanHint;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable.\n{error}'**
  String cameraUnavailable(String error);

  /// No description provided for @manualEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual entry'**
  String get manualEntryTitle;

  /// No description provided for @cardNumberField.
  ///
  /// In en, this message translates to:
  /// **'Card number (18-20 digits)'**
  String get cardNumberField;

  /// No description provided for @invalidCardNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter 15-22 digits'**
  String get invalidCardNumber;

  /// No description provided for @saveAndQuery.
  ///
  /// In en, this message translates to:
  /// **'Save & query'**
  String get saveAndQuery;

  /// No description provided for @savedBalanceMsg.
  ///
  /// In en, this message translates to:
  /// **'Card saved — balance: {amount} CHF'**
  String savedBalanceMsg(String amount);

  /// No description provided for @savedFetchFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Card saved. Online query failed: {error}'**
  String savedFetchFailedMsg(String error);

  /// No description provided for @manualCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual check'**
  String get manualCheckTitle;

  /// No description provided for @manualCheckLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading page…'**
  String get manualCheckLoading;

  /// No description provided for @manualCheckReady.
  ///
  /// In en, this message translates to:
  /// **'Ready — fill in the query.'**
  String get manualCheckReady;

  /// No description provided for @manualCheckResponse.
  ///
  /// In en, this message translates to:
  /// **'Response: {message}'**
  String manualCheckResponse(String message);

  /// No description provided for @manualCheckHint.
  ///
  /// In en, this message translates to:
  /// **'Please enter the card number and PIN on the page and submit — the app picks up the result automatically.'**
  String get manualCheckHint;

  /// No description provided for @balanceSavedMsg.
  ///
  /// In en, this message translates to:
  /// **'Balance saved: {amount} CHF'**
  String balanceSavedMsg(String amount);

  /// No description provided for @noCardInEdit.
  ///
  /// In en, this message translates to:
  /// **'No card is currently being processed.'**
  String get noCardInEdit;

  /// No description provided for @errCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get errCancelled;

  /// No description provided for @errWebviewStart.
  ///
  /// In en, this message translates to:
  /// **'Could not start the WebView'**
  String get errWebviewStart;

  /// No description provided for @errLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the page'**
  String get errLoadFailed;

  /// No description provided for @errFormNotReady.
  ///
  /// In en, this message translates to:
  /// **'Form or security check not ready'**
  String get errFormNotReady;

  /// No description provided for @errFillFailed.
  ///
  /// In en, this message translates to:
  /// **'Filling the form failed'**
  String get errFillFailed;

  /// No description provided for @errNoResult.
  ///
  /// In en, this message translates to:
  /// **'No result received'**
  String get errNoResult;

  /// No description provided for @errQueryFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Could not query the balance'**
  String get errQueryFailedGeneric;

  /// No description provided for @errCardNotFound.
  ///
  /// In en, this message translates to:
  /// **'Card not found or PIN incorrect'**
  String get errCardNotFound;

  /// No description provided for @errApiError.
  ///
  /// In en, this message translates to:
  /// **'The card could not be queried'**
  String get errApiError;

  /// No description provided for @languageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Language / Sprache'**
  String get languageTooltip;

  /// No description provided for @lockSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Protect your wallet'**
  String get lockSetupTitle;

  /// No description provided for @lockSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a 4-digit PIN. Your card data is encrypted with it on the device.'**
  String get lockSetupSubtitle;

  /// No description provided for @lockSetupWarning.
  ///
  /// In en, this message translates to:
  /// **'If you forget this PIN, saved cards cannot be decrypted — the app data would have to be deleted and all cards re-added.'**
  String get lockSetupWarning;

  /// No description provided for @appPinField.
  ///
  /// In en, this message translates to:
  /// **'App PIN (4 digits)'**
  String get appPinField;

  /// No description provided for @confirmAppPinField.
  ///
  /// In en, this message translates to:
  /// **'Repeat app PIN'**
  String get confirmAppPinField;

  /// No description provided for @lockSetupButton.
  ///
  /// In en, this message translates to:
  /// **'Enable protection'**
  String get lockSetupButton;

  /// No description provided for @lockUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter app PIN'**
  String get lockUnlockTitle;

  /// No description provided for @lockUnlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockUnlockButton;

  /// No description provided for @wrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN.'**
  String get wrongPin;

  /// No description provided for @pinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The PINs do not match.'**
  String get pinMismatch;

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String tooManyAttempts(int seconds);

  /// No description provided for @changePinMenu.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePinMenu;

  /// No description provided for @changePinTitle.
  ///
  /// In en, this message translates to:
  /// **'Change app PIN'**
  String get changePinTitle;

  /// No description provided for @currentPinField.
  ///
  /// In en, this message translates to:
  /// **'Current PIN'**
  String get currentPinField;

  /// No description provided for @newPinField.
  ///
  /// In en, this message translates to:
  /// **'New PIN (4 digits)'**
  String get newPinField;

  /// No description provided for @confirmNewPinField.
  ///
  /// In en, this message translates to:
  /// **'Repeat new PIN'**
  String get confirmNewPinField;

  /// No description provided for @pinChangedMsg.
  ///
  /// In en, this message translates to:
  /// **'App PIN changed.'**
  String get pinChangedMsg;

  /// No description provided for @cardsTab.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get cardsTab;

  /// No description provided for @scanTab.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanTab;

  /// No description provided for @balanceCheckTab.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balanceCheckTab;

  /// No description provided for @profileTab.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTab;

  /// No description provided for @heroTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'TOTAL BALANCE'**
  String get heroTotalLabel;

  /// No description provided for @activeCardsChip.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 active card} other{{count} active cards}}'**
  String activeCardsChip(int count);

  /// No description provided for @scanCardCta.
  ///
  /// In en, this message translates to:
  /// **'Scan Card'**
  String get scanCardCta;

  /// No description provided for @enterCodeCta.
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get enterCodeCta;

  /// No description provided for @filterAllActive.
  ///
  /// In en, this message translates to:
  /// **'All Active'**
  String get filterAllActive;

  /// No description provided for @filterExpiringSoon.
  ///
  /// In en, this message translates to:
  /// **'Expiring Soon'**
  String get filterExpiringSoon;

  /// No description provided for @filterFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get filterFavorites;

  /// No description provided for @showBarcode.
  ///
  /// In en, this message translates to:
  /// **'Show Barcode'**
  String get showBarcode;

  /// No description provided for @viewArchivedRow.
  ///
  /// In en, this message translates to:
  /// **'Looking for old cards? View archived cards ({count})'**
  String viewArchivedRow(int count);

  /// No description provided for @urgentBadge.
  ///
  /// In en, this message translates to:
  /// **'URGENT'**
  String get urgentBadge;

  /// No description provided for @urgentStripLine.
  ///
  /// In en, this message translates to:
  /// **'{countdown} ({date})'**
  String urgentStripLine(String countdown, String date);

  /// No description provided for @validUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String validUntil(String date);

  /// No description provided for @cardEndingIn.
  ///
  /// In en, this message translates to:
  /// **'Card ending in •••• {last4}'**
  String cardEndingIn(String last4);

  /// No description provided for @ofInitialAmount.
  ///
  /// In en, this message translates to:
  /// **'of {amount}'**
  String ofInitialAmount(String amount);

  /// No description provided for @scanModeBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get scanModeBarcode;

  /// No description provided for @scanModeCardPin.
  ///
  /// In en, this message translates to:
  /// **'Card & PIN'**
  String get scanModeCardPin;

  /// No description provided for @scanModeFile.
  ///
  /// In en, this message translates to:
  /// **'Image/PDF'**
  String get scanModeFile;

  /// No description provided for @pdfImportNoData.
  ///
  /// In en, this message translates to:
  /// **'No card data found in this PDF. Please enter the codes manually.'**
  String get pdfImportNoData;

  /// No description provided for @pdfImportFailed.
  ///
  /// In en, this message translates to:
  /// **'This file could not be read'**
  String get pdfImportFailed;

  /// No description provided for @pdfAmountDetected.
  ///
  /// In en, this message translates to:
  /// **'Amount detected: {amount} — verified by the online check'**
  String pdfAmountDetected(String amount);

  /// No description provided for @whereToFindCodes.
  ///
  /// In en, this message translates to:
  /// **'Where to find card codes'**
  String get whereToFindCodes;

  /// No description provided for @backOfPhysicalCard.
  ///
  /// In en, this message translates to:
  /// **'Back of physical card'**
  String get backOfPhysicalCard;

  /// No description provided for @digitNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'{digits}-digit number'**
  String digitNumberLabel(int digits);

  /// No description provided for @scratchPinLabel.
  ///
  /// In en, this message translates to:
  /// **'Scratch PIN'**
  String get scratchPinLabel;

  /// No description provided for @quickPaste.
  ///
  /// In en, this message translates to:
  /// **'Quick paste'**
  String get quickPaste;

  /// No description provided for @pinScratchHint.
  ///
  /// In en, this message translates to:
  /// **'Scratch gently to reveal the 4-digit PIN'**
  String get pinScratchHint;

  /// No description provided for @nicknameOptional.
  ///
  /// In en, this message translates to:
  /// **'Card nickname'**
  String get nicknameOptional;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Helps recognize this card at checkout'**
  String get nicknameHint;

  /// No description provided for @checkingBalance.
  ///
  /// In en, this message translates to:
  /// **'Querying Lidl balance service…'**
  String get checkingBalance;

  /// No description provided for @cardVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Card verified successfully'**
  String get cardVerifiedTitle;

  /// No description provided for @cardVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Valid Lidl card detected. The balance will be saved to your wallet.'**
  String get cardVerifiedBody;

  /// No description provided for @checkBalanceAndSave.
  ///
  /// In en, this message translates to:
  /// **'Check Balance & Save Card'**
  String get checkBalanceAndSave;

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get saveAnyway;

  /// No description provided for @openManualCheck.
  ///
  /// In en, this message translates to:
  /// **'Open balance page — solve the captcha'**
  String get openManualCheck;

  /// No description provided for @cardAlreadyImported.
  ///
  /// In en, this message translates to:
  /// **'This card is already in your wallet ({name})'**
  String cardAlreadyImported(String name);

  /// No description provided for @verificationFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Balance check failed'**
  String get verificationFailedTitle;

  /// No description provided for @scanBarcodeInstead.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode instead'**
  String get scanBarcodeInstead;

  /// No description provided for @giftCardLabel.
  ///
  /// In en, this message translates to:
  /// **'GIFT CARD'**
  String get giftCardLabel;

  /// No description provided for @currentBalance.
  ///
  /// In en, this message translates to:
  /// **'Current balance'**
  String get currentBalance;

  /// No description provided for @securityPin.
  ///
  /// In en, this message translates to:
  /// **'Security PIN'**
  String get securityPin;

  /// No description provided for @maxBrightnessNote.
  ///
  /// In en, this message translates to:
  /// **'Max brightness enabled for scanning'**
  String get maxBrightnessNote;

  /// No description provided for @barcodeModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcodeModeLabel;

  /// No description provided for @qrModeLabel.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrModeLabel;

  /// No description provided for @tapToExpand.
  ///
  /// In en, this message translates to:
  /// **'Tap to expand full screen for cashier'**
  String get tapToExpand;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @activityActivation.
  ///
  /// In en, this message translates to:
  /// **'Card activation'**
  String get activityActivation;

  /// No description provided for @activityInitialLoad.
  ///
  /// In en, this message translates to:
  /// **'Initial load'**
  String get activityInitialLoad;

  /// No description provided for @activitySpend.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get activitySpend;

  /// No description provided for @activityReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get activityReload;

  /// No description provided for @activityEdit.
  ///
  /// In en, this message translates to:
  /// **'Manual correction'**
  String get activityEdit;

  /// No description provided for @archiveThisCard.
  ///
  /// In en, this message translates to:
  /// **'Archive this card'**
  String get archiveThisCard;

  /// No description provided for @archivedFootnote.
  ///
  /// In en, this message translates to:
  /// **'Archived cards remain accessible in your archive.'**
  String get archivedFootnote;

  /// No description provided for @restoreToWallet.
  ///
  /// In en, this message translates to:
  /// **'Restore to wallet'**
  String get restoreToWallet;

  /// No description provided for @favoriteAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get favoriteAdd;

  /// No description provided for @favoriteRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get favoriteRemove;

  /// No description provided for @expiryBannerLine.
  ///
  /// In en, this message translates to:
  /// **'Expiry date: {date}'**
  String expiryBannerLine(String date);

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day remaining!} other{{days} days remaining!}}'**
  String daysRemaining(int days);

  /// No description provided for @useInStore.
  ///
  /// In en, this message translates to:
  /// **'Use in any Lidl store or online at lidl.ch'**
  String get useInStore;

  /// No description provided for @fullScreenBarcode.
  ///
  /// In en, this message translates to:
  /// **'Checkout barcode'**
  String get fullScreenBarcode;

  /// No description provided for @cardArchivedMsg.
  ///
  /// In en, this message translates to:
  /// **'Card archived'**
  String get cardArchivedMsg;

  /// No description provided for @cardRestoredMsg.
  ///
  /// In en, this message translates to:
  /// **'Card restored to wallet'**
  String get cardRestoredMsg;

  /// No description provided for @revealPin.
  ///
  /// In en, this message translates to:
  /// **'Show PIN'**
  String get revealPin;

  /// No description provided for @hidePin.
  ///
  /// In en, this message translates to:
  /// **'Hide PIN'**
  String get hidePin;

  /// No description provided for @archiveSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by year, name, or last digits…'**
  String get archiveSearchHint;

  /// No description provided for @spentArchiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Spent archive'**
  String get spentArchiveLabel;

  /// No description provided for @totalRedeemed.
  ///
  /// In en, this message translates to:
  /// **'Total redeemed'**
  String get totalRedeemed;

  /// No description provided for @cardsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Cards count'**
  String get cardsCountLabel;

  /// No description provided for @storedVouchers.
  ///
  /// In en, this message translates to:
  /// **'Stored vouchers'**
  String get storedVouchers;

  /// No description provided for @filterAllArchived.
  ///
  /// In en, this message translates to:
  /// **'All archived'**
  String get filterAllArchived;

  /// No description provided for @filterFullySpent.
  ///
  /// In en, this message translates to:
  /// **'Fully spent'**
  String get filterFullySpent;

  /// No description provided for @filterExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get filterExpired;

  /// No description provided for @fullyRedeemed.
  ///
  /// In en, this message translates to:
  /// **'Fully redeemed'**
  String get fullyRedeemed;

  /// No description provided for @unspentAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} unspent'**
  String unspentAmount(String amount);

  /// No description provided for @expiredOn.
  ///
  /// In en, this message translates to:
  /// **'Expired on {date}'**
  String expiredOn(String date);

  /// No description provided for @spentOn.
  ///
  /// In en, this message translates to:
  /// **'Spent on {date}'**
  String spentOn(String date);

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @clearSpentHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear spent cards history'**
  String get clearSpentHistory;

  /// No description provided for @clearSpentHistoryBody.
  ///
  /// In en, this message translates to:
  /// **'This will remove zero-balance records permanently.'**
  String get clearSpentHistoryBody;

  /// No description provided for @clearedHistoryMsg.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 card removed} other{{count} cards removed}}'**
  String clearedHistoryMsg(int count);

  /// No description provided for @balanceCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Balance check'**
  String get balanceCheckTitle;

  /// No description provided for @balanceCheckIntro.
  ///
  /// In en, this message translates to:
  /// **'Open Lidl’s balance page for any card when a captcha blocks the automatic check.'**
  String get balanceCheckIntro;

  /// No description provided for @pickCardToCheck.
  ///
  /// In en, this message translates to:
  /// **'Pick a card to check'**
  String get pickCardToCheck;

  /// No description provided for @openBalancePage.
  ///
  /// In en, this message translates to:
  /// **'Open balance page'**
  String get openBalancePage;

  /// No description provided for @refreshQueueStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking {completed}/{total}…'**
  String refreshQueueStatus(int completed, int total);

  /// No description provided for @currentlyChecking.
  ///
  /// In en, this message translates to:
  /// **'Currently checking'**
  String get currentlyChecking;

  /// No description provided for @nothingToCheck.
  ///
  /// In en, this message translates to:
  /// **'No cards can be checked right now.'**
  String get nothingToCheck;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile & settings'**
  String get profileTitle;

  /// No description provided for @languageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSection;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @statsSection.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get statsSection;

  /// No description provided for @statTotalCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get statTotalCards;

  /// No description provided for @statActiveCards.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statActiveCards;

  /// No description provided for @statArchivedCards.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get statArchivedCards;

  /// No description provided for @statTotalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total balance'**
  String get statTotalBalance;

  /// No description provided for @securitySection.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySection;

  /// No description provided for @lockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get lockNow;

  /// No description provided for @dataSection.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get dataSection;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'Cards are stored locally on this device. Balances are queried from Lidl\'s public balance-check page.'**
  String get aboutBody;

  /// No description provided for @confirmClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear spent cards history?'**
  String get confirmClearTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
