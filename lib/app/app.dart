import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../features/auth/presentation/pin_page.dart';
import '../features/auth/presentation/setup_page.dart';
import '../features/calculator/presentation/calculator_page.dart';
import '../features/home/home_page.dart';
import '../services/crypto/key_manager.dart';
import '../services/storage/evidence_storage.dart';
import 'app_lock_controller.dart';
import 'app_scope.dart';

class SecureEvidenceApp extends StatefulWidget {
  const SecureEvidenceApp({
    super.key,
    required this.keyManager,
    required this.storage,
    required this.lockController,
    required this.unlockSequence,
  });

  final KeyManager keyManager;
  final EvidenceStorage storage;
  final AppLockController lockController;

  /// Null until first-run setup has been completed.
  final String? unlockSequence;

  /// How long a press anywhere in the evidence center must be held to
  /// trigger panic. Longer than the 500ms platform long-press, so text
  /// selection wins in text fields and a resting thumb does not panic.
  static const Duration panicHoldDuration = Duration(seconds: 1);

  @override
  State<SecureEvidenceApp> createState() => _SecureEvidenceAppState();
}

class _SecureEvidenceAppState extends State<SecureEvidenceApp> {
  late String? _unlockSequence = widget.unlockSequence;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  AppLockController get _lock => widget.lockController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lock);
    _lock.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    _lock.removeListener(_onLockChanged);
    WidgetsBinding.instance.removeObserver(_lock);
    super.dispose();
  }

  void _onLockChanged() {
    if (_lock.state == AppLockState.locked) {
      // Pushed routes (vault, camera, dialogs, sheets) sit above `home`
      // and would otherwise stay on top of the calculator.
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);

      // A "Photo saved to My Evidence" snackbar must not survive onto
      // the calculator.
      _messengerKey.currentState
        ?..clearSnackBars()
        ..clearMaterialBanners();
    }

    setState(() {});
  }

  /// Called when setup has created the master key.
  void _completeSetup(String unlockSequence) {
    setState(() {
      _unlockSequence = unlockSequence;
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

    if (_lock.state == AppLockState.unlocked && widget.keyManager.isUnlocked) {
      return HomePage(keyManager: widget.keyManager);
    }

    if (_lock.state == AppLockState.showPin) {
      return PinPage(keyManager: widget.keyManager, onSuccess: _lock.unlocked);
    }

    return CalculatorPage(
      // A new key per lock gives a fresh calculator: cleared display and
      // no half-typed unlock sequence left over.
      key: ValueKey(_lock.lockCount),
      onPrivateAccess: _lock.showPin,
      unlockSequence: sequence,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      keyManager: widget.keyManager,
      storage: widget.storage,
      lockController: _lock,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
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

        // Wraps the Navigator, so the hold works over every pushed
        // route, dialog and sheet -- panic without going home first.
        builder: (context, child) => _PanicHold(
          enabled: _lock.state == AppLockState.unlocked,
          onPanic: _lock.lock,
          child: child!,
        ),

        home: _home(),
      ),
    );
  }
}

class _PanicHold extends StatelessWidget {
  const _PanicHold({
    required this.enabled,
    required this.onPanic,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onPanic;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Always present, so enabling it does not change the tree shape
    // above the Navigator.
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        if (enabled)
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: SecureEvidenceApp.panicHoldDuration,
                ),
                (recognizer) => recognizer.onLongPress = onPanic,
              ),
      },
      child: child,
    );
  }
}
