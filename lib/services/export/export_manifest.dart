import 'dart:convert';

/// One event from the activity log about an exported item: when it was
/// captured, recorded on the server, viewed, verified, exported.
class CustodyEvent {
  const CustodyEvent({
    required this.seq,
    required this.at,
    required this.event,
  });

  /// Its position in the activity log's hash chain.
  final int seq;

  /// UTC, ISO 8601.
  final String at;

  final String event;

  Map<String, Object?> toJson() => {'seq': seq, 'at': at, 'event': event};
}

/// An item that is in the bundle, with everything needed to check it.
class ExportedItem {
  const ExportedItem({
    required this.bundleName,
    required this.evidenceId,
    required this.type,
    required this.capturedAt,
    required this.sizeBytes,
    required this.sha256,
    required this.storedFileSha256,
    required this.verdict,
    required this.serverCheck,
    required this.custody,
    this.serverNote,
  });

  /// Its name inside the ZIP. Neutral on purpose: ZIP encryption hides
  /// contents but not names.
  final String bundleName;

  final String evidenceId;
  final String type;

  /// UTC, ISO 8601.
  final String capturedAt;

  final int sizeBytes;

  /// The fingerprint recorded at capture. The file in the bundle was
  /// hashed again during export and matched this exactly.
  final String sha256;

  /// The fingerprint of the encrypted copy stored on the phone.
  final String storedFileSha256;

  /// `verified` (the phone's checks pass and the server agrees) or
  /// `verifiedOnThisPhone` (the server could not be asked).
  final String verdict;

  /// `matches`, `notOnServer` or `unavailable`.
  final String serverCheck;

  final String? serverNote;

  final List<CustodyEvent> custody;

  Map<String, Object?> toJson() => {
    'file': bundleName,
    'evidenceId': evidenceId,
    'type': type,
    'capturedAt': capturedAt,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'storedFileSha256': storedFileSha256,
    'verdict': verdict,
    'serverCheck': serverCheck,
    if (serverNote != null) 'serverNote': serverNote,
    'custody': custody.map((event) => event.toJson()).toList(),
  };
}

/// An item that was selected but is **not** in the bundle.
///
/// Listed, rather than silently dropped: a lawyer comparing the bundle
/// with what she says she captured must be able to see the gap and why.
class NotExportedItem {
  const NotExportedItem({
    required this.evidenceId,
    required this.type,
    required this.capturedAt,
    required this.reason,
  });

  final String evidenceId;
  final String type;
  final String capturedAt;
  final String reason;

  Map<String, Object?> toJson() => {
    'evidenceId': evidenceId,
    'type': type,
    'capturedAt': capturedAt,
    'reason': reason,
  };
}

/// The record that travels with an export: what is in it, and how anyone
/// can check it without this app.
///
/// What is deliberately absent matters as much as what is present: no
/// key material of any kind, no original filenames, no location, no
/// device identifiers, and none of her unlock, panic or wrong-PIN history.
/// Custody events are limited to the exported items.
class ExportManifest {
  const ExportManifest({
    required this.generatedAt,
    required this.passwordProtected,
    required this.logIntact,
    required this.logStatus,
    required this.logEntries,
    required this.items,
    required this.notExported,
    this.logHeadHash,
  });

  static const String format = 'secure-evidence/export/v1';

  /// UTC, ISO 8601.
  final String generatedAt;

  final bool passwordProtected;

  final bool logIntact;

  /// "intact", or where and how the activity log breaks.
  final String logStatus;

  final int logEntries;

  /// The hash of the newest log entry: the tip of the chain at export.
  final String? logHeadHash;

  final List<ExportedItem> items;
  final List<NotExportedItem> notExported;

  Map<String, Object?> toJson() => {
    'format': format,
    'generatedAt': generatedAt,
    'passwordProtected': passwordProtected,
    'activityLog': {
      'intact': logIntact,
      'status': logStatus,
      'entries': logEntries,
      'headHash': logHeadHash,
    },
    'items': items.map((item) => item.toJson()).toList(),
    'notExported': notExported.map((item) => item.toJson()).toList(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// `README.txt`: how to open the bundle and check it independently.
  /// Plain ASCII, so it reads the same in any text editor.
  String readme({required String manifestSha256}) {
    final count = items.length;
    final buffer = StringBuffer()
      ..writeln('EVIDENCE EXPORT')
      ..writeln('Generated $generatedAt (UTC)')
      ..writeln()
      ..writeln(
        'This bundle contains $count evidence '
        '${count == 1 ? 'file' : 'files'}, a record of each one '
        '(manifest.pdf and manifest.json), and this file.',
      )
      ..writeln();

    if (passwordProtected) {
      buffer
        ..writeln('OPENING IT')
        ..writeln(
          'The bundle is protected with a password (AES-256). The password '
          'was given to you separately. Open it with 7-Zip '
          '(https://www.7-zip.org, free) or another tool that supports '
          'AES-encrypted ZIP files. The unzip tools built into Windows and '
          'macOS may not.',
        )
        ..writeln();
    }

    buffer
      ..writeln('CHECKING THE FILES YOURSELF')
      ..writeln(
        "Each file's SHA-256 fingerprint was recorded when it was captured "
        'and is listed in manifest.pdf and manifest.json. Any change to a '
        'file, even a single byte, changes its fingerprint completely. To '
        'check a file:',
      )
      ..writeln()
      ..writeln('  Windows:        certutil -hashfile item-01.jpg SHA256')
      ..writeln('  macOS / Linux:  shasum -a 256 item-01.jpg')
      ..writeln()
      ..writeln('The result must match the manifest exactly.')
      ..writeln()
      ..writeln('The SHA-256 fingerprint of manifest.json is:')
      ..writeln('  $manifestSha256')
      ..writeln('and it is also printed in manifest.pdf.')
      ..writeln()
      ..writeln('WHAT THIS DOES NOT CLAIM')
      ..writeln(
        '- It cannot guarantee that a court will admit this evidence. That '
        'depends on the jurisdiction, how the evidence was collected, and '
        'the law.',
      )
      ..writeln('- Times come from the phone\'s clock.')
      ..writeln(
        "- Each item's fingerprint was also recorded at capture on a server "
        'where it cannot be changed or deleted by anyone, including the '
        "project's administrators. That record is held in the project's "
        'Firebase account.',
      );

    return buffer.toString();
  }
}
