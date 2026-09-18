import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/app/app_lock_controller.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/services/crypto/crypto_service.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/storage/evidence_storage.dart';

import '../helpers/fake_secure_store.dart';

/// Stands in for a capture screen that is recording.
class _FakeCapture implements CaptureSession {
  _FakeCapture(this.file);

  final File file;
  bool stopped = false;

  @override
  Future<(File, EvidenceType)?> stopAndHandOver() async {
    stopped = true;
    return (file, EvidenceType.audio);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory workspace;
  late FakeSecureStore store;
  late KeyManager keyManager;
  late EvidenceStorage storage;
  late AppLockController lock;

  Future<void> unlock() async {
    lock.openPin();
    expect((await keyManager.unlock('1234')).isSuccess, isTrue);
    lock.onUnlocked();
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('lock_test_');
    store = FakeSecureStore();
    keyManager = KeyManager(store, kdfIterations: 1000);
    await keyManager.setUp(pin: '1234', unlockSequence: '7×3-1=');
    keyManager.lock();

    storage = EvidenceStorage(
      baseDirectory: workspace,
      keyManager: keyManager,
      store: store,
    );

    lock = AppLockController(
      keyManager: keyManager,
      storage: storage,
      store: store,
      unlockSequence: '7×3-1=',
    );
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('a set-up app starts at the calculator, a fresh one at setup', () {
    expect(lock.state, AppLockState.calculator);

    final fresh = AppLockController(
      keyManager: keyManager,
      storage: storage,
      store: store,
      unlockSequence: null,
    );

    expect(fresh.state, AppLockState.needsSetup);
  });

  group('panic', () {
    test('returns to the calculator and destroys the key', () async {
      await unlock();
      final generation = lock.generation;

      await lock.panic();

      expect(lock.state, AppLockState.calculator);
      expect(keyManager.isUnlocked, isFalse);
      expect(() => keyManager.masterKey, throwsStateError);
      expect(lock.generation, greaterThan(generation));
    });

    test('after panic, the vault needs the PIN again', () async {
      await unlock();
      await lock.panic();

      lock.openPin();
      expect(lock.state, AppLockState.pin);
      expect((await keyManager.unlock('0000')).isSuccess, isFalse);
      expect(keyManager.isUnlocked, isFalse);
    });

    test('a running recording is stopped and saved, not lost', () async {
      await unlock();

      final recording = await storage.newPendingFile(
        EvidenceType.audio,
        '.m4a',
      );
      await recording.writeAsString('audio bytes');

      final capture = _FakeCapture(recording);
      lock.registerCapture(capture);

      await lock.panic();
      await Future.wait(lock.pendingSaves);

      expect(capture.stopped, isTrue);
      expect(keyManager.isUnlocked, isFalse);
      expect(await recording.exists(), isFalse);

      // It is in the vault, readable after unlocking again.
      await keyManager.unlock('1234');
      final items = await storage.getEvidence();
      expect(items, hasLength(1));
      expect(items.single.type, EvidenceType.audio);
    });

    test('an unregistered capture is left alone', () async {
      await unlock();

      final capture = _FakeCapture(File('${workspace.path}/unused'));
      lock.registerCapture(capture);
      lock.unregisterCapture(capture);

      await lock.panic();

      expect(capture.stopped, isFalse);
    });
  });

  group('auto-lock', () {
    test('paused locks when auto-lock is on', () async {
      await unlock();

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(lock.state, AppLockState.calculator);
      expect(keyManager.isUnlocked, isFalse);
    });

    test('hidden locks when auto-lock is on', () async {
      await unlock();

      lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(Duration.zero);

      expect(keyManager.isUnlocked, isFalse);
    });

    test('paused does not lock when auto-lock is off', () async {
      await unlock();
      await lock.setAutoLock(false);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(lock.state, AppLockState.unlocked);
      expect(keyManager.isUnlocked, isTrue);
    });

    test(
      'inactive never locks (permission dialogs, notification shade)',
      () async {
        await unlock();

        lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
        await Future<void>.delayed(Duration.zero);

        expect(lock.state, AppLockState.unlocked);
        expect(keyManager.isUnlocked, isTrue);
      },
    );

    test('backgrounding on the PIN screen returns to the calculator', () async {
      lock.openPin();

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(lock.state, AppLockState.calculator);
    });

    test('the setting persists across restarts', () async {
      await lock.setAutoLock(false);

      final restarted = AppLockController(
        keyManager: keyManager,
        storage: storage,
        store: store,
        unlockSequence: '7×3-1=',
      );
      await restarted.attach();
      addTearDown(restarted.dispose);

      expect(restarted.autoLock, isFalse);
    });
  });

  group('saves survive a lock', () {
    test('locking mid-save still stores evidence under the real key', () async {
      await unlock();

      final source = File('${workspace.path}/clip.m4a');
      await source.writeAsBytes(List<int>.generate(512 * 1024, (i) => i % 251));

      // Start the save, then lock before it can finish.
      final save = storage.addEvidence(
        sourceFile: source,
        type: EvidenceType.audio,
      );
      await Future<void>.delayed(Duration.zero);
      await lock.panic();

      final item = await save;

      await keyManager.unlock('1234');
      final recovered = await CryptoService().decryptToFile(
        source: File(item.filePath),
        destination: File('${workspace.path}/recovered.m4a'),
        masterKey: keyManager.masterKey,
        wrappedDek: item.wrappedDek!,
        nonce: item.nonce!,
        gcmTag: item.gcmTag!,
        plaintextSha256: item.plaintextSha256!,
      );

      expect(
        await recovered.readAsBytes(),
        List<int>.generate(512 * 1024, (i) => i % 251),
      );
    });

    test('unlocking stores captures left in the pending folder', () async {
      // As if the app had been killed before a capture was encrypted.
      await storage.pendingDirectory.create(recursive: true);
      final orphan = File(
        '${storage.pendingDirectory.path}/video_1_abcd1234.mp4',
      );
      await orphan.writeAsString('video bytes');

      await unlock();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final items = await storage.getEvidence();

      expect(items, hasLength(1));
      expect(items.single.type, EvidenceType.video);
      expect(await orphan.exists(), isFalse);
    });
  });
}
