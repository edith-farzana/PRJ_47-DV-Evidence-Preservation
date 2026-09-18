import 'dart:io';

import 'package:cryptography/cryptography.dart';
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
/// Captures are staged in [pendingDirectory] first. Anything still
/// there after a crash, or after the app was killed mid-save, is stored
/// by [ingestPending] on the next unlock -- nothing captured is dropped
/// silently.
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
       directory = Directory('${baseDirectory.path}/evidence'),
       pendingDirectory = Directory('${baseDirectory.path}/pending') {
    _index = EvidenceIndex(directory: directory, store: store);
  }

  final Directory directory;

  /// Plaintext captures waiting to be encrypted. App-private, and not
  /// the cache directory, which Android may clear under storage
  /// pressure.
  final Directory pendingDirectory;

  final KeyManager _keyManager;
  final CryptoService _crypto;
  late final EvidenceIndex _index;

  final Uuid _uuid = const Uuid();

  /// Sources currently being saved, so [ingestPending] never stores the
  /// same capture twice while a save that outlived a lock is running.
  final Set<String> _inFlight = {};

  // ---------------------------------------------------------------
  // Keys
  // ---------------------------------------------------------------

  /// A private copy of the master key for one operation.
  ///
  /// KeyManager.lock() overwrites the master key's bytes. Without a copy,
  /// a lock arriving mid-save could leave a file key wrapped under a
  /// zeroed key. With one, a save started before a panic completes
  /// correctly; the copy is destroyed when the save ends.
  Future<SecretKeyData> copyMasterKey() async {
    final bytes = await _keyManager.masterKey.extractBytes();

    return SecretKeyData(List<int>.of(bytes), overwriteWhenDestroyed: true);
  }

  // ---------------------------------------------------------------
  // Staging
  // ---------------------------------------------------------------

  /// A fresh path in [pendingDirectory] for a capture of [type]. The
  /// type is encoded in the name so [ingestPending] can recover it.
  Future<File> newPendingFile(EvidenceType type, String extension) async {
    await pendingDirectory.create(recursive: true);

    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;

    return File(
      '${pendingDirectory.path}/${type.name}_${stamp}_'
      '${_uuid.v4().substring(0, 8)}$extension',
    );
  }

  /// Moves a capture written elsewhere (e.g. the camera plugin's cache
  /// file) into [pendingDirectory].
  Future<File> stage(File capture, EvidenceType type) async {
    final dot = capture.path.lastIndexOf('.');
    final extension = dot == -1 ? '' : capture.path.substring(dot);
    final destination = await newPendingFile(type, extension);

    try {
      return await capture.rename(destination.path);
    } on FileSystemException {
      // Different filesystem: copy, then destroy the original.
      final copy = await capture.copy(destination.path);
      await _destroyPlaintext(capture);
      return copy;
    }
  }

  /// Stores everything left in [pendingDirectory]. Returns how many
  /// were stored. A file that fails is left in place for next time.
  Future<int> ingestPending() async {
    if (!await pendingDirectory.exists()) {
      return 0;
    }

    var stored = 0;

    // Snapshot first: each successful add deletes its file.
    final entries = await pendingDirectory.list().toList();

    for (final entry in entries) {
      if (entry is! File || _inFlight.contains(entry.path)) {
        continue;
      }

      final name = entry.path.split(Platform.pathSeparator).last;
      final type = EvidenceType.values
          .where((value) => name.startsWith('${value.name}_'))
          .firstOrNull;

      if (type == null) {
        continue;
      }

      try {
        await addEvidence(
          sourceFile: entry,
          type: type,
          originalFileName: name,
        );
        stored++;
      } catch (error) {
        debugPrint('Pending capture $name not stored yet: $error');
      }
    }

    return stored;
  }

  /// Encrypts and stores [sourceFile], then destroys the plaintext.
  ///
  /// Order matters, because the last step cannot be undone:
  ///   1. encrypt to a new blob
  ///   2. decrypt it again and compare hashes
  ///   3. record it in the index
  ///   4. overwrite and delete the source
  /// If 1-3 fail, the source is untouched and the blob is removed.
  ///
  /// [masterKey], if given, is a copy from [copyMasterKey] taken before a
  /// lock; it is destroyed when this returns. Otherwise a copy is taken
  /// here, which requires the vault to be unlocked.
  Future<EvidenceItem> addEvidence({
    required File sourceFile,
    required EvidenceType type,
    String? originalFileName,
    SecretKeyData? masterKey,
  }) async {
    if (masterKey == null && !_keyManager.isUnlocked) {
      throw StateError('Evidence cannot be stored while the vault is locked.');
    }

    final key = masterKey ?? await copyMasterKey();

    _inFlight.add(sourceFile.path);

    try {
      return await _add(sourceFile, type, originalFileName, key);
    } finally {
      _inFlight.remove(sourceFile.path);
      key.destroy();
    }
  }

  Future<EvidenceItem> _add(
    File sourceFile,
    EvidenceType type,
    String? originalFileName,
    SecretKey masterKey,
  ) async {
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

      await _index.append(item, masterKey);
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
    final key = await copyMasterKey();

    final List<EvidenceItem> items;

    try {
      items = await _index.load(key);
    } finally {
      key.destroy();
    }

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
