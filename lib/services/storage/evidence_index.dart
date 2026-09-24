import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../../models/evidence/evidence_item.dart';
import '../crypto/secure_store.dart';
import 'sealed_file.dart';

/// Thrown when the index cannot be trusted: undecryptable, edited,
/// missing when it should exist, or rolled back to an older copy.
///
/// Callers must surface this. Showing an empty vault instead would tell
/// a survivor their evidence is gone when it is still on disk.
class EvidenceIndexCorruptedException implements Exception {
  final String message;

  const EvidenceIndexCorruptedException(this.message);

  @override
  String toString() => 'EvidenceIndexCorruptedException: $message';
}

/// The encrypted list of evidence records, `evidence/index.enc`.
///
/// The encryption and the seal live in [SealedFile]; see there for the
/// layout and why the seal exists. This class adds what is specific to
/// evidence: the records are [EvidenceItem]s, and it only ever appends.
///
/// The constants below are load-bearing. Changing the AAD, the HKDF info
/// or the seal key would make every existing install's index read as
/// corrupted.
class EvidenceIndex {
  EvidenceIndex({
    required this.directory,
    required SecureStore store,
    required SecretKey Function() masterKey,
  }) : _file = SealedFile(
         file: File('${directory.path}/index.enc'),
         store: store,
         masterKey: masterKey,
         sealKey: 'idx.v1.seal',
         aad: utf8.encode('secure-evidence/index/v1'),
         hkdfInfo: utf8.encode('evidence-index/v1'),
         corrupted: EvidenceIndexCorruptedException.new,
       );

  final Directory directory;
  final SealedFile _file;

  /// All records, in stored order. Returns `[]` only for a vault that
  /// has genuinely never had anything written to it.
  Future<List<EvidenceItem>> load() async {
    final records = await _file.load();

    try {
      return records.map(EvidenceItem.fromMap).toList();
    } catch (error) {
      throw EvidenceIndexCorruptedException('Unreadable records ($error).');
    }
  }

  /// Adds [item]. The file is replaced atomically (write temp, rename),
  /// so a crash leaves either the old index or the new one.
  Future<void> append(EvidenceItem item) {
    return _file.update((current) => [...current, item.toMap()]);
  }
}
