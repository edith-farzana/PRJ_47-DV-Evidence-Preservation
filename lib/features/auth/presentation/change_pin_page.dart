import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';

import '../../../services/crypto/key_manager.dart';
import '../domain/pin_validator.dart';
import 'auth_widgets.dart';

/// Re-wraps the master key under a new PIN. No evidence is
/// re-encrypted, so this is instant however much is stored.
class ChangePinPage extends StatefulWidget {
  const ChangePinPage({super.key, required this.keyManager});

  final KeyManager keyManager;

  @override
  State<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends State<ChangePinPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  final PinValidator _validator = const PinValidator();

  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final current = _current.text.trim();
    final next = _next.text.trim();

    final error =
        _validator.validate(current) ??
        _validator.validate(next) ??
        (next != _confirm.text.trim() ? 'The new PINs do not match.' : null) ??
        (next == current
            ? 'The new PIN is the same as the current one.'
            : null);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    // A wrong current PIN counts toward the same lockout as the unlock
    // screen, so this page is not a way round it.
    final result = await widget.keyManager.changePin(
      oldPin: current,
      newPin: next,
    );

    if (!mounted) {
      return;
    }

    switch (result.status) {
      case UnlockStatus.success:
        // The key manager has just reset its count of wrong current-PIN
        // attempts made on this screen; the activity log keeps them.
        unawaited(AppScope.of(context).audit.onPinChanged(result));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PIN changed.')));
        Navigator.of(context).pop();
      case UnlockStatus.wrongPin:
        _current.clear();
        setState(() {
          _busy = false;
          _error = 'The current PIN is incorrect.';
        });
      case UnlockStatus.lockedOut:
        _current.clear();
        setState(() {
          _busy = false;
          _error =
              'Too many attempts. Try again after '
              '${TimeOfDay.fromDateTime(result.lockedUntil!).format(context)}.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.background,
      appBar: AppBar(
        backgroundColor: AuthColors.background,
        foregroundColor: Colors.white,
        title: const Text('Change PIN'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _current,
                label: 'Current PIN',
                enabled: !_busy,
              ),

              const SizedBox(height: 14),

              AuthField(controller: _next, label: 'New PIN', enabled: !_busy),

              const SizedBox(height: 14),

              AuthField(
                controller: _confirm,
                label: 'Confirm new PIN',
                enabled: !_busy,
              ),

              AuthError(_error),

              const SizedBox(height: 22),

              AuthButton(label: 'Change PIN', busy: _busy, onPressed: _change),
            ],
          ),
        ),
      ),
    );
  }
}
