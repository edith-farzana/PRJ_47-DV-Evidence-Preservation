import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/evidence/backup_state.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
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

    sync = EvidenceSync(
      client: client,
      states: BackupStateStore(FakeSecureStore()),
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
