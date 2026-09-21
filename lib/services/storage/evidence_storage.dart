import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../models/evidence/evidence_item.dart';
import '../../models/evidence/integrity_report.dart';
import '../crypto/crypto_service.dart';
import '../crypto/key_manager.dart';
import '../crypto/secure_store.dart';
import 'evidence_index.dart';
import 'secure_delete.dart';

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
    Directory? cacheDirectory,
    CryptoService? crypto,
  }) : _crypto = crypto ?? CryptoService(),
       directory = Directory('${baseDirectory.path}/evidence'),
       previewDirectory = Directory(
         '${(cacheDirectory ?? baseDirectory).path}/preview',
       ) {
    _index = EvidenceIndex(
      directory: directory,
      store: store,
      masterKey: () => _keyManager.masterKey,
    );
  }

  final Directory directory;

  /// Where evidence is decrypted to while it is on screen.
  ///
  /// Deliberately not [directory]: the evidence directory must never
  /// hold plaintext. In the app this is inside the cache, so the OS can
  /// reclaim it and [sweepPreviews] can clear it at launch.
  final Directory previewDirectory;
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

    // By this point the evidence is safely stored, so a failure here is
    // logged rather than thrown -- reporting "could not save" for
    // evidence that WAS saved would be worse.
    await destroyPlaintext(sourceFile);

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

  /// Decrypts [item] so it can be shown, and returns the plaintext file.
  ///
  /// The caller MUST pass the result to [closePreview] when its screen
  /// is disposed -- including when a panic or an auto-lock tears the
  /// screen down. Plaintext evidence must never outlive the screen
  /// showing it.
  Future<File> openPreview(EvidenceItem item) async {
    if (!_keyManager.isUnlocked) {
      throw StateError('Evidence cannot be opened while the vault is locked.');
    }

    if (!item.isEncrypted) {
      throw const EvidenceIntegrityException(
        'This record carries no encryption metadata, so it cannot be '
        'decrypted.',
      );
    }

    final blob = File(item.filePath);

    if (!await blob.exists()) {
      throw EvidenceIntegrityException(
        'The encrypted file for this evidence is missing from ${blob.path}.',
      );
    }

    await previewDirectory.create(recursive: true);

    // A fresh name per open, so two previews of the same item cannot
    // collide and a stale file is never mistaken for a new one.
    final destination = File(
      '${previewDirectory.path}/${_uuid.v4()}${_extensionFor(item)}',
    );

    return _crypto.decryptToFile(
      source: blob,
      destination: destination,
      masterKey: _keyManager.masterKey,
      wrappedDek: item.wrappedDek!,
      nonce: item.nonce!,
      gcmTag: item.gcmTag!,
      plaintextSha256: item.plaintextSha256!,
    );
  }

  /// Destroys a file handed out by [openPreview].
  Future<void> closePreview(File preview) => destroyPlaintext(preview);

  /// Destroys every decrypted preview left behind by a crash, a
  /// force-stop or a killed process. Called at launch.
  Future<void> sweepPreviews() async {
    if (!await previewDirectory.exists()) {
      return;
    }

    await for (final entity in previewDirectory.list()) {
      if (entity is File) {
        await destroyPlaintext(entity);
      }
    }
  }

  /// Re-checks [item] against the hashes recorded when it was captured.
  ///
  /// Never throws: a failure is a finding to show the user, not an
  /// error that should take the screen down. See [IntegrityReport] for
  /// what each check means.
  Future<IntegrityReport> checkIntegrity(EvidenceItem item) async {
    if (!item.isEncrypted) {
      return IntegrityReport.unverifiable(item.id);
    }

    final blob = File(item.filePath);

    if (!await blob.exists()) {
      return IntegrityReport(
        itemId: item.id,
        blobExists: false,
        recordedPlaintextSha256: item.plaintextSha256,
        recordedCiphertextSha256: item.ciphertextSha256,
        failure: 'The encrypted file is missing from ${blob.path}.',
      );
    }

    if (!_keyManager.isUnlocked) {
      throw StateError(
        'Evidence cannot be verified while the vault is locked.',
      );
    }

    // Cheap, and it does not need the key: hash the stored blob first so
    // storage corruption is reported even if decryption then fails.
    final ciphertextSha256 = await _crypto.hashFile(blob);

    File? recovered;

    try {
      recovered = await openPreview(item);

      return IntegrityReport(
        itemId: item.id,
        blobExists: true,
        recordedPlaintextSha256: item.plaintextSha256,
        recalculatedPlaintextSha256: await _crypto.hashFile(recovered),
        recordedCiphertextSha256: item.ciphertextSha256,
        recalculatedCiphertextSha256: ciphertextSha256,
      );
    } on EvidenceIntegrityException catch (error) {
      return IntegrityReport(
        itemId: item.id,
        blobExists: true,
        recordedPlaintextSha256: item.plaintextSha256,
        recordedCiphertextSha256: item.ciphertextSha256,
        recalculatedCiphertextSha256: ciphertextSha256,
        failure: error.message,
      );
    } finally {
      if (recovered != null) {
        await closePreview(recovered);
      }
    }
  }

  /// What the decrypted file should be called on disk.
  ///
  /// A player picks its decoder from the extension, and the stored blob
  /// deliberately has none. The original name is only trusted for its
  /// extension, never for the path.
  String _extensionFor(EvidenceItem item) {
    final name = item.originalFileName;
    final dot = name.lastIndexOf('.');

    if (dot > 0 && dot < name.length - 1) {
      final extension = name.substring(dot).toLowerCase();

      if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)) {
        return extension;
      }
    }

    switch (item.type) {
      case EvidenceType.photo:
        return '.jpg';
      case EvidenceType.video:
        return '.mp4';
      case EvidenceType.audio:
        return '.m4a';
    }
  }

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }
}
