import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/services/crypto/crypto_service.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';

import '../helpers/fake_secure_store.dart';

void main() {
  // Real PBKDF2, but at a low count so the suite stays fast. The
  // production count is guarded separately below.
  const testIterations = 1000;

  late FakeSecureStore store;
  late DateTime now;

  KeyManager newManager() =>
      KeyManager(store, kdfIterations: testIterations, clock: () => now);

  Future<KeyManager> setUpManager({String pin = '1234'}) async {
    final manager = newManager();
    await manager.setUp(pin: pin, unlockSequence: '7×3-1=');
    manager.lock();
    return manager;
  }

  Future<void> failTimes(KeyManager manager, int times) async {
    for (var i = 0; i < times; i++) {
      await manager.unlock('0000');
    }
  }

  setUp(() {
    store = FakeSecureStore();
    now = DateTime(2026, 9, 18, 12);
  });

  // =================================================================
  // Setup
  // =================================================================

  group('setup', () {
    test('a fresh store is not set up', () async {
      expect(await newManager().isSetUp(), isFalse);
    });

    test(
      'setup stores the unlock sequence and leaves the vault unlocked',
      () async {
        final manager = newManager();

        await manager.setUp(pin: '1234', unlockSequence: '7×3-1=');

        expect(await manager.isSetUp(), isTrue);
        expect(await manager.unlockSequence(), '7×3-1=');
        expect(manager.isUnlocked, isTrue);
      },
    );

    test(
      'setting up twice is refused, so the master key is never orphaned',
      () async {
        final manager = await setUpManager();

        expect(
          () => manager.setUp(pin: '9999', unlockSequence: '1+1='),
          throwsStateError,
        );
      },
    );

    test('the PIN is not stored anywhere', () async {
      await setUpManager(pin: '4826');

      for (final value in store.values.values) {
        expect(value, isNot(contains('4826')));
      }
    });

    test(
      'the same PIN with a different salt gives a different stored key',
      () async {
        await setUpManager(pin: '1234');
        final first = Map.of(store.values);

        store = FakeSecureStore();
        await setUpManager(pin: '1234');

        expect(store.values['km.v1.vault'], isNot(first['km.v1.vault']));
      },
    );
  });

  // =================================================================
  // Unlock
  // =================================================================

  group('unlock', () {
    test('the correct PIN unwraps a key that decrypts evidence', () async {
      final workspace = await Directory.systemTemp.createTemp('km_test_');
      addTearDown(() => workspace.delete(recursive: true));

      final crypto = CryptoService();
      final setupManager = newManager();
      await setupManager.setUp(pin: '1234', unlockSequence: '7×3-1=');

      final source = File('${workspace.path}/evidence.txt');
      await source.writeAsString('recorded 18 Sep');

      final result = await crypto.encryptFile(
        source: source,
        destination: File('${workspace.path}/evidence.enc'),
        masterKey: setupManager.masterKey,
      );

      // A fresh manager over the same storage: a restarted app.
      final manager = newManager();
      final unlock = await manager.unlock('1234');

      expect(unlock.isSuccess, isTrue);

      final recovered = await crypto.decryptToFile(
        source: File('${workspace.path}/evidence.enc'),
        destination: File('${workspace.path}/recovered.txt'),
        masterKey: manager.masterKey,
        wrappedDek: result.wrappedDek,
        nonce: result.nonce,
        gcmTag: result.gcmTag,
        plaintextSha256: result.plaintextSha256,
      );

      expect(await recovered.readAsString(), 'recorded 18 Sep');
    });

    test('a wrong PIN fails and the vault stays locked', () async {
      final manager = await setUpManager();

      final result = await manager.unlock('9999');

      expect(result.status, UnlockStatus.wrongPin);
      expect(result.failedAttempts, 1);
      expect(manager.isUnlocked, isFalse);
      expect(() => manager.masterKey, throwsStateError);
    });

    test('lock destroys the key and masterKey throws afterwards', () async {
      final manager = await setUpManager();
      await manager.unlock('1234');

      final key = manager.masterKey;
      manager.lock();

      expect(manager.isUnlocked, isFalse);
      expect(() => manager.masterKey, throwsStateError);
      expect(() => key.extractBytes(), throwsA(anything));
    });

    test('a corrupted key record fails loudly instead of resetting', () async {
      final manager = await setUpManager();
      store.values['km.v1.vault'] = 'not json';

      expect(
        () => manager.unlock('1234'),
        throwsA(isA<KeyStoreCorruptedException>()),
      );
    });
  });

  // =================================================================
  // Lockout
  // =================================================================

  group('lockout', () {
    test('the first four failures do not lock out', () async {
      final manager = await setUpManager();

      await failTimes(manager, KeyManager.freeAttempts);

      expect(await manager.lockedUntil(), isNull);
    });

    test(
      'the fifth failure locks out and a correct PIN is then refused',
      () async {
        final manager = await setUpManager();

        await failTimes(manager, KeyManager.freeAttempts);
        final fifth = await manager.unlock('0000');

        expect(fifth.status, UnlockStatus.lockedOut);
        expect(fifth.lockedUntil, now.add(const Duration(seconds: 30)));

        final correct = await manager.unlock('1234');

        expect(correct.status, UnlockStatus.lockedOut);
        expect(manager.isUnlocked, isFalse);
      },
    );

    test('each further failure waits longer, capped at one hour', () async {
      final manager = await setUpManager();
      await failTimes(manager, KeyManager.freeAttempts);

      final waits = <Duration>[];

      for (var i = 0; i < KeyManager.lockoutSchedule.length + 2; i++) {
        final result = await manager.unlock('0000');
        final wait = result.lockedUntil!.difference(now);
        waits.add(wait);
        now = result.lockedUntil!;
      }

      for (var i = 1; i < KeyManager.lockoutSchedule.length; i++) {
        expect(waits[i], greaterThan(waits[i - 1]));
      }

      expect(waits.last, const Duration(hours: 1));
    });

    test('the lockout survives an app restart', () async {
      final manager = await setUpManager();
      await failTimes(manager, KeyManager.freeAttempts + 1);

      final restarted = newManager();

      expect(await restarted.lockedUntil(), isNotNull);
      expect((await restarted.unlock('1234')).status, UnlockStatus.lockedOut);
    });

    test('the attempt is counted before the slow key derivation', () async {
      final manager = await setUpManager();

      // Simulate the app being killed mid-derivation: the counter must
      // already be persisted by the time the KDF starts.
      final pending = manager.unlock('0000');
      await Future<void>.delayed(Duration.zero);
      expect(store.values['km.v1.failedAttempts'], '1');
      await pending;
    });

    test(
      'a correct PIN after the lockout expires unlocks and resets',
      () async {
        final manager = await setUpManager();
        await failTimes(manager, KeyManager.freeAttempts + 1);

        now = now.add(const Duration(seconds: 31));
        final result = await manager.unlock('1234');

        expect(result.isSuccess, isTrue);
        expect(store.values.containsKey('km.v1.failedAttempts'), isFalse);
        expect(await manager.lockedUntil(), isNull);
      },
    );
  });

  // =================================================================
  // Wrong PINs before a success
  //
  // The counter resets the moment the right PIN goes in. These are the
  // last chance to know someone tried, so they are handed back with the
  // success for the activity log to keep.
  // =================================================================

  group('wrong PINs before a success', () {
    test('come back with the success, then are cleared', () async {
      final manager = await setUpManager();
      final firstWrong = now;

      await manager.unlock('0000');
      now = now.add(const Duration(minutes: 1));
      await manager.unlock('1111');
      now = now.add(const Duration(minutes: 1));

      final result = await manager.unlock('1234');

      expect(result.priorFailedAttempts, 2);
      expect(result.priorFailureTimes, hasLength(2));
      expect(
        result.priorFailureTimes.first.isAtSameMomentAs(firstWrong),
        isTrue,
      );
      expect(store.values.containsKey('km.v1.failureTimes'), isFalse);

      manager.lock();
      final next = await manager.unlock('1234');

      expect(next.priorFailedAttempts, 0);
      expect(next.priorFailureTimes, isEmpty);
    });

    test('the successful attempt itself is not among them', () async {
      final manager = await setUpManager();

      final result = await manager.unlock('1234');

      expect(result.priorFailedAttempts, 0);
      expect(result.priorFailureTimes, isEmpty);
    });

    test('a guess cut off mid-derivation already has its time', () async {
      final manager = await setUpManager();

      final pending = manager.unlock('0000');
      await Future<void>.delayed(Duration.zero);

      expect(store.values['km.v1.failureTimes'], isNotNull);
      await pending;
    });

    test('only the latest times are kept; the count is not capped', () async {
      final manager = await setUpManager();
      const attempts = KeyManager.maxFailureTimes + 6;

      for (var i = 0; i < attempts; i++) {
        // Past any lockout, so every attempt is actually made.
        now = now.add(const Duration(hours: 2));
        await manager.unlock('0000');
      }

      now = now.add(const Duration(hours: 2));
      final result = await manager.unlock('1234');

      expect(result.priorFailedAttempts, attempts);
      expect(result.priorFailureTimes, hasLength(KeyManager.maxFailureTimes));
    });

    test('a wrong current PIN when changing the PIN is kept too', () async {
      final manager = await setUpManager();
      await manager.unlock('1234');

      await manager.changePin(oldPin: '0000', newPin: '5678');
      final result = await manager.changePin(oldPin: '1234', newPin: '5678');

      expect(result.isSuccess, isTrue);
      expect(result.priorFailedAttempts, 1);
      expect(result.priorFailureTimes, hasLength(1));
    });
  });

  // =================================================================
  // PIN change
  // =================================================================

  group('change PIN', () {
    test('evidence encrypted under the old PIN still decrypts', () async {
      final workspace = await Directory.systemTemp.createTemp('km_test_');
      addTearDown(() => workspace.delete(recursive: true));

      final crypto = CryptoService();
      final manager = newManager();
      await manager.setUp(pin: '1234', unlockSequence: '7×3-1=');

      final source = File('${workspace.path}/before.txt');
      await source.writeAsString('captured before the PIN change');

      final encrypted = await crypto.encryptFile(
        source: source,
        destination: File('${workspace.path}/before.enc'),
        masterKey: manager.masterKey,
      );

      final change = await manager.changePin(oldPin: '1234', newPin: '8642');
      expect(change.isSuccess, isTrue);

      final restarted = newManager();
      expect((await restarted.unlock('8642')).isSuccess, isTrue);

      final recovered = await crypto.decryptToFile(
        source: File('${workspace.path}/before.enc'),
        destination: File('${workspace.path}/after.txt'),
        masterKey: restarted.masterKey,
        wrappedDek: encrypted.wrappedDek,
        nonce: encrypted.nonce,
        gcmTag: encrypted.gcmTag,
        plaintextSha256: encrypted.plaintextSha256,
      );

      expect(await recovered.readAsString(), 'captured before the PIN change');
    });

    test('the old PIN stops working after a change', () async {
      final manager = await setUpManager();
      await manager.changePin(oldPin: '1234', newPin: '8642');
      manager.lock();

      expect((await manager.unlock('1234')).status, UnlockStatus.wrongPin);
    });

    test('a wrong old PIN changes nothing and counts toward lockout', () async {
      final manager = await setUpManager();
      final before = store.values['km.v1.vault'];

      final result = await manager.changePin(oldPin: '0000', newPin: '8642');

      expect(result.status, UnlockStatus.wrongPin);
      expect(result.failedAttempts, 1);
      expect(store.values['km.v1.vault'], before);
    });
  });

  // =================================================================
  // Guard rails
  // =================================================================

  test('production key derivation uses at least 150,000 iterations', () async {
    expect(KeyManager.defaultKdfIterations, greaterThanOrEqualTo(150000));

    // And that the default is what actually gets written.
    final manager = KeyManager(store);
    final stopwatch = Stopwatch()..start();
    await manager.setUp(pin: '1234', unlockSequence: '7×3-1=');
    stopwatch.stop();

    expect(store.values['km.v1.vault'], contains('"iterations":150000'));

    // Printed for the record; the on-device figure is what matters.
    // ignore: avoid_print
    print(
      'PBKDF2 x150,000 on this machine: ${stopwatch.elapsedMilliseconds}ms',
    );
  });
}
