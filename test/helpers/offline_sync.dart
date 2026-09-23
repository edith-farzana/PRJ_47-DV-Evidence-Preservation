import 'dart:io';

import 'package:secure_evidence_app/services/sync/backup_state_store.dart';
import 'package:secure_evidence_app/services/sync/evidence_sync.dart';
import 'package:secure_evidence_app/services/sync/evidence_sync_client.dart';

import 'fake_secure_store.dart';

/// A client that is never configured, and refuses everything if asked.
///
/// Widget tests must not reach the network, and the app is required to
/// work with no backend at all -- a build without `google-services.json`
/// still captures, encrypts, lists and verifies evidence.
class _OfflineClient implements EvidenceSyncClient {
  static const _unavailable = SyncUnavailableException(
    'Firebase is not configured in tests.',
  );

  @override
  bool get isConfigured => false;

  @override
  Future<void> writeMetadata(String evidenceId, Map<String, Object?> payload) =>
      throw _unavailable;

  @override
  Future<void> uploadBlob(String evidenceId, File blob) => throw _unavailable;

  @override
  Future<void> writeReceipt(String evidenceId, Map<String, Object?> payload) =>
      throw _unavailable;

  @override
  Future<Set<String>> backedUpIds() => throw _unavailable;
}

EvidenceSync offlineSync() {
  return EvidenceSync(
    client: _OfflineClient(),
    states: BackupStateStore(FakeSecureStore()),
  );
}
