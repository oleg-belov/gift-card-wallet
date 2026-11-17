import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/card_transaction.dart';
import '../models/gift_card.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_text.dart';
import '../services/balance_service.dart';
import '../services/voucher_codes.dart';
import '../services/voucher_pdf.dart';
import '../widgets/lidl_badge.dart';
import 'manual_check_screen.dart';

/// Scan tab: dark camera view with a yellow corner-bracket viewfinder,
/// mode chips (camera / manual entry / gallery) and the card-entry sheet.
class ScanTab extends ConsumerStatefulWidget {
  const ScanTab({super.key, this.active = true, this.onCardSaved});

  /// Whether this tab is currently visible; the camera only runs then.
  final bool active;

  /// Called after a card was saved so the shell can navigate (e.g. back to
  /// the cards tab).
  final void Function(bool verified)? onCardSaved;

  @override
  ConsumerState<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends ConsumerState<ScanTab>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _cameraController;
  bool _handled = false;
  int _mode = 0; // 0 = barcode camera, 1 = manual entry, 2 = gallery

  /// Created lazily on first build of the visible tab; a `late final` field
  /// would be created during dispose() when the tab was never shown, which
  /// looks up TickerMode on a deactivated element.
  AnimationController? _laser;

  AnimationController _ensureLaser() {
    return _laser ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _ensureCamera();
    // An import picked while the app was locked (system file picker pauses
    // the activity) is replayed here, right after the next unlock. Both the
    // provider write and the sheet must run post-frame — initState is not
    // allowed to modify providers.
    final pending = ref.read(pendingCardImportProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingCardImportProvider.notifier).state = null;
        if (kDebugMode) {
          debugPrint('E2E: replay sheet opened '
              'card=…${pending.cardNumber.substring(pending.cardNumber.length - 4)}');
        }
        _openEntrySheet(
          presetNumber: pending.cardNumber,
          presetPin: pending.pin,
          presetBarcodeValue: pending.barcodeValue,
          detectedValue: pending.detectedValue,
          barcodeFormat: pending.barcodeFormat,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant ScanTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _ensureCamera();
      _handled = false;
    } else if (!widget.active && old.active) {
      // Drop the one-shot flag so the next visit can scan again, and pause
      // the camera while hidden.
      _handled = false;
      _cameraController?.stop();
    }
  }

  void _ensureCamera() {
    final controller = _cameraController;
    if (controller == null) {
      _cameraController = MobileScannerController();
    } else {
      controller.start();
    }
  }

  @override
  void dispose() {
    _laser?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      // Real voucher barcodes are GS1-128 element strings (AI 01 GTIN +
      // AI 90 card number); bare card numbers are long digit strings per
      // the Lidl form validation. Anything else is ignored so the user
      // re-aims.
      final code = parseScannedCode(value);
      if (code == null) continue;

      setState(() => _handled = true);
      _openEntrySheet(
        presetNumber: code.cardNumber,
        presetBarcodeValue: code.barcodeValue,
        barcodeFormat: barcode.format.name,
      );
      return;
    }
  }

  Future<void> _pickImportFile() async {
    final l10n = AppLocalizations.of(context);
    // The system picker pauses the app → the wallet locks and this tab
    // unmounts. Capture the stashing notifier before any await so the
    // import result survives the lock (replayed on the next unlock).
    final pendingNotifier = ref.read(pendingCardImportProvider.notifier);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      final files = result?.files;
      if (files == null || files.isEmpty) return;
      final file = files.first;

      final extension = file.extension?.toLowerCase();
      if (extension == 'pdf') {
        await _importVoucherPdf(file, pendingNotifier, l10n);
        return;
      }

      // Images go through the same barcode detection as the camera.
      final path = file.path;
      if (path == null) {
        if (mounted) _showMessage(l10n.errNoResult);
        return;
      }
      final capture = await _cameraController?.analyzeImage(path);
      if (capture == null) {
        if (mounted) _showMessage(l10n.errNoResult);
        return;
      }
      if (mounted) {
        _onDetect(capture);
        return;
      }
      // Locked while analyzing: stash the first decodable code.
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue;
        if (value == null || value.isEmpty) continue;
        final code = parseScannedCode(value);
        if (code == null) continue;
        pendingNotifier.state = PendingCardImport(
          cardNumber: code.cardNumber,
          barcodeValue: code.barcodeValue,
          barcodeFormat: barcode.format.name,
        );
        return;
      }
      pendingNotifier.state = null;
    } catch (e) {
      if (mounted) _showMessage(l10n.errNoResult);
    }
  }

  /// Decodes a barcode from one extracted PDF image: writes it to a temp
  /// file and runs the platform barcode detector (the same ML pipeline the
  /// camera uses). Returns null when nothing decodable is found.
  Future<ScannedCode?> _decodeImageBarcode(VoucherPdfImage image) async {
    File? temp;
    var decoded = false;
    try {
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/lidl_voucher_barcode.${image.extension}');
      await temp.writeAsBytes(image.bytes, flush: true);
      final controller = _cameraController ?? MobileScannerController();
      final capture = await controller.analyzeImage(temp.path);
      if (capture == null) {
        if (kDebugMode) debugPrint('E2E: pdf barcode analyze=null');
        return null;
      }
      if (kDebugMode) {
        debugPrint('E2E: pdf barcode analyze: '
            '${capture.barcodes.length} barcode(s)');
      }
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue;
        if (kDebugMode) {
          debugPrint('E2E: pdf barcode raw=${value ?? "<null>"}');
        }
        if (value == null || value.isEmpty) continue;
        final code = parseScannedCode(value);
        if (code != null) {
          decoded = true;
          return code;
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('E2E: pdf barcode analyze error=$e');
      return null;
    } finally {
      if (!decoded) {
        // Keep the file around for on-device inspection in debug builds.
        if (!kDebugMode) {
          try {
            if (temp != null && await temp.exists()) await temp.delete();
          } catch (_) {}
        }
      } else {
        try {
          if (temp != null && await temp.exists()) await temp.delete();
        } catch (_) {}
      }
    }
  }

  /// Reads the voucher fields (card number, PIN, face value, serial) out of
  /// the PDF's text layer and opens the entry sheet prefilled.
  Future<void> _importVoucherPdf(
    PlatformFile file,
    StateController<PendingCardImport?> pendingNotifier,
    AppLocalizations l10n,
  ) async {
    try {
      final bytes = file.bytes ?? (file.path != null ? File(file.path!).readAsBytesSync() : null);
      if (bytes == null) {
        if (mounted) _showMessage(l10n.pdfImportFailed);
        return;
      }
      final data = VoucherPdfExtractor.extract(bytes);

      // The voucher embeds its barcode as a strip image — decode it for the
      // GS1 checkout payload (and as a card-number fallback for PDFs with
      // an empty text layer).
      ScannedCode? scanned;
      for (final image in data.images) {
        scanned = await _decodeImageBarcode(image);
        if (scanned != null) break;
      }
      if (kDebugMode) {
        final payload = scanned?.barcodeValue ?? scanned?.cardNumber;
        debugPrint('E2E: pdf barcode '
            '${payload == null ? "not decoded" : "decoded …${payload.substring(payload.length - 6)}"}');
      }

      final cardNumber = data.cardNumber ?? scanned?.cardNumber;
      if (cardNumber == null) {
        if (mounted) _showMessage(l10n.pdfImportNoData);
        return;
      }
      if (kDebugMode) {
        debugPrint('E2E: pdf extracted '
            'card=…${cardNumber.substring(cardNumber.length - 4)} '
            'pin=${data.pin != null} value=${data.value}');
      }
      final pending = PendingCardImport(
        cardNumber: cardNumber,
        pin: data.pin,
        detectedValue: data.value,
        barcodeValue: scanned?.barcodeValue,
        barcodeFormat: 'code128',
      );
      if (mounted) {
        _openEntrySheet(
          presetNumber: pending.cardNumber,
          presetPin: pending.pin,
          detectedValue: pending.detectedValue,
          barcodeFormat: pending.barcodeFormat,
        );
      } else {
        // The picker paused the app and the gate locked — replay after the
        // next unlock instead of dropping the picked voucher.
        pendingNotifier.state = pending;
      }
    } catch (e) {
      if (mounted) _showMessage(l10n.pdfImportFailed);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openEntrySheet({
    String? presetNumber,
    String? presetPin,
    String? presetBarcodeValue,
    double? detectedValue,
    String? barcodeFormat,
  }) async {
    final (bool saved, bool verified, String? message, int? manualCheckCardId) =
        await showModalBottomSheet<(bool, bool, String?, int?)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CardEntrySheet(
        presetNumber: presetNumber,
        presetPin: presetPin,
        presetBarcodeValue: presetBarcodeValue,
        detectedValue: detectedValue,
        barcodeFormat: barcodeFormat,
      ),
    ) ?? (false, false, null, null);

    if (!mounted) return;
    setState(() => _handled = false);
    if (saved) {
      final l10n = AppLocalizations.of(context);
      _showMessage(verified
          ? l10n.savedBalanceMsg(message ?? '')
          : l10n.savedFetchFailedMsg(message ?? l10n.errQueryFailedGeneric));
      widget.onCardSaved?.call(verified);
    }
    if (manualCheckCardId != null) {
      // The user chose to solve the captcha by hand: the card is saved,
      // the balance page opens prefilled and the answer flows back in.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ManualCheckScreen(cardId: manualCheckCardId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1520),
      body: SafeArea(
        child: Column(
          children: [
            // Mode chips on a dark rail.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: AppRadius.pill,
                ),
                child: Row(
                  children: [
                    _ModeChip(
                      label: l10n.scanModeBarcode,
                      icon: Icons.qr_code_scanner,
                      selected: _mode == 0,
                      onTap: () => setState(() => _mode = 0),
                    ),
                    _ModeChip(
                      label: l10n.scanModeCardPin,
                      icon: Icons.keyboard_outlined,
                      selected: _mode == 1,
                      onTap: () {
                        setState(() => _mode = 1);
                        _openEntrySheet();
                      },
                    ),
                    _ModeChip(
                      label: l10n.scanModeFile,
                      icon: Icons.picture_as_pdf_outlined,
                      selected: _mode == 2,
                      onTap: () {
                        setState(() => _mode = 2);
                        _pickImportFile();
                      },
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.active && _cameraController != null)
                    MobileScanner(
                      controller: _cameraController,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => _CameraErrorView(
                        onManual: () => _openEntrySheet(),
                        error: error,
                      ),
                    )
                  else
                    ColoredBox(
                      color: const Color(0xFF0D1520),
                      child: Center(
                        child: Icon(
                          Icons.qr_code_scanner,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  if (widget.active)
                    _ViewfinderOverlay(laser: _ensureLaser()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.scanHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yellow corner brackets, dashed frame and the animated laser line.
class _ViewfinderOverlay extends StatelessWidget {
  const _ViewfinderOverlay({required this.laser});

  final Animation<double> laser;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 300,
            height: 190,
            child: Stack(
              children: [
                // Dashed inner guide.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: CustomPaint(
                      painter: _DashedRectPainter(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
                // Corner brackets.
                ..._corners(),
                // Laser line.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedBuilder(
                        animation: laser,
                        builder: (context, _) => Align(
                          alignment: Alignment(0, laser.value * 2 - 1),
                          child: Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                AppColors.yellow.withValues(alpha: 0),
                                AppColors.yellow,
                                AppColors.yellow.withValues(alpha: 0),
                              ]),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.yellow.withValues(alpha: 0.6),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const size = 28.0;
    const thickness = 3.5;
    BorderSide side = const BorderSide(color: AppColors.yellow, width: thickness);
    return [
      Positioned(
        top: 0,
        left: 0,
        child: _Corner(width: size, height: size, borders: [Border(top: side), Border(left: side)]),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: _Corner(width: size, height: size, borders: [Border(top: side), Border(right: side)]),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: _Corner(width: size, height: size, borders: [Border(bottom: side), Border(left: side)]),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: _Corner(width: size, height: size, borders: [Border(bottom: side), Border(right: side)]),
      ),
    ];
  }
}

class _Corner extends StatelessWidget {
  const _Corner({required this.width, required this.height, required this.borders});

  final double width;
  final double height;
  final List<Border> borders;

  @override
  Widget build(BuildContext context) {
    // Merge the two one-sided borders into a single container border.
    final merged = Border.merge(borders[0], borders[1]);
    return Container(width: width, height: height, decoration: BoxDecoration(border: merged));
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 5.0;
    const gap = 4.0;
    Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0, metric.length);
        dashed.addPath(metric.extractPath(distance, end.toDouble()), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.yellow : Colors.transparent,
        borderRadius: AppRadius.pill,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? AppColors.slate : Colors.white70,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected ? AppColors.slate : Colors.white70,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.onManual, required this.error});

  final VoidCallback onManual;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              l10n.cameraUnavailable(error.toString()),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onManual,
              icon: const Icon(Icons.keyboard_outlined),
              label: Text(l10n.scanModeCardPin),
            ),
          ],
        ),
      ),
    );
  }
}

/// Public entry point for the manual entry sheet (used by the wallet hero's
/// "Enter Code" CTA as well as the scan tab).
Future<void> showManualEntrySheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<(bool, bool, String?, int?)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CardEntrySheet(),
  );
}

/// Card entry sheet matching the "manual gift card entry modal" mockup:
/// card-back helper, grouped number field, PIN with reveal toggle, nickname
/// and a check-before-save verification flow.
class _CardEntrySheet extends ConsumerStatefulWidget {
  const _CardEntrySheet({
    this.presetNumber,
    this.presetPin,
    this.presetBarcodeValue,
    this.detectedValue,
    this.barcodeFormat,
  });

  final String? presetNumber;
  final String? presetPin;

  /// Full barcode payload from a GS1-128 scan, stored with the card so
  /// checkout renders the same bars the voucher carries.
  final String? presetBarcodeValue;

  /// Face value read from an imported voucher PDF; shown as a hint and used
  /// as the initial amount when the card is saved without verification.
  final double? detectedValue;

  final String? barcodeFormat;

  @override
  ConsumerState<_CardEntrySheet> createState() => _CardEntrySheetState();
}

enum _EntryPhase { idle, checking, verified, failed }

class _CardEntrySheetState extends ConsumerState<_CardEntrySheet> {
  late final TextEditingController _numberCtrl = TextEditingController(
    text: widget.presetNumber == null ? '' : _groupDigits(widget.presetNumber!),
  );
  late final TextEditingController _pinCtrl = TextEditingController(
    text: widget.presetPin ?? '',
  );
  final _nicknameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _pinVisible = false;
  _EntryPhase _phase = _EntryPhase.idle;
  String? _errorText;

  /// Card already in the wallet with the same number, when detected.
  GiftCard? _duplicate;

  @override
  void initState() {
    super.initState();
    // Prefilled imports (scan / PDF): surface a duplicate immediately so the
    // user does not wait for a network check before learning the card is
    // already in the wallet.
    if (widget.presetNumber != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _checkDuplicate();
      });
    }
  }

  GiftCard? _findDuplicate(String digits) {
    for (final card in ref.read(cardListProvider).value ?? const <GiftCard>[]) {
      if (card.cardNumber == digits) return card;
    }
    return null;
  }

  void _checkDuplicate() {
    final number = _numberCtrl.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _duplicate = _findDuplicate(number);
      if (_duplicate != null) {
        if (kDebugMode) {
          debugPrint('E2E: duplicate blocked '
              'card=…${number.substring(number.length - 4)} (on open)');
        }
        _phase = _EntryPhase.failed;
        _errorText = _duplicateMessage(_duplicate!);
      }
    });
  }

  String _duplicateMessage(GiftCard existing) {
    final l10n = AppLocalizations.of(context);
    final name = existing.nickname ??
        (existing.cardNumber.length <= 4
            ? existing.cardNumber
            : '•••• ${existing.cardNumber.substring(existing.cardNumber.length - 4)}');
    return l10n.cardAlreadyImported(name);
  }

  Future<void> _submit({
    bool forceSave = false,
    bool thenOpenManualCheck = false,
  }) async {
    if (_phase == _EntryPhase.checking || _phase == _EntryPhase.verified) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final l10n = AppLocalizations.of(context);
    final number = _numberCtrl.text.replaceAll(RegExp(r'\D'), '');
    final pin = _pinCtrl.text;

    // Deduplication: never start a network check (or a save) for a card
    // that is already in the wallet.
    final duplicate = _findDuplicate(number);
    if (duplicate != null) {
      if (kDebugMode) {
        debugPrint('E2E: duplicate blocked '
            'card=…${number.substring(number.length - 4)}');
      }
      setState(() {
        _duplicate = duplicate;
        _phase = _EntryPhase.failed;
        _errorText = _duplicateMessage(duplicate);
      });
      return;
    }

    if (!forceSave) {
      RefreshOutcome? outcome;
      // The edge occasionally challenges even a well-formed request
      // ("card not found" that succeeds on retry) — re-run the ladder once
      // when the first pass failed FAST (a burst, not a slow edge). A slow
      // failure already consumed the whole deadline: don't hold the screen
      // a second time.
      final checkStarted = DateTime.now();
      for (var tryIndex = 1; tryIndex <= 2; tryIndex++) {
        if (!mounted) return;
        setState(() {
          _phase = _EntryPhase.checking;
          _errorText = null;
        });
        outcome = await ref
            .read(balanceServiceProvider)
            .checkCard(cardNumber: number, pin: pin);
        if (!mounted) return;
        if (outcome.result.isSuccess) break;
        if (tryIndex < 2 &&
            DateTime.now().difference(checkStarted) <
                const Duration(seconds: 15)) {
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        break;
      }
      final finalOutcome = outcome!;
      // A cancelled check (app locked mid-run) is not an error — the gate
      // is up anyway; the user re-triggers the query after unlocking.
      if (finalOutcome.errorKey == RefreshErrors.cancelled) {
        return;
      }
      if (finalOutcome.result.isSuccess) {
        setState(() => _phase = _EntryPhase.verified);
        // Give the user a moment to see the verified banner before the
        // sheet closes and the card lands in the wallet.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        await _saveAndClose(
          verifiedBalance: finalOutcome.result.balance,
          verifiedStatus: finalOutcome.result.status,
          verifiedExpiry: finalOutcome.result.expiryDate,
          fetchError: null,
        );
        return;
      }
      setState(() {
        _phase = _EntryPhase.failed;
        _errorText = localizedRefreshError(
          l10n,
          finalOutcome.errorKey,
          finalOutcome.errorDetail,
        );
      });
      return;
    }
    await _saveAndClose(
      verifiedBalance: null,
      verifiedStatus: null,
      verifiedExpiry: null,
      fetchError: _errorText,
      thenOpenManualCheck: thenOpenManualCheck,
    );
  }

  Future<void> _saveAndClose({
    required double? verifiedBalance,
    required GiftCardStatus? verifiedStatus,
    required String? verifiedExpiry,
    required String? fetchError,
    bool thenOpenManualCheck = false,
  }) async {
    final number = _numberCtrl.text.replaceAll(RegExp(r'\D'), '');
    final nickname = _nicknameCtrl.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    var draft = GiftCard.draft(
      cardNumber: number,
      pin: _pinCtrl.text,
      nickname: nickname.isEmpty ? null : nickname,
      barcodeValue: widget.presetBarcodeValue,
    );
    final verified = verifiedBalance != null;
    if (verified) {
      draft = draft.copyWith(
        balance: verifiedBalance,
        initialBalance: verifiedBalance,
        status: verifiedStatus ?? GiftCardStatus.unbekannt,
        expiryDate: verifiedExpiry,
        clearExpiryDate: verifiedExpiry == null,
        lastRefreshed: now,
      );
    } else if (widget.detectedValue != null) {
      // Unverified PDF import: the printed face value is still a better
      // starting point than an unknown initial amount (progress bars work).
      draft = draft.copyWith(initialBalance: widget.detectedValue);
    }
    final result = await ref.read(cardListProvider.notifier).addCard(draft);
    if (result.isDuplicate) {
      // Race fallback: the duplicate check in _submit ran before the save.
      if (!mounted) return;
      setState(() {
        _duplicate = result.existing;
        _phase = _EntryPhase.failed;
        _errorText = _duplicateMessage(result.existing!);
      });
      return;
    }
    final id = result.id!;
    if (kDebugMode) {
      debugPrint('E2E: card saved id=$id');
    }
    if (verified) {
      try {
        await ref.read(transactionDaoProvider).insert(CardTransaction(
              cardId: id,
              type: CardTransactionType.activation,
              amount: verifiedBalance,
              balanceAfter: verifiedBalance,
              createdAt: now,
            ));
      } on StateError {
        // Crypto session locked mid-save; skip the history row.
      }
    }
    if (widget.barcodeFormat != null) {
      final saved = (await ref.read(cardDaoProvider).getById(id))!
          .copyWith(barcodeFormat: widget.barcodeFormat);
      await ref.read(cardListProvider.notifier).updateCard(saved);
    }
    if (!mounted) return;
    Navigator.of(context).pop((
      true,
      verified,
      verified
          ? verifiedBalance.toStringAsFixed(2)
          : fetchError,
      thenOpenManualCheck ? id : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bool manual = widget.presetNumber == null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.yellow,
                    ),
                    child: const Icon(
                      Icons.card_giftcard,
                      color: AppColors.slate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              l10n.manualEntryTitle,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.chipBlue,
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                l10n.manual,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: AppColors.blue),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          l10n.nicknameHint,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context).pop((false, false, null, null)),
                  ),
                ],
              ),
              if (manual) ...[
                const SizedBox(height: 16),
                _CardBackHelper(),
              ],
              if (widget.detectedValue != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined,
                        size: 15, color: AppColors.blue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.pdfAmountDetected(
                          '${widget.detectedValue!.toStringAsFixed(2)} CHF',
                        ),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.blue),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _numberCtrl,
                enabled: manual,
                inputFormatters: [_DigitGroupingFormatter()],
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  // Editing the number clears a stale duplicate warning.
                  if (_duplicate != null) {
                    setState(() {
                      _duplicate = null;
                      _phase = _EntryPhase.idle;
                      _errorText = null;
                    });
                  }
                },
                style: theme.textTheme.headlineSmall
                    ?.copyWith(letterSpacing: 1.5),
                decoration: InputDecoration(
                  labelText: l10n.cardNumberField,
                  suffixIcon: manual
                      ? IconButton(
                          icon: const Icon(Icons.content_paste, size: 20),
                          tooltip: l10n.quickPaste,
                          onPressed: () async {
                            final data = await Clipboard.getData(
                                Clipboard.kTextPlain);
                            final text = data?.text ?? '';
                            final digits =
                                text.replaceAll(RegExp(r'\D'), '');
                            if (digits.isNotEmpty) {
                              _numberCtrl.text = _groupDigits(digits);
                            }
                          },
                        )
                      : const Icon(Icons.verified_outlined,
                          color: AppColors.blue),
                ),
                validator: (v) {
                  final digits =
                      (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return RegExp(r'^\d{15,22}$').hasMatch(digits)
                      ? null
                      : l10n.invalidCardNumber;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: !_pinVisible,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  labelText: l10n.pinField,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _pinVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _pinVisible = !_pinVisible),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').length == 4 ? null : l10n.invalidPin,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: AppColors.slateMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.pinScratchHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nicknameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.nicknameOptional,
                  hintText: l10n.nicknameField,
                ),
              ),
              const SizedBox(height: 16),
              if (_phase == _EntryPhase.checking)
                _StatusBanner(
                  background: AppColors.chipBlue,
                  foreground: AppColors.blue,
                  icon: Icons.sync,
                  title: l10n.checkingBalance,
                  spin: true,
                ),
              if (_phase == _EntryPhase.verified)
                _StatusBanner(
                  background: AppColors.chipBlue,
                  foreground: AppColors.blue,
                  icon: Icons.verified,
                  title: l10n.cardVerifiedTitle,
                  body: l10n.cardVerifiedBody,
                ),
              if (_phase == _EntryPhase.failed) ...[
                _StatusBanner(
                  background: AppColors.redContainer,
                  foreground: Color(0xFFB0000C),
                  icon: Icons.error_outline,
                  // A duplicate is not a verification failure — show only
                  // the already-imported message without the scary title.
                  title: _duplicate != null
                      ? _duplicateMessage(_duplicate!)
                      : l10n.verificationFailedTitle,
                  body: _duplicate != null ? null : _errorText,
                ),
                const SizedBox(height: 10),
              ],
              if (_phase != _EntryPhase.verified)
                FilledButton.icon(
                  onPressed: _phase == _EntryPhase.checking
                      ? null
                      : () => _submit(),
                  icon: const Icon(Icons.lock_outline, size: 20),
                  label: Text(
                    l10n.checkBalanceAndSave,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (_phase == _EntryPhase.failed && _duplicate == null) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _submit(forceSave: true),
                  child: Text(l10n.saveAnyway),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      _submit(forceSave: true, thenOpenManualCheck: true),
                  child: Text(l10n.openManualCheck),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Blue/red status banner inside the entry sheet.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.title,
    this.body,
    this.spin = false,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final String title;
  final String? body;
  final bool spin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          spin
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5,
                    color: foreground),
              )
            : Icon(icon, color: foreground, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
                ),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: foreground),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawn "back of card" hint showing where to find number and PIN.
class _CardBackHelper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chipBlue,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 16, color: AppColors.blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.whereToFindCodes,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.blue),
                ),
              ),
              Text(
                l10n.backOfPhysicalCard,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2431),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.yellow, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.cardNumberField,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.yellow,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '9840 •••• •••• 5721',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.red, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.scratchPinLabel,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.red),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: AppRadius.pill,
                              ),
                              child: Text(
                                '••••',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const LidlBadge(size: 18),
                    const SizedBox(width: 8),
                    Text(
                      l10n.giftCardLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white54,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Groups typed digits into 4-4-4-… blocks with spaces.
class _DigitGroupingFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 22) return oldValue;
    final grouped = _groupDigits(digits);
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}

/// Groups a digit string into blocks of four separated by spaces.
String _groupDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    if ((i + 1) % 4 == 0 && i + 1 != digits.length) buffer.write(' ');
  }
  return buffer.toString();
}
