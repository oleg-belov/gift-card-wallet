import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/crypto_service.dart';
import '../state/providers.dart';

enum LockScreenMode { setup, unlock }

/// Full-screen gate shown while the app is locked (or on first run when the
/// app PIN must be created). All card data stays encrypted until the correct
/// PIN is entered.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.mode});

  final LockScreenMode mode;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;

  // Brute-force throttle: after 5 wrong entries the screen blocks for 30 s.
  static const _maxAttempts = 5;
  static const _cooldownSeconds = 30;
  int _failedAttempts = 0;
  int _remainingCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  bool get _coolingDown => _remainingCooldown > 0;

  void _startCooldown() {
    _remainingCooldown = _cooldownSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _remainingCooldown -= 1;
        if (_remainingCooldown <= 0) {
          _failedAttempts = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _submit() async {
    if (_busy || _coolingDown) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      if (widget.mode == LockScreenMode.setup) {
        await ref.read(lockStateProvider.notifier).setup(_pinController.text);
      } else {
        await ref.read(lockStateProvider.notifier).unlock(_pinController.text);
      }
      // On success the AppGate switches to the wallet; nothing to do here.
    } on WrongPinException {
      setState(() {
        _failedAttempts += 1;
        if (_failedAttempts >= _maxAttempts) _startCooldown();
      });
      _pinController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _pinValidator(String? value, AppLocalizations l10n) {
    if (value == null || value.length != 4) return l10n.invalidPin;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isSetup = widget.mode == LockScreenMode.setup;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      isSetup ? Icons.shield_outlined : Icons.lock_outline,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isSetup ? l10n.lockSetupTitle : l10n.lockUnlockTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    if (isSetup) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.lockSetupSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      l10n.personalUseNotice,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _pinController,
                      decoration: InputDecoration(
                        labelText: l10n.appPinField,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      maxLength: 4,
                      obscureText: true,
                      autofocus: true,
                      enabled: !_coolingDown,
                      validator: (value) => _pinValidator(value, l10n),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (isSetup) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmController,
                        decoration: InputDecoration(
                          labelText: l10n.confirmAppPinField,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        maxLength: 4,
                        obscureText: true,
                        enabled: !_coolingDown,
                        validator: (value) {
                          if (value == null || value.length != 4) {
                            return l10n.invalidPin;
                          }
                          if (value != _pinController.text) {
                            return l10n.pinMismatch;
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_coolingDown) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.tooManyAttempts(_remainingCooldown),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ] else if (_failedAttempts > 0) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.wrongPin,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    if (isSetup) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: theme.colorScheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_outlined,
                                  color: theme.colorScheme.onTertiaryContainer),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l10n.lockSetupWarning,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy || _coolingDown ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(isSetup ? Icons.shield : Icons.lock_open),
                      label: Text(
                        isSetup ? l10n.lockSetupButton : l10n.lockUnlockButton,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the "Change PIN" sheet. Verifies the current PIN, then re-encrypts
/// every stored card under the new one.
Future<void> showChangePinSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ChangePinSheet(),
  );
}

class _ChangePinSheet extends ConsumerStatefulWidget {
  const _ChangePinSheet();

  @override
  ConsumerState<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends ConsumerState<_ChangePinSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(lockStateProvider.notifier)
          .changePin(_currentController.text, _newController.text);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pinChangedMsg)),
        );
      }
    } on WrongPinException {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wrongPin)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.changePinTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            TextFormField(
              controller: _currentController,
              decoration: InputDecoration(labelText: l10n.currentPinField),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              maxLength: 4,
              obscureText: true,
              autofocus: true,
              validator: (value) =>
                  value == null || value.length != 4 ? l10n.invalidPin : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newController,
              decoration: InputDecoration(labelText: l10n.newPinField),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              maxLength: 4,
              obscureText: true,
              validator: (value) =>
                  value == null || value.length != 4 ? l10n.invalidPin : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              decoration: InputDecoration(labelText: l10n.confirmNewPinField),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              maxLength: 4,
              obscureText: true,
              validator: (value) {
                if (value == null || value.length != 4) return l10n.invalidPin;
                if (value != _newController.text) return l10n.pinMismatch;
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.password),
              label: Text(l10n.changePinMenu),
            ),
          ],
        ),
      ),
    );
  }
}
