import 'dart:convert';

import '../../models/evidence/backup_state.dart';
import '../crypto/secure_store.dart';

/// Local sync state for every item, as one record in [SecureStore].
///
/// Deliberately **not** kept in the encrypted evidence index.
/// `EvidenceIndex` exposes `append` and nothing else, and "there is no
/// update method" is a property this project claims out loud. Backup
/// state changes as uploads run, so putting it there would mean adding
/// the very method the design promises not to have. It is bookkeeping,
/// not evidence, and it loses nothing by living beside it.
class BackupStateStore {
  BackupStateStore(this._store);

  final SecureStore _store;

  static const String _key = 'sync.v1.backups';

  /// Read-modify-write, so two uploads finishing together cannot each
  /// save a map that is missing the other's change.
  Future<void> _queue = Future.value();

  Map<String, BackupRecord>? _cache;

  Future<Map<String, BackupRecord>> load() => _serialized(_load);

  /// The state of one item, without touching storage. Returns the
  /// default until [load] has run at least once.
  BackupRecord recordFor(String evidenceId) {
    return _cache?[evidenceId] ?? const BackupRecord();
  }

  Future<void> save(String evidenceId, BackupRecord record) {
    return _serialized(() async {
      final current = await _load();

      current[evidenceId] = record;

      await _write(current);
    });
  }

  /// Replaces what is known about which items have cloud copies, from
  /// the receipts on the server. The receipts are the authority; this
  /// map is only a cache of them.
  Future<void> reconcile(Set<String> backedUp) {
    return _serialized(() async {
      final current = await _load();

      for (final id in backedUp) {
        final existing = current[id] ?? const BackupRecord();

        current[id] = existing.copyWith(
          state: BackupState.backedUp,
          metadataSynced: true,
        );
      }

      await _write(current);
    });
  }

  // ---------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());

    _queue = result.then<void>((_) {}, onError: (_) {});

    return result;
  }

  Future<Map<String, BackupRecord>> _load() async {
    final raw = await _store.read(_key);

    if (raw == null) {
      return _cache = {};
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      return _cache = decoded.map(
        (id, value) =>
            MapEntry(id, BackupRecord.fromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      // Unreadable bookkeeping is not worth failing over: the receipts
      // on the server can rebuild it, and no evidence depends on it.
      return _cache = {};
    }
  }

  Future<void> _write(Map<String, BackupRecord> records) async {
    _cache = records;

    await _store.write(
      _key,
      jsonEncode(records.map((id, record) => MapEntry(id, record.toJson()))),
    );
  }
}
