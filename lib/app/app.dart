import 'package:flutter/material.dart';

import '../features/auth/presentation/pin_page.dart';
import '../features/auth/presentation/setup_page.dart';
import '../features/calculator/presentation/calculator_page.dart';
import '../features/home/home_page.dart';
import 'app_lock_controller.dart';
import 'app_scope.dart';

class SecureEvidenceApp extends StatelessWidget {
  const SecureEvidenceApp({super.key, required this.lock});

  final AppLockController lock;

  Widget _home() {
    switch (lock.state) {
      case AppLockState.needsSetup:
        return SetupPage(
          keyManager: lock.keyManager,
          onComplete: lock.completeSetup,
        );
      case AppLockState.calculator:
        return CalculatorPage(
          // A new key per lock: the calculator comes back cleared.
          key: ValueKey(lock.generation),
          onPrivateAccess: lock.openPin,
          unlockSequence: lock.unlockSequence!,
        );
      case AppLockState.pin:
        return PinPage(keyManager: lock.keyManager, onSuccess: lock.onUnlocked);
      case AppLockState.unlocked:
        return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      lock: lock,
      child: ListenableBuilder(
        listenable: lock,
        builder: (context, _) => MaterialApp(
          navigatorKey: lock.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Calculator',

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
      ),
    );
  }
}
