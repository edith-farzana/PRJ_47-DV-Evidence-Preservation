import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secure_evidence_app/app/app.dart';
import 'package:secure_evidence_app/app/app_lock_controller.dart';
import 'package:secure_evidence_app/features/auth/presentation/pin_page.dart';
import 'package:secure_evidence_app/features/auth/presentation/setup_page.dart';
import 'package:secure_evidence_app/features/calculator/presentation/calculator_page.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/storage/evidence_storage.dart';

import 'helpers/fake_secure_store.dart';

/// The app under test. Nothing here touches storage, so the directory
/// is never created.
SecureEvidenceApp buildApp({String? unlockSequence}) {
  final store = FakeSecureStore();
  final keyManager = KeyManager(store);

  return SecureEvidenceApp(
    keyManager: keyManager,
    storage: EvidenceStorage(
      baseDirectory: Directory('${Directory.systemTemp.path}/unused'),
      keyManager: keyManager,
      store: store,
    ),
    lockController: AppLockController(keyManager: keyManager, store: store),
    unlockSequence: unlockSequence,
  );
}

void main() {
  // A typical portrait phone, rather than the default 800x600 test
  // surface the calculator was never laid out for.
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('first launch shows setup, not the calculator', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.byType(SetupPage), findsOneWidget);
    expect(find.byType(CalculatorPage), findsNothing);
  });

  testWidgets('once set up, the app opens as a calculator', (tester) async {
    await tester.pumpWidget(buildApp(unlockSequence: '7×3-1='));

    expect(find.byType(CalculatorPage), findsOneWidget);
  });

  testWidgets('the chosen sequence opens the PIN screen', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(unlockSequence: '7×3-1='));

    for (final key in ['7', '×', '3', '-', '1', '=']) {
      await tester.tap(find.widgetWithText(InkWell, key).first);
      await tester.pump();
    }

    expect(find.byType(PinPage), findsOneWidget);
  });

  testWidgets('the old hardcoded sequence no longer opens anything', (
    tester,
  ) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(unlockSequence: '7×3-1='));

    for (final key in ['1', '+', '2', '+', '3', '+', '4', '=']) {
      await tester.tap(find.widgetWithText(InkWell, key).first);
      await tester.pump();
    }

    expect(find.byType(PinPage), findsNothing);
    expect(find.byType(CalculatorPage), findsOneWidget);
  });
}
