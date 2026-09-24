import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Something that happened in the app, worth a permanent record.
///
/// Deliberately coarse. The log is a record of a survivor's behaviour, so
/// it holds what happened and when -- never filenames, never content.
enum AuditEventType {
  /// The PIN was accepted.
  unlocked,

  /// A wrong PIN was entered. Recorded by the key manager at the moment
  /// it counts the attempt, so even a force-quit guess is kept.
  unlockFailed,

  /// Panic: a one-second hold anywhere.
  panic,

  /// The app locked itself on going to the background.
  autoLocked,

  captured,
  viewed,

  /// Integrity was checked; the verdict is in the entry's detail.
  verified,

  /// An item's fingerprint reached the server.
  recordedOnServer,

  pinChanged,
}

extension AuditEventTypeLabel on AuditEventType {
  String get label {
    switch (this) {
      case AuditEventType.unlocked:
        return 'Opened';
      case AuditEventType.unlockFailed:
        return 'Wrong PIN entered';
      case AuditEventType.panic:
        return 'Panic';
      case AuditEventType.autoLocked:
        return 'Locked (app left)';
      case AuditEventType.captured:
        return 'Evidence captured';
      case AuditEventType.viewed:
        return 'Evidence viewed';
      case AuditEventType.verified:
        return 'Integrity checked';
      case AuditEventType.recordedOnServer:
        return 'Fingerprint recorded on server';
      case AuditEventType.pinChanged:
        return 'PIN changed';
    }
  }
}

/// One link in the hash chain.
///
/// [hash] is the SHA-256 of every other field -- including [prevHash],
/// the hash of the entry before it. So altering any entry breaks its own
/// hash and every link after it, and removing one breaks the link and
/// the sequence.
class AuditEntry {
  const AuditEntry._({
    required this.seq,
    required this.at,
    required this.type,
    required this.evidenceId,
    required this.detail,
    required this.prevHash,
    required this.hash,
  });

  /// What the first entry points back to.
  static const String genesisHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  /// Builds an entry and computes its hash.
  factory AuditEntry.create({
    required int seq,
    required DateTime at,
    required AuditEventType type,
    required String prevHash,
    String? evidenceId,
    Map<String, Object?> detail = const {},
  }) {
    final atIso = at.toUtc().toIso8601String();

    return AuditEntry._(
      seq: seq,
      at: atIso,
      type: type.name,
      evidenceId: evidenceId,
      detail: detail,
      prevHash: prevHash,
      hash: computeHash(
        seq: seq,
        at: atIso,
        type: type.name,
        evidenceId: evidenceId,
        detail: detail,
        prevHash: prevHash,
      ),
    );
  }

  /// 1-based position in the chain.
  final int seq;

  /// UTC, ISO 8601. Kept as the exact string that was hashed, so a round
  /// trip through JSON can never change what the hash covers.
  final String at;

  /// The event type's name. A string rather than the enum, so an entry
  /// written by a newer version still loads and verifies.
  final String type;

  final String? evidenceId;
  final Map<String, Object?> detail;
  final String prevHash;
  final String hash;

  DateTime get time => DateTime.parse(at);

  AuditEventType? get eventType {
    for (final value in AuditEventType.values) {
      if (value.name == type) return value;
    }
    return null;
  }

  /// Whether [hash] still matches this entry's contents.
  bool get hashIsValid =>
      hash ==
      computeHash(
        seq: seq,
        at: at,
        type: type,
        evidenceId: evidenceId,
        detail: detail,
        prevHash: prevHash,
      );

  /// SHA-256 over a canonical encoding: fixed field order, and `detail`'s
  /// keys sorted, so the same entry always hashes the same way.
  static String computeHash({
    required int seq,
    required String at,
    required String type,
    required String? evidenceId,
    required Map<String, Object?> detail,
    required String prevHash,
  }) {
    final canonical = jsonEncode([
      seq,
      at,
      type,
      evidenceId,
      _sorted(detail),
      prevHash,
    ]);

    return crypto.sha256.convert(utf8.encode(canonical)).toString();
  }

  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: _sorted(value[key])};
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }

  Map<String, dynamic> toMap() => {
    'seq': seq,
    'at': at,
    'type': type,
    'evidenceId': evidenceId,
    'detail': detail,
    'prevHash': prevHash,
    'hash': hash,
  };

  factory AuditEntry.fromMap(Map<String, dynamic> map) {
    return AuditEntry._(
      seq: map['seq'] as int,
      at: map['at'] as String,
      type: map['type'] as String,
      evidenceId: map['evidenceId'] as String?,
      detail: Map<String, Object?>.from(map['detail'] as Map? ?? const {}),
      prevHash: map['prevHash'] as String,
      hash: map['hash'] as String,
    );
  }
}
