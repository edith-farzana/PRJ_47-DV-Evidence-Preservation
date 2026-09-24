import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/app/app_lock_controller.dart';
import 'package:secure_evidence_app/services/audit/audit_log.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';

import '../helpers/fake_secure_store.dart';

void main() {
  late FakeSecureStore store;
  late KeyManager keyManager;
  late AppLockController controller;

  /// A controller whose key is in memory and which shows the evidence
  /// center, as after a correct PIN.
  Future<void> unlock() async {
    await keyManager.setUp(pin: '1234', unlockSequence: '7×3-1=');
    controller
      ..showPin()
      ..unlocked();
  }

  setUp(() {
    store = FakeSecureStore();
    keyManager = KeyManager(store, kdfIterations: 1000);
    controller = AppLockController(keyManager: keyManager, store: store);
  });

  group('panic', () {
    test('drops the key and returns to the calculator', () async {
      await unlock();
      final lockCount = controller.lockCount;

      controller.lock();

      expect(keyManager.isUnlocked, isFalse);
      expect(controller.state, AppLockState.locked);
      expect(controller.lockCount, lockCount + 1);
    });

    test('the key is already gone when listeners run', () async {
      await unlock();
      bool? unlockedDuringNotify;
      controller.addListener(
        () => unlockedDuringNotify = keyManager.isUnlocked,
      );

      controller.lock();

      expect(unlockedDuringNotify, isFalse);
    });

    test('ignores a capture holding off auto-lock', () async {
      await unlock();
      controller.holdAutoLock();

      controller.lock();

      expect(keyManager.isUnlocked, isFalse);
      expect(controller.state, AppLockState.locked);
    });

    test('the vault needs the PIN again afterwards', () async {
      await unlock();
      controller.lock();

      controller.showPin();

      expect(controller.state, AppLockState.showPin);
      expect(keyManager.isUnlocked, isFalse);
      expect(() => keyManager.masterKey, throwsStateError);
    });
  });

  group('auto-lock', () {
    test('is on by default', () async {
      await controller.load();

      expect(controller.autoLock, isTrue);
    });

    test('paused locks when auto-lock is on', () async {
      await unlock();

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(keyManager.isUnlocked, isFalse);
      expect(controller.state, AppLockState.locked);
    });

    test('hidden locks too', () async {
      await unlock();

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);

      expect(controller.state, AppLockState.locked);
    });

    test('paused does not lock when auto-lock is off', () async {
      await unlock();
      await controller.setAutoLock(false);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(keyManager.isUnlocked, isTrue);
      expect(controller.state, AppLockState.unlocked);
    });

    test(
      'inactive does not lock (permission dialogs, notification shade)',
      () async {
        await unlock();

        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);

        expect(keyManager.isUnlocked, isTrue);
      },
    );

    test('paused on the PIN screen goes back to the calculator', () {
      controller.showPin();
      final lockCount = controller.lockCount;

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(controller.state, AppLockState.locked);
      expect(controller.lockCount, lockCount + 1);
    });

    test('paused on the calculator does nothing', () {
      final lockCount = controller.lockCount;

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(controller.lockCount, lockCount);
    });

    test('the preference survives a restart', () async {
      await controller.setAutoLock(false);

      final restarted = AppLockController(keyManager: keyManager, store: store);
      await restarted.load();

      expect(restarted.autoLock, isFalse);
    });
  });

  group('capture hold', () {
    test('paused during a capture keeps the key', () async {
      await unlock();
      controller.holdAutoLock();

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(keyManager.isUnlocked, isTrue);
    });

    test('releasing in the background runs the deferred lock', () async {
      await unlock();
      controller.holdAutoLock();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      controller.releaseAutoLock();

      expect(keyManager.isUnlocked, isFalse);
      expect(controller.state, AppLockState.locked);
    });

    test('releasing after returning to the app does not lock', () async {
      await unlock();
      controller.holdAutoLock();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      controller.releaseAutoLock();

      expect(keyManager.isUnlocked, isTrue);
    });

    test('nested holds lock only when the last is released', () async {
      await unlock();
      controller
        ..holdAutoLock()
        ..holdAutoLock();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      controller.releaseAutoLock();
      expect(keyManager.isUnlocked, isTrue);

      controller.releaseAutoLock();
      expect(keyManager.isUnlocked, isFalse);
    });

    test('a release after panic is harmless', () async {
      await unlock();
      controller.holdAutoLock();
      controller.lock();

      // The capture page is disposed after panic and releases its hold.
      controller.releaseAutoLock();

      expect(controller.state, AppLockState.locked);
    });
  });

  group('activity log', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('lock_audit_');
      controller = AppLockController(
        keyManager: keyManager,
        store: store,
        audit: AuditLog(
          baseDirectory: workspace,
          store: store,
          keyManager: keyManager,
        ),
      );
    });

    tearDown(() => workspace.delete(recursive: true));

    // Landing in the pending list, not the chain, is the proof the key
    // was already destroyed when the event was written. Panic must not
    // wait for the log.
    test('panic is recorded, after the key is gone', () async {
      await unlock();

      controller.lock();
      await Future<void>.delayed(Duration.zero);

      expect(store.values['audit.v1.pending'], contains('"panic"'));
    });

    test('auto-lock is recorded as such, not as panic', () async {
      await unlock();

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      final pending = store.values['audit.v1.pending']!;

      expect(pending, contains('"autoLocked"'));
      expect(pending, isNot(contains('"panic"')));
    });
  });
}
