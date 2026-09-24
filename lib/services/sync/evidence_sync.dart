import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/evidence/backup_state.dart';
import '../../models/evidence/evidence_item.dart';
import '../../models/evidence/server_check.dart';
import 'backup_state_store.dart';
import 'evidence_sync_client.dart';
import 'sync_config.dart';

/// Decides what leaves the phone, and in what order.
///
/// The rule this class exists to enforce:
///
///  * **Metadata goes up for every item.** Hashes, the wrapped key, a
///    timestamp and a size. That immutable record is what makes a later
///    deletion or alteration provable, and it reveals nothing.
///  * **The encrypted blob goes up only when the survivor says so**,
///    per item. Nothing here may upload a file on its own.
///
/// No Firebase import: everything goes through [EvidenceSyncClient], so
/// these decisions are testable with a fake.
class EvidenceSync extends ChangeNotifier {
  EvidenceSync({
    required this._client,
    required this._states,
    this._fileBackupEnabled = cloudFileBackupEnabled,
  });

  final EvidenceSyncClient _client;
  final BackupStateStore _states;

  /// Overridable so tests can drive both states; in the app it is
  /// [cloudFileBackupEnabled].
  final bool _fileBackupEnabled;

  bool get isConfigured => _client.isConfigured;

  /// Whether an encrypted copy can actually be uploaded.
  ///
  /// False while Firebase Storage is switched off. Metadata sync is
  /// unaffected — see [cloudFileBackupEnabled] for what that means.
  bool get cloudFileBackupAvailable =>
      _fileBackupEnabled && _client.isConfigured;

  /// Loads local state. Contacts nothing.
  Future<void> load() => _states.load();

  BackupState stateOf(String evidenceId) => _states.recordFor(evidenceId).state;

  bool isBackedUp(String evidenceId) =>
      stateOf(evidenceId) == BackupState.backedUp;

  /// How many of [items] have no cloud copy yet.
  int notBackedUp(List<EvidenceItem> items) {
    return items.where((item) => !isBackedUp(item.id)).length;
  }

  /// Records every item that has not reached Firestore yet.
  ///
  /// Called when the vault is opened rather than at capture time: a
  /// capture may happen with no signal, and this way the record catches
  /// up by itself. A failure here is not shown to the user -- being
  /// offline is ordinary, and the evidence is already safe on the phone.
  Future<void> syncPendingMetadata(List<EvidenceItem> items) async {
    if (!_client.isConfigured) return;

    var changed = false;

    for (final item in items) {
      final record = _states.recordFor(item.id);

      if (record.metadataSynced) continue;

      try {
        await _client.writeMetadata(item.id, metadataPayload(item));

        await _states.save(item.id, record.copyWith(metadataSynced: true));

        changed = true;
      } catch (error) {
        debugPrint('Metadata for ${item.id} not recorded yet: $error');
      }
    }

    if (changed) notifyListeners();
  }

  /// Uploads the encrypted blob for [item], then writes its receipt.
  ///
  /// Throws so the screen that asked can say what went wrong. The local
  /// evidence is never touched by a failure here.
  Future<void> backUp(EvidenceItem item) async {
    // Checked before anything else, and before any state is written:
    // an upload that cannot succeed must not leave the item badged
    // BACKUP FAILED. Nothing is wrong with her evidence -- the
    // capability simply is not switched on.
    if (!cloudFileBackupAvailable) {
      throw const SyncUnavailableException(
        'Keeping a cloud copy of the file is not switched on yet. The '
        'record proving this evidence exists has still been saved.',
      );
    }

    final blob = File(item.filePath);

    if (!await blob.exists()) {
      // Recorded as failed, unlike the case above. The difference is
      // whether a backup was actually attempted: being switched off is
      // refused up front and changes nothing, while a missing file
      // means she asked, it did not happen, and something is wrong
      // that she needs to see.
      await _setState(item.id, BackupState.failed);

      throw SyncFailedException(
        'The encrypted file for this evidence is missing.',
      );
    }

    await _setState(item.id, BackupState.uploading);

    try {
      // Metadata first: the record that proves the evidence existed
      // matters more than the copy, and it is what the receipt hangs off.
      final record = _states.recordFor(item.id);

      if (!record.metadataSynced) {
        await _client.writeMetadata(item.id, metadataPayload(item));

        await _states.save(item.id, record.copyWith(metadataSynced: true));
      }

      await _client.uploadBlob(item.id, blob);

      // Only now: a receipt promises a cloud copy exists.
      await _client.writeReceipt(item.id, receiptPayload(item));

      await _setState(item.id, BackupState.backedUp);
    } catch (error) {
      await _setState(item.id, BackupState.failed);

      rethrow;
    }
  }

  /// Backs up everything that does not already have a cloud copy.
  ///
  /// One failure does not stop the rest: returns how many succeeded, so
  /// the caller can report honestly on a partial run.
  Future<int> backUpAll(List<EvidenceItem> items) async {
    if (!cloudFileBackupAvailable) {
      return 0;
    }

    var uploaded = 0;

    for (final item in items) {
      if (isBackedUp(item.id)) continue;

      try {
        await backUp(item);
        uploaded++;
      } catch (error) {
        debugPrint('Backing up ${item.id} failed: $error');
      }
    }

    return uploaded;
  }

  /// Compares [item] with the server's record of it.
  ///
  /// **Read-only, by construction.** If there is no server record, this
  /// does not create one: a tampered local record would then be written
  /// to the server as if it were the original, and the check would
  /// launder the very thing it exists to catch.
  ///
  /// Never throws. Every way the server can fail to answer is reported
  /// as [ServerCheckStatus.unavailable] -- neutral, because not reaching
  /// the server says nothing about the evidence.
  Future<ServerCheck> checkServerRecord(EvidenceItem item) async {
    if (!_client.isConfigured) {
      return const ServerCheck.unavailable(
        'Firebase is not set up in this build.',
      );
    }

    final Map<String, Object?>? server;

    try {
      server = await _client.fetchMetadata(item.id);
    } on SyncUnavailableException catch (error) {
      return ServerCheck.unavailable(error.message);
    } catch (error) {
      // An unexpected failure is reported as "not reached", never as
      // tampering: a bug here must not accuse anyone.
      return ServerCheck.unavailable('$error');
    }

    if (server == null) {
      return const ServerCheck.notOnServer();
    }

    // What this phone would have uploaded for this item, built by the same
    // function that uploaded it -- so the two cannot drift apart.
    final expected = metadataPayload(item);

    final mismatched = [
      for (final field in serverCheckedFields)
        if (server[field] != expected[field]) field,
    ];

    final serverHash = server['plaintextSha256'] as String?;

    if (mismatched.isEmpty) {
      return ServerCheck.matches(serverPlaintextSha256: serverHash);
    }

    return ServerCheck.mismatch(
      fields: mismatched,
      serverPlaintextSha256: serverHash,
    );
  }

  /// Rebuilds local state from the receipts on the server, which are
  /// the authority for what has a cloud copy.
  Future<void> reconcile() async {
    if (!_client.isConfigured) return;

    try {
      await _states.reconcile(await _client.backedUpIds());

      notifyListeners();
    } catch (error) {
      debugPrint('Could not reconcile backups: $error');
    }
  }

  Future<void> _setState(String evidenceId, BackupState state) async {
    await _states.save(
      evidenceId,
      _states.recordFor(evidenceId).copyWith(state: state),
    );

    notifyListeners();
  }
}
