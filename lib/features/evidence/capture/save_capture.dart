import 'dart:async';
import 'dart:io';

import '../../../models/audit/audit_entry.dart';
import '../../../models/evidence/evidence_item.dart';
import '../../../services/audit/audit_log.dart';
import '../../../services/storage/evidence_storage.dart';
import '../../../services/sync/evidence_sync.dart';

/// What every capture screen does once it has a plaintext file.
///
/// Only the first step is waited for: [EvidenceStorage.addEvidence],
/// which encrypts, verifies, records and then destroys [source]. When it
/// returns the evidence is safe, and the screen can say so. The rest is
/// started and left to run:
///
///  * the activity log notes the capture;
///  * the record goes to the server ([EvidenceSync.recordCaptured]).
///    With no signal that can take hours, or fail. Neither may hold up,
///    or turn into a failure, a capture that has already succeeded --
///    the next unlock catches the record up.
///
/// Throws only what [EvidenceStorage.addEvidence] throws, and in that
/// case [source] has not been touched.
Future<EvidenceItem> saveCapture({
  required EvidenceStorage storage,
  required AuditLog audit,
  required EvidenceSync sync,
  required File source,
  required EvidenceType type,
  required String originalFileName,
}) async {
  final evidence = await storage.addEvidence(
    sourceFile: source,
    type: type,
    originalFileName: originalFileName,
  );

  unawaited(
    audit.record(
      AuditEventType.captured,
      evidenceId: evidence.id,
      detail: {'type': evidence.type.name},
    ),
  );

  // After the log entry, so "captured" is queued in the log ahead of the
  // "recorded on server" this produces.
  unawaited(sync.recordCaptured(evidence));

  return evidence;
}
