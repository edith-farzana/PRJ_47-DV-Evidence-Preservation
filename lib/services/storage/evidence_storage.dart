import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/evidence/evidence_item.dart';
import '../crypto/crypto_service.dart';
import '../crypto/key_manager.dart';
import '../crypto/secure_store.dart';
import 'evidence_index.dart';

/// Encrypted, append-only evidence storage.
///
/// Every capture is encrypted to `evidence/<uuid>.enc` under its own
/// key, verified, recorded in the encrypted [EvidenceIndex], and only
/// then is the plaintext source destroyed.
///
/// There is intentionally NO deleteEvidence() or updateEvidence()
/// method.
class EvidenceStorage {
  EvidenceStorage({
    required Directory baseDirectory,
    required this._keyManager,
    required SecureStore store,
    CryptoService? crypto,
  }) : _crypto = crypto ?? CryptoService(),
       directory = Directory('${baseDirectory.path}/evidence') {
    _index = EvidenceIndex(
      directory: directory,
      store: store,
      masterKey: () => _keyManager.masterKey,
    );
  }

  final Directory directory;
  final KeyManager _keyManager;
  final CryptoService _crypto;
  late final EvidenceIndex _index;

  final Uuid _uuid = const Uuid();

  /// Encrypts and stores [sourceFile], then destroys the plaintext.
  ///
  /// Order matters, because the last step cannot be undone:
  ///   1. encrypt to a new blob
  ///   2. decrypt it again and compare hashes
  ///   3. record it in the index
  ///   4. overwrite and delete the source
  /// If 1-3 fail, the source is untouched and the blob is removed.
  Future<EvidenceItem> addEvidence({
    required File sourceFile,
    required EvidenceType type,
    String? originalFileName,
  }) async {
    if (!_keyManager.isUnlocked) {
      throw StateError('Evidence cannot be stored while the vault is locked.');
    }

    if (!await sourceFile.exists()) {
      throw ArgumentError('Evidence source file does not exist.');
    }

    final capturedAt = DateTime.now().toUtc();
    final id = _uuid.v4();

    await directory.create(recursive: true);

    // No extension: the name should not reveal what kind of file it is.
    final blob = File('${directory.path}/$id.enc');

    final EvidenceItem item;

    try {
      final masterKey = _keyManager.masterKey;

      final encryption = await _crypto.encryptFile(
        source: sourceFile,
        destination: blob,
        masterKey: masterKey,
      );

      final verified = await _crypto.verifyIntegrity(
        source: blob,
        masterKey: masterKey,
        wrappedDek: encryption.wrappedDek,
        nonce: encryption.nonce,
        gcmTag: encryption.gcmTag,
        plaintextSha256: encryption.plaintextSha256,
      );

      if (!verified) {
        throw const EvidenceIntegrityException(
          'The encrypted copy did not decrypt back to the original. '
          'The original has been kept.',
        );
      }

      item = EvidenceItem.encrypted(
        id: id,
        type: type,
        filePath: blob.path,
        originalFileName: originalFileName ?? _fileName(sourceFile.path),
        capturedAt: capturedAt,
        encryption: encryption,
      );

      await _index.append(item);
    } catch (_) {
      if (await blob.exists()) {
        await blob.delete();
      }
      rethrow;
    }

    await _destroyPlaintext(sourceFile);

    return item;
  }

  /// All evidence, newest first.
  ///
  /// Throws [EvidenceIndexCorruptedException] rather than returning an
  /// empty list when the index cannot be trusted.
  Future<List<EvidenceItem>> getEvidence() async {
    final items = await _index.load();

    items.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    return items;
  }

  /// Best effort: overwrite with zeros, then delete.
  ///
  /// Flash wear levelling means the old blocks may survive the
  /// overwrite (docs/SECURITY.md §5). By this point the evidence is
  /// safely stored, so a failure here is logged rather than thrown --
  /// reporting "could not save" for evidence that WAS saved would be
  /// worse.
  Future<void> _destroyPlaintext(File file) async {
    try {
      final length = await file.length();
      // Append mode, then seek to 0: this overwrites the existing bytes
      // in place. FileMode.writeOnly would truncate first, freeing the
      // old blocks without ever overwriting them.
      final handle = await file.open(mode: FileMode.writeOnlyAppend);

      try {
        await handle.setPosition(0);

        const chunk = 64 * 1024;
        final zeros = Uint8List(chunk);

        for (var written = 0; written < length; written += chunk) {
          final size = length - written < chunk ? length - written : chunk;
          await handle.writeFrom(zeros, 0, size);
        }

        await handle.flush();
      } finally {
        await handle.close();
      }

      await file.delete();
    } catch (error) {
      debugPrint('Could not destroy plaintext source ${file.path}: $error');
    }
  }

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
