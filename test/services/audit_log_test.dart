import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/audit/audit_entry.dart';
import 'package:secure_evidence_app/services/audit/audit_log.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/storage/sealed_file.dart';

import '../helpers/fake_secure_store.dart';

void main() {
  late Directory workspace;
  late FakeSecureStore store;
  late KeyManager keyManager;
  late AuditLog log;
  late DateTime now;

  AuditLog newLog() => AuditLog(
    baseDirectory: workspace,
    store: store,
    keyManager: keyManager,
    clock: () => now,
  );

  File logFile() => File('${workspace.path}/audit/log.enc');

  /// Direct access to the records under the log, to tamper with them the
  /// way someone holding the key could.
  SealedFile raw() => SealedFile(
    file: logFile(),
    store: store,
    masterKey: () => keyManager.masterKey,
    sealKey: 'audit.v1.seal',
    aad: utf8.encode('secure-evidence/audit/v1'),
    hkdfInfo: utf8.encode('audit-log/v1'),
    corrupted: AuditLogCorruptedException.new,
  );

  Future<void> recordSome(int count) async {
    for (var i = 0; i < count; i++) {
      now = now.add(const Duration(minutes: 1));
      await log.record(AuditEventType.viewed, evidenceId: 'evidence-$i');
    }
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('audit_test_');
    store = FakeSecureStore();
    now = DateTime.utc(2026, 9, 24, 10);
    // One clock for both, so wrong-PIN times can be checked exactly.
    keyManager = KeyManager(store, kdfIterations: 1000, clock: () => now);
    await keyManager.setUp(pin: '1234', unlockSequence: '7×3-1=');
    log = newLog();
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  // =================================================================
  // An intact chain
  // =================================================================

  group('an intact chain', () {
    test('verifies', () async {
      await recordSome(5);

      final report = await log.verify();

      expect(report.intact, isTrue);
      expect(report.entryCount, 5);
    });

    test('an empty log verifies', () async {
      final report = await log.verify();

      expect(report.intact, isTrue);
      expect(report.entryCount, 0);
    });

    test('the first entry anchors to the genesis value', () async {
      await recordSome(2);

      final entries = await log.entries();

      expect(entries.first.seq, 1);
      expect(entries.first.prevHash, AuditEntry.genesisHash);
      expect(entries[1].prevHash, entries.first.hash);
    });

    test('survives a restart', () async {
      await recordSome(3);

      final report = await newLog().verify();

      expect(report.intact, isTrue);
      expect(report.entryCount, 3);
    });

    test('holds no filenames or content, only what happened', () async {
      await log.record(
        AuditEventType.captured,
        evidenceId: 'evidence-1',
        detail: {'type': 'photo'},
      );

      final entry = (await log.entries()).single;

      expect(entry.toMap().keys, {
        'seq',
        'at',
        'type',
        'evidenceId',
        'detail',
        'prevHash',
        'hash',
      });
    });

    test('is encrypted on disk', () async {
      await log.record(AuditEventType.captured, evidenceId: 'evidence-1');

      final bytes = String.fromCharCodes(await logFile().readAsBytes());

      expect(bytes, isNot(contains('captured')));
      expect(bytes, isNot(contains('evidence-1')));
    });
  });

  // =================================================================
  // Tampering
  // =================================================================

  group('tampering is caught', () {
    test('editing a middle entry fails at that entry', () async {
      await recordSome(5);

      await raw().update((records) {
        records[2] = {...records[2], 'type': 'captured'};
        return records;
      });

      final report = await log.verify();

      expect(report.intact, isFalse);
      expect(report.brokenAtSeq, 3);
      expect(report.problem, contains('altered'));
    });

    test(
      'an edit that recomputes its own hash still breaks the next link',
      () async {
        await recordSome(5);

        await raw().update((records) {
          final edited = records[2];
          final hash = AuditEntry.computeHash(
            seq: edited['seq'] as int,
            at: edited['at'] as String,
            type: 'captured',
            evidenceId: edited['evidenceId'] as String?,
            detail: const {},
            prevHash: edited['prevHash'] as String,
          );
          records[2] = {...edited, 'type': 'captured', 'hash': hash};
          return records;
        });

        final report = await log.verify();

        expect(report.intact, isFalse);
        expect(report.brokenAtSeq, 4);
      },
    );

    test('deleting a middle entry fails', () async {
      await recordSome(5);

      await raw().update((records) => records..removeAt(2));

      final report = await log.verify();

      expect(report.intact, isFalse);
      expect(report.brokenAtSeq, 3);
      expect(report.problem, contains('missing'));
    });

    // The attack a chain alone misses: a shorter chain is still a valid
    // chain. The seal is what catches it.
    test('cutting entries off the end is caught', () async {
      await recordSome(5);

      final seal = store.values['audit.v1.seal']!;
      await raw().update((records) => records.sublist(0, 3));
      // The file is now a shorter chain that is valid in itself. The seal
      // in the Keystore still describes the longer one.
      store.values['audit.v1.seal'] = seal;

      final report = await log.verify();

      expect(report.intact, isFalse);
    });

    test('restoring an older copy is caught', () async {
      await recordSome(2);
      final older = await logFile().readAsBytes();

      await recordSome(3);
      await logFile().writeAsBytes(older);

      final report = await log.verify();

      expect(report.intact, isFalse);
      expect(report.problem, contains('does not match its seal'));
    });

    test(
      'a corrupted file fails loudly rather than reading as empty',
      () async {
        await recordSome(3);

        final bytes = await logFile().readAsBytes();
        bytes[bytes.length ~/ 2] ^= 0x01;
        await logFile().writeAsBytes(bytes);

        final report = await log.verify();

        expect(report.intact, isFalse);
        await expectLater(
          log.entries(),
          throwsA(isA<AuditLogCorruptedException>()),
        );
      },
    );

    test('a deleted log is caught once entries exist', () async {
      await recordSome(2);
      await logFile().delete();

      final report = await log.verify();

      expect(report.intact, isFalse);
      expect(report.problem, contains('missing'));
    });
  });

  // =================================================================
  // Events that happen while locked
  // =================================================================

  group('while locked', () {
    test('an event is kept pending, not lost', () async {
      keyManager.lock();

      await log.record(AuditEventType.panic);

      expect(store.values['audit.v1.pending'], contains('panic'));
      expect(await logFile().exists(), isFalse);
    });

    test('pending events are folded in at unlock, in time order', () async {
      keyManager.lock();

      now = DateTime.utc(2026, 9, 24, 11);
      await log.record(AuditEventType.autoLocked);
      now = DateTime.utc(2026, 9, 24, 12);
      await log.record(AuditEventType.panic);

      now = DateTime.utc(2026, 9, 24, 13);
      final result = await keyManager.unlock('1234');
      await log.onUnlocked(result);

      final types = (await log.entries()).map((entry) => entry.type);

      expect(types, ['autoLocked', 'panic', 'unlocked']);
      expect(store.values.containsKey('audit.v1.pending'), isFalse);
      expect((await log.verify()).intact, isTrue);
    });

    test(
      'wrong PINs before the unlock are recorded, with their times',
      () async {
        keyManager.lock();

        final wrongAt = [
          DateTime.utc(2026, 9, 24, 14, 2),
          DateTime.utc(2026, 9, 24, 14, 3),
        ];

        for (final time in wrongAt) {
          now = time;
          await keyManager.unlock('0000');
        }

        now = DateTime.utc(2026, 9, 24, 15);
        final result = await keyManager.unlock('1234');
        await log.onUnlocked(result);

        final entries = await log.entries();

        expect(entries.map((entry) => entry.type), [
          'unlockFailed',
          'unlockFailed',
          'unlocked',
        ]);
        expect(entries.first.time, wrongAt.first);
        expect(entries.last.detail['priorFailedAttempts'], 2);
      },
    );

    test('wrong PINs produce a notice, given out once', () async {
      keyManager.lock();
      await keyManager.unlock('0000');
      await keyManager.unlock('9999');

      await log.onUnlocked(await keyManager.unlock('1234'));

      final notice = log.takeUnlockNotice();

      expect(notice, isNotNull);
      expect(notice!.count, 2);
      expect(notice.times, hasLength(2));
      expect(log.takeUnlockNotice(), isNull);
    });

    test('a clean unlock produces no notice', () async {
      keyManager.lock();

      await log.onUnlocked(await keyManager.unlock('1234'));

      expect(log.takeUnlockNotice(), isNull);
    });

    test('the pending list is capped', () async {
      keyManager.lock();

      for (var i = 0; i < AuditLog.maxPending + 25; i++) {
        now = now.add(const Duration(seconds: 1));
        await log.record(AuditEventType.autoLocked);
      }

      final pending = jsonDecode(store.values['audit.v1.pending']!) as List;

      expect(pending, hasLength(AuditLog.maxPending));
    });

    // A panic can land while an unlock is still folding the pending list
    // in. Whatever path that takes, nothing may be lost: not the panic,
    // not what was pending, and not the unlock itself -- whose wrong-PIN
    // record the key manager has already cleared.
    test('a panic in the middle of an unlock loses nothing', () async {
      keyManager.lock();
      await log.record(AuditEventType.autoLocked);

      final folding = log.onUnlocked(await keyManager.unlock('1234'));

      keyManager.lock();
      await log.record(AuditEventType.panic);
      await folding;

      await log.onUnlocked(await keyManager.unlock('1234'));

      final types = (await log.entries()).map((entry) => entry.type).toList();

      expect(types, containsAll(['autoLocked', 'panic']));
      expect(types.where((type) => type == 'unlocked'), hasLength(2));
      expect((await log.verify()).intact, isTrue);
    });
  });
}
