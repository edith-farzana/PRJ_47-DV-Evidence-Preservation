import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/evidence/backup_state.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/models/evidence/server_check.dart';
import 'package:secure_evidence_app/services/sync/backup_state_store.dart';
import 'package:secure_evidence_app/services/sync/evidence_sync.dart';
import 'package:secure_evidence_app/services/sync/evidence_sync_client.dart';

import '../helpers/fake_secure_store.dart';

/// Records what was sent, in what order, without a network.
class _FakeClient implements EvidenceSyncClient {
  /// Every call, in order: `metadata:id`, `blob:id`, `receipt:id`.
  final List<String> calls = [];

  final List<Map<String, Object?>> payloads = [];

  Set<String> remoteReceipts = {};

  bool configured = true;
  bool uploadsFail = false;

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
}
