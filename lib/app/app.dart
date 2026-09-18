import 'package:flutter/material.dart';

import '../features/auth/presentation/pin_page.dart';
import '../features/auth/presentation/setup_page.dart';
import '../features/calculator/presentation/calculator_page.dart';
import '../features/home/home_page.dart';
import '../services/crypto/key_manager.dart';
import '../services/storage/evidence_storage.dart';
import 'app_scope.dart';

class SecureEvidenceApp extends StatefulWidget {
  const SecureEvidenceApp({
    super.key,
    required this.keyManager,
    required this.storage,
    required this.unlockSequence,
  });

  final KeyManager keyManager;
  final EvidenceStorage storage;

  /// Null until first-run setup has been completed.
  final String? unlockSequence;

  @override
  State<SecureEvidenceApp> createState() => _SecureEvidenceAppState();
}

class _SecureEvidenceAppState extends State<SecureEvidenceApp> {
  late String? _unlockSequence = widget.unlockSequence;
  bool _showPin = false;

  /// Called when setup has created the master key.
  void _completeSetup(String unlockSequence) {
    setState(() {
      _unlockSequence = unlockSequence;
    });
  }

  /// Called when the secret calculator sequence is entered.
  void _openPin() {
    setState(() {
      _showPin = true;
    });
  }

  /// Called when the PIN has unwrapped the master key.
  void _unlock() {
    setState(() {
      // Once the key is locked again, start from the calculator.
      _showPin = false;
    });
  }

  Widget _home() {
    final sequence = _unlockSequence;

    if (sequence == null) {
      return SetupPage(
        keyManager: widget.keyManager,
        onComplete: _completeSetup,
      );
    }

    if (widget.keyManager.isUnlocked) {
      return HomePage(keyManager: widget.keyManager);
    }

    if (_showPin) {
      return PinPage(keyManager: widget.keyManager, onSuccess: _unlock);
    }

    return CalculatorPage(onPrivateAccess: _openPin, unlockSequence: sequence);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      keyManager: widget.keyManager,
      storage: widget.storage,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Secure Evidence',

        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF090B10),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF9B7BFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),

        home: _home(),
      ),
    );
  }
}
