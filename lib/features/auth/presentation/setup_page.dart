import 'package:flutter/material.dart';

import '../../../services/crypto/key_manager.dart';
import '../domain/pin_validator.dart';
import '../domain/unlock_sequence.dart';
import 'auth_widgets.dart';

/// First run: choose a PIN and the calculator sequence that opens it.
///
/// Creates the master key. After this, every launch starts at the
/// calculator.
class SetupPage extends StatefulWidget {
  const SetupPage({
    super.key,
    required this.keyManager,
    required this.onComplete,
  });

  final KeyManager keyManager;

  /// Called with the stored unlock sequence once the vault exists.
  final ValueChanged<String> onComplete;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _sequence = TextEditingController();

  final PinValidator _validator = const PinValidator();

  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    _sequence.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final pin = _pin.text.trim();
    final sequence = UnlockSequence.normalize(_sequence.text);

    final error =
        _validator.validate(pin) ??
        (pin != _confirm.text.trim() ? 'The PINs do not match.' : null) ??
        UnlockSequence.validate(sequence);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    final stored = UnlockSequence.toStored(sequence);

    try {
      await widget.keyManager.setUp(pin: pin, unlockSequence: stored);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not create the vault: $error';
        });
      }
      return;
    }

    // Straight to the calculator, locked, so the first thing the user
    // does is practise the sequence and the PIN.
    widget.keyManager.lock();

    if (mounted) {
      widget.onComplete(stored);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              const Text(
                'Set up',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'This app opens as a calculator. Choose the keys that '
                'open it, and a PIN to unlock it.',
                style: TextStyle(color: Colors.white54, fontSize: 15),
              ),

              const SizedBox(height: 28),

              AuthField(
                controller: _pin,
                label: '4-digit PIN',
                enabled: !_busy,
              ),

              const SizedBox(height: 14),

              AuthField(
                controller: _confirm,
                label: 'Confirm PIN',
                enabled: !_busy,
              ),

              const SizedBox(height: 14),

              AuthField(
                controller: _sequence,
                label: 'Calculator keys, e.g. 7*3-1',
                obscure: false,
                numeric: false,
                maxLength: UnlockSequence.maxLength,
                enabled: !_busy,
              ),

              const SizedBox(height: 8),

              ValueListenableBuilder(
                valueListenable: _sequence,
                builder: (_, value, _) {
                  final preview = UnlockSequence.normalize(value.text);

                  return Text(
                    preview.isEmpty
                        ? 'Use digits and + - * /, with at least one operator.'
                        : 'To open: type $preview then press =',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  );
                },
              ),

              const SizedBox(height: 22),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0x33FF5252),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Your PIN cannot be recovered. It never leaves this phone, '
                  'and nobody — including us — can reset it. If you forget '
                  'it, the evidence stored here cannot be opened.',
                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                ),
              ),

              AuthError(_error),

              const SizedBox(height: 22),

              AuthButton(
                label: 'Create vault',
                busy: _busy,
                onPressed: _create,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
