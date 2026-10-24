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
    this._onRecorded,
  });

  final EvidenceSyncClient _client;
  final BackupStateStore _states;

  /// Overridable so tests can drive both states; in the app it is
  /// [cloudFileBackupEnabled].
  final bool _fileBackupEnabled;

  /// Told each id whose record has just reached the server. The app
  /// writes it to the activity log (see `main.dart`), so the entry is
  /// there whichever moment sent the record: capture, unlock or vault.
  final Future<void> Function(String evidenceId)? _onRecorded;

  /// Ids whose record is being written right now.
  ///
  /// A capture, an unlock and the vault can all reach for the same item
  /// at once. Offline, Firestore holds a write open until the signal
  /// returns, so without this a second call would queue a duplicate
  /// write behind the first.
  final Set<String> _inFlight = {};

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
  /// The one place a record is sent from. Three moments call it, so a
  /// capture made with no signal still gets its record without anyone
  /// having to remember to open the vault:
  ///
  ///  * straight after a capture, through [recordCaptured];
  ///  * at every unlock, through [catchUp];
  ///  * whenever the vault is opened.
  ///
  /// A failure here is not shown to the user -- being offline is
  /// ordinary, and the evidence is already safe on the phone. The item
  /// stays pending for the next of those moments.
  ///
  /// [keepGoing] is asked before each write; once it says no, nothing
  /// more is started. A write already on its way is left to finish.
  ///
  /// Returns the ids whose record reached the server on this call.
  Future<List<String>> syncPendingMetadata(
    List<EvidenceItem> items, {
    bool Function()? keepGoing,
  }) async {
    if (!_client.isConfigured) return const [];

    final recorded = <String>[];

    for (final item in items) {
      if (keepGoing != null && !keepGoing()) break;

      if (_states.recordFor(item.id).metadataSynced) continue;

      // Already being sent by another call.
      if (!_inFlight.add(item.id)) continue;

      try {
        await _client.writeMetadata(item.id, metadataPayload(item));

        // Read again rather than reuse the record from before the write,
        // which may have taken hours: a backup may have changed it since.
        await _states.save(
          item.id,
          _states.recordFor(item.id).copyWith(metadataSynced: true),
        );

        recorded.add(item.id);
      } catch (error) {
        debugPrint('Metadata for ${item.id} not recorded yet: $error');
      } finally {
        _inFlight.remove(item.id);
      }
    }

    if (recorded.isNotEmpty) {
      notifyListeners();

      await _announce(recorded);
    }

    return recorded;
  }

  /// Sends [item]'s record straight after it has been captured.
  ///
  /// The capture screens start this and do not wait for it (see
  /// `saveCapture`): by now the evidence is safe on the phone, and with
  /// no signal the write may not finish for hours. If it fails, or never
  /// gets the chance, the next unlock or vault visit sends it.
  ///
  /// Never throws.
  Future<void> recordCaptured(EvidenceItem item) async {
    try {
      await syncPendingMetadata([item]);
    } catch (error) {
      debugPrint('Metadata for ${item.id} not recorded at capture: $error');
    }
  }

  /// Sends every record still missing from the server.
  ///
  /// Called at each unlock (see `main.dart`), so a capture made offline
  /// is recorded the next time the app is opened, whether or not the
  /// vault is. Never before an unlock: an app that contacts Google while
  /// it is still a calculator would give itself away.
  ///
  /// [loadItems] decrypts the evidence index, so it is only called when
  /// there is a server to send to. [keepGoing] is as for
  /// [syncPendingMetadata]; the app passes whether the vault is still
  /// unlocked, so a panic stops new writes.
  ///
  /// Never throws, and nothing should wait for it: neither an unlock nor
  /// a panic may be held up by the network.
  Future<void> catchUp(
    Future<List<EvidenceItem>> Function() loadItems, {
    bool Function()? keepGoing,
  }) async {
    try {
      if (!_client.isConfigured) return;
      if (keepGoing != null && !keepGoing()) return;

      await syncPendingMetadata(await loadItems(), keepGoing: keepGoing);
    } catch (error) {
      // An index that cannot be read is reported by the vault screen.
      // Here it only means there is nothing to send this time.
      debugPrint('Metadata catch-up did not run: $error');
    }
  }

  /// Passes newly recorded ids to [_onRecorded], one at a time and in
  /// order. A failure there is not a failure to record.
  Future<void> _announce(List<String> ids) async {
    final onRecorded = _onRecorded;

    if (onRecorded == null) return;

    for (final id in ids) {
      try {
        await onRecorded(id);
      } catch (error) {
        debugPrint('Could not note that $id was recorded: $error');
      }
    }
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
