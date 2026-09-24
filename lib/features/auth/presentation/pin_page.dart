import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/crypto/key_manager.dart';
import '../domain/pin_validator.dart';

class PinPage extends StatefulWidget {
  final KeyManager keyManager;

  /// Receives the result, which carries the wrong PINs entered before
  /// this one -- the key manager has just reset its count of them.
  final ValueChanged<UnlockResult> onSuccess;

  const PinPage({super.key, required this.keyManager, required this.onSuccess});

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  final TextEditingController _controller = TextEditingController();
  final PinValidator _validator = const PinValidator();

  String _error = '';
  bool _busy = false;
  DateTime? _lockedUntil;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();

    // A lockout from before a restart still applies.
    widget.keyManager.lockedUntil().then((until) {
      if (mounted && until != null) {
        _startLockout(until);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _lockedOut => _lockedUntil != null;

  void _startLockout(DateTime until) {
    _ticker?.cancel();

    setState(() {
      _lockedUntil = until;
      _error = '';
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      if (DateTime.now().isAfter(until)) {
        _ticker?.cancel();
        setState(() => _lockedUntil = null);
        return;
      }

      setState(() {});
    });
  }

  String _lockoutMessage() {
    final remaining = _lockedUntil!.difference(DateTime.now());
    final seconds = remaining.inSeconds + 1;

    if (seconds < 60) {
      return 'Too many attempts. Try again in ${seconds}s.';
    }

    return 'Too many attempts. Try again in ${remaining.inMinutes + 1} min.';
  }

  Future<void> _submitPin() async {
    if (_busy || _lockedOut) {
      return;
    }

    final pin = _controller.text.trim();

    // First check whether the input is structurally valid. A malformed
    // PIN is not an attempt and does not count toward the lockout.
    if (!_validator.isValid(pin)) {
      setState(() {
        _error = _validator.validate(pin) ?? 'Invalid PIN.';
      });

      _controller.clear();
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    // The PIN is correct only if it unwraps the master key.
    final result = await widget.keyManager.unlock(pin);

    if (!mounted) {
      return;
    }

    _controller.clear();
    setState(() => _busy = false);

    switch (result.status) {
      case UnlockStatus.success:
        FocusScope.of(context).unfocus();
        widget.onSuccess(result);
      case UnlockStatus.wrongPin:
        final left = KeyManager.freeAttempts - result.failedAttempts;
        setState(() {
          _error = left > 0
              ? 'Incorrect PIN. $left ${left == 1 ? 'attempt' : 'attempts'} '
                    'before a timeout.'
              : 'Incorrect PIN.';
        });
      case UnlockStatus.lockedOut:
        _startLockout(result.lockedUntil!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0712),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C3CEB),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 40,
                  ),
                ),

                const SizedBox(height: 28),

                const Text(
                  'Secure Evidence',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Enter PIN',
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: _controller,
                  enabled: !_busy && !_lockedOut,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF171020),
                    hintText: 'PIN',
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFF8B5CF6),
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) {
                    if (_error.isNotEmpty) {
                      setState(() {
                        _error = '';
                      });
                    }
                  },
                  onSubmitted: (_) => _submitPin(),
                ),

                if (_error.isNotEmpty || _lockedOut) ...[
                  const SizedBox(height: 10),

                  Text(
                    _lockedOut ? _lockoutMessage() : _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 14,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _busy || _lockedOut ? null : _submitPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C3CEB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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
