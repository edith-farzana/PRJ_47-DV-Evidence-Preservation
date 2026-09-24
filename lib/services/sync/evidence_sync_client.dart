import 'dart:io';

import '../../models/evidence/evidence_item.dart';

/// Thrown when the backend cannot be reached or is not configured.
///
/// Kept separate from a genuine rejection so the UI can say "not
/// connected" rather than "backup failed", which would be alarming and
/// wrong.
class SyncUnavailableException implements Exception {
  const SyncUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'SyncUnavailableException: $message';
}

/// An upload that reached the server and was refused, or broke part-way.
class SyncFailedException implements Exception {
  const SyncFailedException(this.message);

  final String message;

  @override
  String toString() => 'SyncFailedException: $message';
}

/// What the backend has to be able to do.
///
/// An interface, so that [EvidenceSync] -- which decides *what* is sent
/// -- can be tested without Firebase. The only implementation that
/// touches the network is `FirebaseEvidenceClient`.
abstract class EvidenceSyncClient {
  /// False when Firebase has not been configured in this build. The app
  /// must stay fully usable in that state: everything local still works.
  bool get isConfigured;

  /// Creates `/users/{uid}/evidence/{evidenceId}`.
  ///
  /// The rules deny update, so writing an id that already exists is
  /// refused by the server. Implementations treat that as "already
  /// recorded" rather than an error -- the record being immutable is
  /// the point, not a problem.
  Future<void> writeMetadata(String evidenceId, Map<String, Object?> payload);

  /// Uploads the encrypted blob to `/users/{uid}/evidence/{id}.enc`.
  Future<void> uploadBlob(String evidenceId, File blob);

  /// Creates the `/users/{uid}/backups/{evidenceId}` receipt.
  ///
  /// Written only after [uploadBlob] has completed. A receipt is a
  /// promise that a cloud copy exists, so it must never run ahead of one.
  Future<void> writeReceipt(String evidenceId, Map<String, Object?> payload);

  /// Ids that have a receipt. Used to rebuild local state.
  Future<Set<String>> backedUpIds();

  /// Reads `/users/{uid}/evidence/{evidenceId}` from the **server**.
  ///
  /// Returns null when no record exists. Throws
  /// [SyncUnavailableException] when the server cannot be reached.
  ///
  /// Implementations must not answer from a local cache. A cached copy
  /// is our own earlier write, stored on the very phone being checked,
  /// so it proves nothing about whether that phone has been tampered
  /// with.
  Future<Map<String, Object?>?> fetchMetadata(String evidenceId);
}

/// The one place the uploaded metadata map is built.
///
/// Everything here is either a hash, a wrapped key, or a number. There
/// is no filename, no path, no location and no free text: nothing that
/// identifies a person, and nothing that helps anyone read the evidence.
/// The wrapped DEK is encrypted under a master key that never leaves the
/// phone, so to Firebase it is noise.
Map<String, Object?> metadataPayload(EvidenceItem item) {
  return {
    'plaintextSha256': item.plaintextSha256,
    'ciphertextSha256': item.ciphertextSha256,
    'wrappedDek': item.wrappedDek,
    'nonce': item.nonce,
    'gcmTag': item.gcmTag,
    'capturedAt': item.capturedAt.toUtc().toIso8601String(),
    'fileSizeBytes': item.fileSizeBytes,
    'type': item.type.name,
    'encryptionAlgorithm': item.encryptionAlgorithm,
    'keyVersion': item.keyVersion,
  };
}

/// The receipt recording that a cloud copy of [item] exists.
Map<String, Object?> receiptPayload(EvidenceItem item) {
  return {
    'ciphertextSha256': item.ciphertextSha256,
    'fileSizeBytes': item.fileSizeBytes,
    'backedUpAt': DateTime.now().toUtc().toIso8601String(),
  };
}
