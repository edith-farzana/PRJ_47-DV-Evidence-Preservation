import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/audit/audit_entry.dart';
import '../crypto/key_manager.dart';
import '../crypto/secure_store.dart';
import '../storage/sealed_file.dart';

/// Thrown when the activity log cannot be trusted: undecryptable, edited,
/// cut short, or replaced with an older copy.
class AuditLogCorruptedException implements Exception {
  const AuditLogCorruptedException(this.message);

  final String message;

  @override
  String toString() => 'AuditLogCorruptedException: $message';
}

/// The result of walking the chain.
class ChainReport {
  const ChainReport.intact(this.entryCount)
    : brokenAtSeq = null,
      problem = null;

  const ChainReport.broken({
    required this.entryCount,
    required this.problem,
    this.brokenAtSeq,
  });

  final int entryCount;

  /// The first entry that does not check out. Null when the whole file
  /// failed before any entry could be read.
  final int? brokenAtSeq;

  /// In words for the user. Null when intact.
  final String? problem;

  bool get intact => problem == null;
}

/// Wrong PINs entered since she last opened the app.
///
/// Worth telling her about: once the right PIN goes in, the lockout
/// counter resets, and without this nothing would show anyone tried.
class UnlockNotice {
  const UnlockNotice({required this.count, required this.times});

  /// Authoritative, from the key manager's counter.
  final int count;

  /// When each happened, as far as they were recorded. Best effort: the
  /// count is the number to trust if the two ever differ.
  final List<DateTime> times;

  DateTime? get first => times.isEmpty ? null : times.first;
  DateTime? get last => times.isEmpty ? null : times.last;
}

/// An append-only, hash-chained record of what happens in the app.
///
/// Stored encrypted at `<documents>/audit/log.enc`, sealed like the
/// evidence index ([SealedFile]) so that cutting recent entries off, or
/// restoring an older copy, is caught -- the one attack a hash chain alone
/// misses.
///
/// Some events happen without the master key: a wrong PIN, and locking.
/// Those go into a small pending list in [SecureStore], which needs no
/// master key, and are folded into the chain in time order at the next
/// unlock.
class AuditLog extends ChangeNotifier {
  AuditLog({
    required Directory baseDirectory,
    required this._store,
    required this._keyManager,
    @visibleForTesting DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now,
       _file = SealedFile(
         file: File('${baseDirectory.path}/audit/log.enc'),
         store: _store,
         masterKey: () => _keyManager.masterKey,
         sealKey: 'audit.v1.seal',
         aad: utf8.encode('secure-evidence/audit/v1'),
         hkdfInfo: utf8.encode('audit-log/v1'),
         corrupted: AuditLogCorruptedException.new,
       );

  final SecureStore _store;
  final KeyManager _keyManager;
  final DateTime Function() _now;
  final SealedFile _file;

  static const String _pendingKey = 'audit.v1.pending';

  /// Enough for a long stretch locked; bounded so the pending list cannot
  /// grow without limit if the log is ever unwritable.
  static const int maxPending = 200;

  UnlockNotice? _notice;

  Future<void> _pendingQueue = Future.value();

  // ---------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------

  /// Records an event. Never throws: a logging failure must not stop a
  /// capture or a lock.
  ///
  /// Written to the chain when unlocked; otherwise, or if the key is lost
  /// mid-write to a panic, kept pending until the next unlock.
  Future<void> record(
    AuditEventType type, {
    String? evidenceId,
    Map<String, Object?> detail = const {},
  }) async {
    final draft = _Draft(_now(), type.name, evidenceId, detail);

    if (_keyManager.isUnlocked) {
      try {
        await _append([draft]);
        notifyListeners();
        return;
      } catch (error) {
        // Locked mid-write, or the log is unreadable. Either way, keeping
        // the event pending loses less than dropping it.
        debugPrint('Activity log: kept ${type.name} pending ($error)');
      }
    }

    await _addPending([draft]);
  }

  /// Called once the PIN has been accepted.
  ///
  /// Folds in what happened while locked -- panics, auto-locks, and the
  /// wrong PINs the key manager kept -- then records the unlock itself.
  Future<void> onUnlocked(UnlockResult result) async {
    if (result.priorFailedAttempts > 0) {
      // Set before any await, so the screen that opens next can show it.
      _notice = UnlockNotice(
        count: result.priorFailedAttempts,
        times: result.priorFailureTimes,
      );
      notifyListeners();
    }

    await _foldWith([
      for (final time in result.priorFailureTimes)
        _Draft(time, AuditEventType.unlockFailed.name, null, const {}),
      _Draft(_now(), AuditEventType.unlocked.name, null, {
        'priorFailedAttempts': result.priorFailedAttempts,
      }),
    ]);
  }

  /// Called after a successful PIN change. Wrong current-PIN attempts
  /// made on that screen are recorded too: the key manager's counter
  /// resets on success, exactly as it does on unlock.
  Future<void> onPinChanged(UnlockResult result) async {
    await _foldWith([
      for (final time in result.priorFailureTimes)
        _Draft(time, AuditEventType.unlockFailed.name, null, const {}),
      _Draft(_now(), AuditEventType.pinChanged.name, null, const {}),
    ]);
  }

  /// The wrong-PIN notice for the screen shown after unlock. Returned
  /// once, then cleared.
  UnlockNotice? takeUnlockNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  // ---------------------------------------------------------------
  // Reading and verifying
  // ---------------------------------------------------------------

  /// Every entry, oldest first. Throws [AuditLogCorruptedException] if
  /// the file cannot be trusted.
  Future<List<AuditEntry>> entries() async {
    final records = await _file.load();

    try {
      return records.map(AuditEntry.fromMap).toList();
    } catch (error) {
      throw AuditLogCorruptedException('Unreadable entries ($error).');
    }
  }

  /// Walks the chain and reports the first entry that does not check out.
  ///
  /// Never throws: a broken log is a finding to show, not an error.
  Future<ChainReport> verify() async {
    final List<AuditEntry> chain;

    try {
      chain = await entries();
    } on AuditLogCorruptedException catch (error) {
      return ChainReport.broken(entryCount: 0, problem: error.message);
    }

    var expectedPrev = AuditEntry.genesisHash;

    for (var i = 0; i < chain.length; i++) {
      final entry = chain[i];
      final position = i + 1;

      if (entry.seq != position) {
        return ChainReport.broken(
          entryCount: chain.length,
          brokenAtSeq: position,
          problem:
              'Entry $position is missing: the sequence jumps to '
              '${entry.seq}.',
        );
      }

      if (entry.prevHash != expectedPrev) {
        return ChainReport.broken(
          entryCount: chain.length,
          brokenAtSeq: position,
          problem: 'Entry $position does not follow from the one before it.',
        );
      }

      if (!entry.hashIsValid) {
        return ChainReport.broken(
          entryCount: chain.length,
          brokenAtSeq: position,
          problem: 'Entry $position has been altered.',
        );
      }

      expectedPrev = entry.hash;
    }

    return ChainReport.intact(chain.length);
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  /// Appends [fresh] together with whatever is pending, oldest first, in
  /// one write.
  Future<void> _foldWith(List<_Draft> fresh) async {
    final pending = await _serializedPending(_readPending);

    try {
      await _append(
        [...pending, ...fresh]..sort((a, b) => a.at.compareTo(b.at)),
      );

      // Only what was read: a panic that landed in the pending list while
      // this was running must not be swept away with the rest.
      await _serializedPending(() async {
        final now = await _readPending();
        await _writePending(now.skip(pending.length).toList());
      });

      notifyListeners();
    } catch (error) {
      // The key manager has already cleared its record of the wrong PINs,
      // so if they do not reach the chain they must not be lost.
      debugPrint('Activity log: kept unlock events pending ($error)');
      await _addPending(fresh);
    }
  }

  Future<void> _append(List<_Draft> drafts) {
    return _file.update((current) {
      var prev = current.isEmpty
          ? AuditEntry.genesisHash
          : current.last['hash'] as String;
      var seq = current.length;

      final added = <Map<String, dynamic>>[];

      for (final draft in drafts) {
        final type = _typeNamed(draft.type);
        if (type == null) continue;

        seq++;

        final entry = AuditEntry.create(
          seq: seq,
          at: draft.at,
          type: type,
          prevHash: prev,
          evidenceId: draft.evidenceId,
          detail: draft.detail,
        );

        added.add(entry.toMap());
        prev = entry.hash;
      }

      return [...current, ...added];
    });
  }

  static AuditEventType? _typeNamed(String name) {
    for (final value in AuditEventType.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  Future<void> _addPending(List<_Draft> drafts) {
    return _serializedPending(() async {
      final pending = [...await _readPending(), ...drafts];

      final kept = pending.length > maxPending
          ? pending.sublist(pending.length - maxPending)
          : pending;

      await _writePending(kept);
    });
  }

  Future<List<_Draft>> _readPending() async {
    final raw = await _store.read(_pendingKey);
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((entry) => _Draft.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('Activity log: unreadable pending list dropped ($error)');
      return [];
    }
  }

  Future<void> _writePending(List<_Draft> drafts) {
    if (drafts.isEmpty) return _store.delete(_pendingKey);

    return _store.write(
      _pendingKey,
      jsonEncode(drafts.map((draft) => draft.toJson()).toList()),
    );
  }

  Future<T> _serializedPending<T>(Future<T> Function() action) {
    final result = _pendingQueue.then((_) => action());
    _pendingQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// An event not yet in the chain.
class _Draft {
  _Draft(this.at, this.type, this.evidenceId, this.detail);

  final DateTime at;
  final String type;
  final String? evidenceId;
  final Map<String, Object?> detail;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'type': type,
    'evidenceId': evidenceId,
    'detail': detail,
  };

  factory _Draft.fromJson(Map<String, dynamic> json) => _Draft(
    DateTime.parse(json['at'] as String),
    json['type'] as String,
    json['evidenceId'] as String?,
    Map<String, Object?>.from(json['detail'] as Map? ?? const {}),
  );
}
