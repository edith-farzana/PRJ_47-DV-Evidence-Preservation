import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/app/app_lock_controller.dart';
import 'package:secure_evidence_app/features/evidence/capture/save_capture.dart';
import 'package:secure_evidence_app/models/audit/audit_entry.dart';
import 'package:secure_evidence_app/models/evidence/backup_state.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/models/evidence/server_check.dart';
import 'package:secure_evidence_app/services/audit/audit_log.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/storage/evidence_storage.dart';
import 'package:secure_evidence_app/services/sync/backup_state_store.dart';
import 'package:secure_evidence_app/services/sync/evidence_sync.dart';
import 'package:secure_evidence_app/services/sync/evidence_sync_client.dart';

import '../helpers/fake_secure_store.dart';
import '../helpers/offline_sync.dart';

/// Records what was sent, in what order, without a network.
class _FakeClient implements EvidenceSyncClient {
  /// Every call, in order: `metadata:id`, `blob:id`, `receipt:id`.
  final List<String> calls = [];

  final List<Map<String, Object?>> payloads = [];

  Set<String> remoteReceipts = {};

  bool configured = true;
  bool uploadsFail = false;

  /// No signal: every write is refused, as the real client refuses when
  /// it cannot sign in or reach Firestore.
  bool offline = false;

  /// While set, writes wait on it: a server that has not answered yet.
  /// Offline, Firestore holds a write open like this until the signal
  /// returns.
  Completer<void>? holdWrites;

  /// Every write tried, including those refused or still waiting.
  int writeAttempts = 0;

  List<String> get metadataWrites => _ids('metadata');
  List<String> get blobUploads => _ids('blob');
  List<String> get receipts => _ids('receipt');

  List<String> _ids(String kind) => calls
      .where((call) => call.startsWith('$kind:'))
      .map((call) => call.split(':').last)
      .toList();

  @override
  bool get isConfigured => configured;

  @override
  Future<void> writeMetadata(
    String evidenceId,
    Map<String, Object?> payload,
  ) async {
    writeAttempts++;

    if (offline) {
      throw const SyncUnavailableException('there is no internet connection.');
    }

    await holdWrites?.future;

    calls.add('metadata:$evidenceId');
    payloads.add(payload);
  }

  @override
  Future<void> uploadBlob(String evidenceId, File blob) async {
    if (uploadsFail) {
      throw const SyncFailedException('no signal');
    }

    calls.add('blob:$evidenceId');
  }

  @override
  Future<void> writeReceipt(
    String evidenceId,
    Map<String, Object?> payload,
  ) async {
    calls.add('receipt:$evidenceId');
  }

  @override
  Future<Set<String>> backedUpIds() async => remoteReceipts;

  /// What the server holds, by evidence id. Absent means no record.
  final Map<String, Map<String, Object?>> serverRecords = {};

  bool serverUnreachable = false;

  @override
  Future<Map<String, Object?>?> fetchMetadata(String evidenceId) async {
    calls.add('fetch:$evidenceId');

    if (serverUnreachable) {
      throw const SyncUnavailableException('there is no internet connection.');
    }

    return serverRecords[evidenceId];
  }
}

/// A client whose read fails in a way nobody planned for.
class _BrokenFetchClient extends _FakeClient {
  @override
  Future<Map<String, Object?>?> fetchMetadata(String evidenceId) async {
    throw StateError('unexpected');
  }
}

/// A client whose write blows up in a way nobody planned for -- before
/// it has even returned a future -- until [broken] is cleared.
class _BrokenWriteClient extends _FakeClient {
  bool broken = true;

  @override
  Future<void> writeMetadata(String evidenceId, Map<String, Object?> payload) {
    if (broken) {
      writeAttempts++;
      throw StateError('unexpected');
    }

    return super.writeMetadata(evidenceId, payload);
  }
}

/// Lets work that was started and not awaited run to its next real wait.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits for background work that does real file I/O, which [settle]
/// cannot see the end of. Fails rather than hanging.
Future<void> eventually(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));

  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting.');

    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory workspace;
  late _FakeClient client;
  late EvidenceSync sync;

  Future<EvidenceItem> makeItem(String id) async {
    final blob = File('${workspace.path}/$id.enc');

    await blob.writeAsBytes([1, 2, 3, 4]);

    return EvidenceItem(
      id: id,
      type: EvidenceType.photo,
      filePath: blob.path,
      originalFileName: 'private-photo.jpg',
      capturedAt: DateTime.utc(2026, 9, 21, 10),
      fileSizeBytes: 4,
      plaintextSha256: 'a' * 64,
      ciphertextSha256: 'b' * 64,
      wrappedDek: 'd3JhcHBlZA==',
      nonce: 'bm9uY2U=',
      gcmTag: 'dGFn',
      encryptionAlgorithm: 'AES-256-GCM',
      keyVersion: 1,
    );
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('sync_test_');

    client = _FakeClient();

    // Most of these cases describe how backup behaves once Storage is
    // switched on. The group at the end covers it switched off, which
    // is how the app actually ships today.
    sync = EvidenceSync(
      client: client,
      states: BackupStateStore(FakeSecureStore()),
      fileBackupEnabled: true,
    );

    await sync.load();
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  group('metadata', () {
    test('is recorded for every item, backed up or not', () async {
      final items = [await makeItem('one'), await makeItem('two')];

      await sync.syncPendingMetadata(items);

      expect(client.metadataWrites, ['one', 'two']);
    });

    test('is not sent twice for the same item', () async {
      final items = [await makeItem('one')];

      await sync.syncPendingMetadata(items);
      await sync.syncPendingMetadata(items);

      expect(client.metadataWrites, ['one']);
    });

    test('carries no filename, path or plaintext', () async {
      await sync.syncPendingMetadata([await makeItem('one')]);

      final payload = client.payloads.single;

      expect(payload.containsKey('originalFileName'), isFalse);
      expect(payload.containsKey('filePath'), isFalse);

      final serialised = payload.values.join(' ');

      expect(serialised, isNot(contains('private-photo')));
      expect(serialised, isNot(contains(workspace.path)));

      // What it must carry, for the record to prove anything.
      expect(payload['plaintextSha256'], 'a' * 64);
      expect(payload['wrappedDek'], isNotNull);
    });
  });

  group('the opt-in rule', () {
    // The load-bearing test for the whole "media stays local" decision.
    test('no blob is uploaded unless backup is asked for', () async {
      final items = [await makeItem('one'), await makeItem('two')];

      await sync.syncPendingMetadata(items);

      expect(client.blobUploads, isEmpty);
      expect(client.receipts, isEmpty);
      expect(sync.stateOf('one'), BackupState.localOnly);
    });

    test('backing one item up leaves the others local', () async {
      final one = await makeItem('one');
      final two = await makeItem('two');

      await sync.syncPendingMetadata([one, two]);
      await sync.backUp(one);

      expect(client.blobUploads, ['one']);
      expect(sync.stateOf('two'), BackupState.localOnly);
    });
  });

  group('backing up one item', () {
    test('sends metadata, then the blob, then the receipt', () async {
      final item = await makeItem('one');

      await sync.backUp(item);

      expect(client.calls, ['metadata:one', 'blob:one', 'receipt:one']);
      expect(sync.stateOf('one'), BackupState.backedUp);
    });

    test('a failed upload writes no receipt and reports failure', () async {
      final item = await makeItem('one');

      client.uploadsFail = true;

      await expectLater(sync.backUp(item), throwsA(isA<SyncFailedException>()));

      expect(client.receipts, isEmpty);
      expect(sync.stateOf('one'), BackupState.failed);
    });

    test('a missing blob fails before anything is sent', () async {
      final item = await makeItem('one');

      await File(item.filePath).delete();

      await expectLater(sync.backUp(item), throwsA(isA<SyncFailedException>()));

      expect(client.calls, isEmpty);
    });

    test('nothing is sent when Firebase is not configured', () async {
      client.configured = false;

      await expectLater(
        sync.backUp(await makeItem('one')),
        throwsA(isA<SyncUnavailableException>()),
      );

      expect(client.calls, isEmpty);
    });
  });

  group('back up all', () {
    test('uploads everything that has no cloud copy', () async {
      final items = [
        await makeItem('one'),
        await makeItem('two'),
        await makeItem('three'),
      ];

      final uploaded = await sync.backUpAll(items);

      expect(uploaded, 3);
      expect(client.blobUploads, ['one', 'two', 'three']);
    });

    test('skips items that are already backed up', () async {
      final one = await makeItem('one');
      final two = await makeItem('two');

      await sync.backUp(one);

      final uploaded = await sync.backUpAll([one, two]);

      expect(uploaded, 1);
      expect(client.blobUploads, ['one', 'two']);
    });

    test('one failure does not stop the rest', () async {
      final items = [await makeItem('one'), await makeItem('two')];

      await File(items.first.filePath).delete();

      final uploaded = await sync.backUpAll(items);

      expect(uploaded, 1);
      expect(sync.stateOf('one'), BackupState.failed);
      expect(sync.stateOf('two'), BackupState.backedUp);
    });
  });

  group('cloud file backup switched off', () {
    late EvidenceSync offline;

    setUp(() async {
      offline = EvidenceSync(
        client: client,
        states: BackupStateStore(FakeSecureStore()),
        fileBackupEnabled: false,
      );

      await offline.load();
    });

    test('reports itself unavailable', () {
      expect(offline.cloudFileBackupAvailable, isFalse);
    });

    test('backing up refuses, and sends nothing', () async {
      await expectLater(
        offline.backUp(await makeItem('one')),
        throwsA(isA<SyncUnavailableException>()),
      );

      expect(client.calls, isEmpty);
    });

    // The item is fine. Badging it FAILED would tell a survivor her
    // evidence is at risk when only the upload is unavailable.
    test('the item stays local-only, and is never marked failed', () async {
      final item = await makeItem('one');

      await expectLater(offline.backUp(item), throwsA(anything));

      expect(offline.stateOf('one'), BackupState.localOnly);
      expect(offline.stateOf('one'), isNot(BackupState.failed));
    });

    test('back up all does nothing and reports nothing done', () async {
      final items = [await makeItem('one'), await makeItem('two')];

      expect(await offline.backUpAll(items), 0);
      expect(client.calls, isEmpty);
    });

    // The half that works has to keep working: this is the record that
    // makes a later deletion provable.
    test('metadata still reaches the server', () async {
      final items = [await makeItem('one'), await makeItem('two')];

      await offline.syncPendingMetadata(items);

      expect(client.metadataWrites, ['one', 'two']);
      expect(client.blobUploads, isEmpty);
    });
  });

  group('cross-checking against the server record', () {
    /// The record as this phone uploaded it, optionally with one field
    /// changed -- standing in for a local record that was altered after
    /// the server copy was made.
    Map<String, Object?> recordFor(
      EvidenceItem item, {
      Map<String, Object?> altered = const {},
    }) => {...metadataPayload(item), ...altered};

    test('matches when the server holds what was uploaded', () async {
      final item = await makeItem('one');
      client.serverRecords['one'] = recordFor(item);

      final check = await sync.checkServerRecord(item);

      expect(check.status, ServerCheckStatus.matches);
      expect(check.serverPlaintextSha256, item.plaintextSha256);
    });

    test('a different evidence fingerprint is a mismatch', () async {
      final item = await makeItem('one');
      client.serverRecords['one'] = recordFor(
        item,
        altered: {'plaintextSha256': 'c' * 64},
      );

      final check = await sync.checkServerRecord(item);

      expect(check.status, ServerCheckStatus.mismatch);
      expect(check.mismatchedFields, ['plaintextSha256']);
    });

    test('a different stored-file fingerprint is a mismatch', () async {
      final item = await makeItem('one');
      client.serverRecords['one'] = recordFor(
        item,
        altered: {'ciphertextSha256': 'c' * 64},
      );

      final check = await sync.checkServerRecord(item);

      expect(check.mismatchedFields, ['ciphertextSha256']);
    });

    // When evidence existed is half of what the server record proves.
    test('a moved capture time is a mismatch', () async {
      final item = await makeItem('one');
      client.serverRecords['one'] = recordFor(
        item,
        altered: {'capturedAt': '2026-09-01T10:00:00.000Z'},
      );

      final check = await sync.checkServerRecord(item);

      expect(check.status, ServerCheckStatus.mismatch);
      expect(check.mismatchedFields, ['capturedAt']);
    });

    test('every disagreeing field is reported', () async {
      final item = await makeItem('one');
      client.serverRecords['one'] = recordFor(
        item,
        altered: {
          'plaintextSha256': 'c' * 64,
          'capturedAt': '2026-09-01T10:00:00.000Z',
        },
      );

      final check = await sync.checkServerRecord(item);

      expect(check.mismatchedFields, ['plaintextSha256', 'capturedAt']);
    });

    test('no record on the server is reported as such', () async {
      final check = await sync.checkServerRecord(await makeItem('one'));

      expect(check.status, ServerCheckStatus.notOnServer);
      expect(check.reached, isFalse);
    });

    test('an unreachable server is unavailable, not a failure', () async {
      client.serverUnreachable = true;

      final check = await sync.checkServerRecord(await makeItem('one'));

      expect(check.status, ServerCheckStatus.unavailable);
      expect(check.reason, contains('internet'));
      expect(check.disagrees, isFalse);
    });

    // A bug in the check must never accuse anyone of tampering.
    test('an unexpected error is unavailable, never a mismatch', () async {
      final broken = EvidenceSync(
        client: _BrokenFetchClient(),
        states: BackupStateStore(FakeSecureStore()),
      );

      final check = await broken.checkServerRecord(await makeItem('one'));

      expect(check.status, ServerCheckStatus.unavailable);
    });

    test('without Firebase, nothing is contacted at all', () async {
      client.configured = false;

      final check = await sync.checkServerRecord(await makeItem('one'));

      expect(check.status, ServerCheckStatus.unavailable);
      expect(client.calls, isEmpty);
    });

    // The check must not create a record where there is none. A tampered
    // local record would otherwise be written to the server as if it were
    // the original -- laundering the very thing the check exists to catch.
    test('a check only ever reads', () async {
      final item = await makeItem('one');

      await sync.checkServerRecord(item);

      expect(client.calls, ['fetch:one']);
      expect(client.metadataWrites, isEmpty);
    });
  });

  group('reconciling with the server', () {
    test('receipts on the server mark items as backed up', () async {
      await sync.syncPendingMetadata([await makeItem('one')]);

      expect(sync.stateOf('one'), BackupState.localOnly);

      client.remoteReceipts = {'one'};

      await sync.reconcile();

      expect(sync.stateOf('one'), BackupState.backedUp);
    });

    test('counts what still has no cloud copy', () async {
      final items = [await makeItem('one'), await makeItem('two')];

      await sync.backUp(items.first);

      expect(sync.notBackedUp(items), 1);
    });
  });

  // The server record is what makes a later deletion provable, so it
  // must not depend on the vault being opened. These run a real capture
  // through `saveCapture`, the path both capture screens take, and an
  // unlock wired the way main.dart wires it.
  group('recording at capture and at unlock', () {
    late FakeSecureStore store;
    late KeyManager keyManager;
    late EvidenceStorage storage;
    late AuditLog audit;

    /// Ids the service reported recorded, in order -- what the app
    /// writes to the activity log.
    late List<String> announced;

    /// The service as main.dart builds it, around [withClient].
    Future<EvidenceSync> appSync(EvidenceSyncClient withClient) async {
      final built = EvidenceSync(
        client: withClient,
        states: BackupStateStore(store),
        onRecorded: (id) async {
          await audit.record(AuditEventType.recordedOnServer, evidenceId: id);
          announced.add(id);
        },
      );

      await built.load();

      return built;
    }

    /// A capture, through the path both capture screens take.
    Future<EvidenceItem> capture(
      EvidenceSync through, {
      String name = 'photo.jpg',
    }) async {
      final source = File('${workspace.path}/capture/$name');

      await source.parent.create(recursive: true);
      await source.writeAsBytes(List<int>.generate(2048, (i) => i % 251));

      return saveCapture(
        storage: storage,
        audit: audit,
        sync: through,
        source: source,
        type: EvidenceType.photo,
        originalFileName: name,
      );
    }

    /// Locks, then unlocks with the PIN through a controller wired as in
    /// main.dart. Returns the controller, so a test can panic.
    Future<AppLockController> lockAndUnlock(EvidenceSync through) async {
      keyManager.lock();

      final controller = AppLockController(
        keyManager: keyManager,
        store: store,
        afterUnlock: () => through.catchUp(
          storage.getEvidence,
          keepGoing: () => keyManager.isUnlocked,
        ),
      );

      final result = await keyManager.unlock('1234');

      controller
        ..showPin()
        ..unlocked(result);

      return controller;
    }

    setUp(() async {
      store = FakeSecureStore();
      keyManager = KeyManager(store, kdfIterations: 1000);
      await keyManager.setUp(pin: '1234', unlockSequence: '7×3-1=');

      storage = EvidenceStorage(
        baseDirectory: workspace,
        keyManager: keyManager,
        store: store,
      );

      audit = AuditLog(
        baseDirectory: workspace,
        store: store,
        keyManager: keyManager,
      );

      announced = [];
    });

    tearDown(() async {
      // The capture's log entry is written in the background. Reading the
      // log queues behind it, so the workspace is not deleted mid-write.
      try {
        await audit.entries();
      } catch (_) {
        // Locked by a test that panicked: nothing to wait for.
      }
    });

    test('a capture is recorded on the server straight away', () async {
      final sync = await appSync(client);

      final item = await capture(sync);

      await eventually(() => announced.isNotEmpty);

      expect(client.metadataWrites, [item.id]);
      expect(announced, [item.id]);

      // Metadata only: exactly what metadataPayload builds -- hashes, the
      // wrapped key, a time and a size. Never the file name.
      expect(client.payloads.single, metadataPayload(item));
      expect(
        client.payloads.single.values.join(' '),
        isNot(contains('photo.jpg')),
      );
    });

    test(
      'the activity log shows the capture, then the server record',
      () async {
        final sync = await appSync(client);

        final item = await capture(sync);

        await eventually(() => announced.isNotEmpty);

        final history = (await audit.entries())
            .where((entry) => entry.evidenceId == item.id)
            .map((entry) => entry.type)
            .toList();

        expect(history, ['captured', 'recordedOnServer']);
      },
    );

    test(
      'a capture made with no signal is recorded at the next unlock',
      () async {
        client.offline = true;
        final sync = await appSync(client);

        final item = await capture(sync);
        await settle();

        // Tried at capture, and refused.
        expect(client.writeAttempts, 1);
        expect(client.metadataWrites, isEmpty);

        // The vault is never opened. The signal comes back, and later she
        // unlocks the app again.
        client.offline = false;
        await lockAndUnlock(sync);

        await eventually(() => announced.isNotEmpty);

        expect(client.metadataWrites, [item.id]);
        expect(announced, [item.id]);
      },
    );

    test('a failure while recording never fails the capture', () async {
      final broken = _BrokenWriteClient();
      final sync = await appSync(broken);

      final item = await capture(sync);
      await settle();

      // Saved and listed, although the write blew up. An error escaping
      // into the test zone would already have failed this test.
      expect((await storage.getEvidence()).map((e) => e.id), [item.id]);
      expect(broken.writeAttempts, 1);

      // Still pending, so the next unlock sends it.
      broken.broken = false;
      await lockAndUnlock(sync);

      await eventually(() => announced.isNotEmpty);

      expect(broken.metadataWrites, [item.id]);
    });

    test('a server that never answers does not hold up the capture', () async {
      client.holdWrites = Completer<void>();
      final sync = await appSync(client);

      // Times out, failing the test, if the capture waits for the server.
      final item = await capture(sync).timeout(const Duration(seconds: 10));

      expect((await storage.getEvidence()).map((e) => e.id), [item.id]);
      expect(client.writeAttempts, 1);
      expect(client.metadataWrites, isEmpty);

      // The signal returns, and the write that was waiting lands.
      client.holdWrites!.complete();

      await eventually(() => announced.isNotEmpty);

      expect(client.metadataWrites, [item.id]);
    });

    test('capture, unlock and vault at once send the record once', () async {
      client.holdWrites = Completer<void>();
      final sync = await appSync(client);

      final item = await capture(sync);

      // The capture's write is still waiting when the other two arrive.
      await sync.catchUp(storage.getEvidence);
      await sync.syncPendingMetadata([item]);

      expect(client.writeAttempts, 1);

      client.holdWrites!.complete();

      await eventually(() => announced.isNotEmpty);
      await settle();

      expect(client.metadataWrites, [item.id]);
      expect(announced, [item.id]);
    });

    test('a panic during the unlock catch-up stops new writes', () async {
      client.offline = true;
      final sync = await appSync(client);

      for (final name in ['a.jpg', 'b.jpg', 'c.jpg']) {
        await capture(sync, name: name);
      }
      await settle();

      expect(client.writeAttempts, 3);

      client
        ..offline = false
        ..holdWrites = Completer<void>();

      final controller = await lockAndUnlock(sync);

      await eventually(() => client.writeAttempts == 4);

      // Panic, with one write on its way.
      controller.lock();

      client.holdWrites!.complete();

      await eventually(() => announced.isNotEmpty);
      await settle();

      // The write already sent was allowed to land; nothing new started.
      expect(client.writeAttempts, 4);
      expect(client.metadataWrites, hasLength(1));
    });

    test('the catch-up sends nothing while the app is locked', () async {
      client.offline = true;
      final sync = await appSync(client);

      await capture(sync);
      await settle();

      client.offline = false;
      keyManager.lock();

      var loaded = false;

      await sync.catchUp(() async {
        loaded = true;
        return storage.getEvidence();
      }, keepGoing: () => keyManager.isUnlocked);

      // Only the attempt made at capture, while unlocked.
      expect(client.writeAttempts, 1);
      expect(loaded, isFalse);
    });

    test(
      'without Firebase a capture still saves, and nothing is tried',
      () async {
        final sync = offlineSync();

        final item = await capture(sync);
        await settle();

        expect((await storage.getEvidence()).map((e) => e.id), [item.id]);

        // The index is not even decrypted when there is nowhere to send.
        var loaded = false;

        await sync.catchUp(() async {
          loaded = true;
          return const <EvidenceItem>[];
        });

        expect(loaded, isFalse);
      },
    );
  });
}
