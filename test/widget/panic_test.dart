import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secure_evidence_app/app/app.dart';
import 'package:secure_evidence_app/app/app_lock_controller.dart';
import 'package:secure_evidence_app/features/auth/presentation/pin_page.dart';
import 'package:secure_evidence_app/features/calculator/presentation/calculator_page.dart';
import 'package:secure_evidence_app/features/home/home_page.dart';
import 'package:secure_evidence_app/services/audit/audit_log.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/storage/evidence_storage.dart';

import '../helpers/fake_secure_store.dart';
import '../helpers/offline_sync.dart';

const sequence = '7×3-1=';

/// Lets route and sheet transitions finish. Not pumpAndSettle: the
/// vault tab, built inside the home IndexedStack, shows a spinner
/// that never stops under the fake test clock.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late KeyManager keyManager;
  late AppLockController controller;

  /// Pumps the app past the calculator and PIN, into the evidence
  /// center. The PIN step itself is covered by the KeyManager tests;
  /// here the key is set up directly and the controller told.
  Future<void> pumpUnlocked(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = FakeSecureStore();
    keyManager = KeyManager(store, kdfIterations: 1000);
    controller = AppLockController(keyManager: keyManager, store: store);

    await tester.runAsync(
      () => keyManager.setUp(pin: '1234', unlockSequence: sequence),
    );

    await tester.pumpWidget(
      SecureEvidenceApp(
        keyManager: keyManager,
        storage: EvidenceStorage(
          baseDirectory: Directory('${Directory.systemTemp.path}/unused'),
          keyManager: keyManager,
          store: store,
        ),
        lockController: controller,
        sync: offlineSync(),
        audit: AuditLog(
          baseDirectory: Directory('${Directory.systemTemp.path}/unused'),
          store: store,
          keyManager: keyManager,
        ),
        unlockSequence: sequence,
      ),
    );

    controller
      ..showPin()
      ..unlocked();
    await settle(tester);

    expect(find.byType(HomePage), findsOneWidget);
  }

  /// The calculator's main display, which is the larger of its texts.
  String calculatorDisplay(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(CalculatorPage),
            matching: find.byType(Text),
          ),
        )
        .where((t) => t.style?.fontSize == 64);

    return texts.single.data!;
  }

  Future<void> tapPanic(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Panic Mode'));
    await tester.tap(find.text('Panic Mode'));
    await settle(tester);
  }

  Future<void> holdAnywhere(WidgetTester tester, Duration duration) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MaterialApp)),
    );
    await tester.pump(duration);
    await gesture.up();
    await settle(tester);
  }

  testWidgets('panic button: unlocked -> calculator reading 0', (tester) async {
    await pumpUnlocked(tester);

    await tapPanic(tester);

    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(CalculatorPage), findsOneWidget);
    expect(calculatorDisplay(tester), '0');
    expect(keyManager.isUnlocked, isFalse);
  });

  testWidgets('after panic, the vault needs the PIN again', (tester) async {
    await pumpUnlocked(tester);

    await tapPanic(tester);

    for (final key in ['7', '×', '3', '-', '1', '=']) {
      await tester.tap(find.widgetWithText(InkWell, key).first);
      await tester.pump();
    }

    expect(find.byType(PinPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('holding anywhere panics, even over an open sheet', (
    tester,
  ) async {
    await pumpUnlocked(tester);

    await tester.tap(find.text('Capture Evidence'));
    await settle(tester);
    expect(find.text('Take Photo'), findsOneWidget);

    await holdAnywhere(tester, const Duration(milliseconds: 1100));

    expect(find.text('Take Photo'), findsNothing);
    expect(find.byType(CalculatorPage), findsOneWidget);
    expect(keyManager.isUnlocked, isFalse);
  });

  testWidgets('an ordinary long-press does not panic', (tester) async {
    await pumpUnlocked(tester);

    await holdAnywhere(tester, const Duration(milliseconds: 600));

    expect(find.byType(HomePage), findsOneWidget);
    expect(keyManager.isUnlocked, isTrue);
  });

  testWidgets('panic clears a visible snackbar', (tester) async {
    await pumpUnlocked(tester);

    ScaffoldMessenger.of(
      tester.element(find.byType(HomePage)),
    ).showSnackBar(const SnackBar(content: Text('Photo saved to My Evidence')));
    await settle(tester);
    expect(find.text('Photo saved to My Evidence'), findsOneWidget);

    await tapPanic(tester);

    expect(find.text('Photo saved to My Evidence'), findsNothing);
  });

  testWidgets('backgrounding the app locks it', (tester) async {
    await pumpUnlocked(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);

    expect(find.byType(CalculatorPage), findsOneWidget);
    expect(keyManager.isUnlocked, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
