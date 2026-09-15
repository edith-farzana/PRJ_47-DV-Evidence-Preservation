import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Thrown when decryption or integrity verification fails.
///
/// This is deliberately a distinct type: callers must be able to tell
/// "this evidence has been tampered with" apart from an ordinary I/O
/// error, because the two demand very different responses.
class EvidenceIntegrityException implements Exception {
  final String message;

  const EvidenceIntegrityException(this.message);

  @override
  String toString() => 'EvidenceIntegrityException: $message';
}

/// The cryptographic metadata produced by encrypting one evidence file.
///
/// None of these values are secret except [wrappedDek], which is itself
/// encrypted under the master key. They are safe to store alongside the
/// blob and to upload to the backend.
class EncryptionResult {
  /// SHA-256 of the ORIGINAL file, hex encoded.
  ///
  /// This is the evidentiary hash: it proves the captured material has
  /// not changed since capture. It is also bound into the ciphertext as
  /// AAD, so it cannot be swapped for a different file's hash.
  final String plaintextSha256;

  /// SHA-256 of the encrypted blob, hex encoded. Detects storage or
  /// transport corruption without needing to decrypt.
  final String ciphertextSha256;

  /// The per-file data encryption key, wrapped under the master key.
  /// Base64 of: nonce(12) || ciphertext(32) || mac(16).
  final String wrappedDek;

  /// Base64 of the 96-bit nonce used for the file itself.
  final String nonce;

  /// Base64 of the 128-bit GCM authentication tag for the file.
  final String gcmTag;

  final String encryptionAlgorithm;
  final int keyVersion;

  final int plaintextBytes;
  final int ciphertextBytes;

  const EncryptionResult({
    required this.plaintextSha256,
    required this.ciphertextSha256,
    required this.wrappedDek,
    required this.nonce,
    required this.gcmTag,
    required this.encryptionAlgorithm,
    required this.keyVersion,
    required this.plaintextBytes,
    required this.ciphertextBytes,
  });
}

/// Envelope encryption for evidence files.
///
/// Key hierarchy (see docs/SECURITY.md):
///
///   PIN -> PBKDF2 -> PIN-derived key -> master key (KEK) -> per-file DEK
///
/// This service owns the bottom two levels: it generates a fresh DEK for
/// every file, encrypts the file under that DEK with AES-256-GCM, and
/// wraps the DEK under the master key it is handed. It never derives,
/// stores or persists the master key itself -- that is KeyManager's job
/// (P2).
class CryptoService {
  CryptoService();

  static const String algorithmLabel = 'AES-256-GCM';

  /// Bumped only if the key hierarchy itself changes, so that old
  /// records stay decryptable by the scheme that produced them.
  static const int currentKeyVersion = 1;

  /// AES-GCM nonce length in bytes (96 bits, the NIST-recommended size).
  static const int nonceLength = 12;

  /// Wrapped-DEK layout: 12-byte nonce, 32-byte ciphertext, 16-byte MAC.
  static const int _dekCipherTextLength = 32;
  static const int _macLength = 16;

  final AesGcm _cipher = AesGcm.with256bits();

  // ---------------------------------------------------------------
  // Hashing
  // ---------------------------------------------------------------

  /// Streams [file] through SHA-256 and returns the hex digest.
  ///
  /// Streaming matters: evidence can be a 30-minute video, and reading
  /// one into memory to hash it would take the app down on a low-end
  /// device. `openRead()` yields chunks, so peak memory stays flat
  /// regardless of file size.
  Future<String> hashFile(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;

    return digest.toString();
  }

  /// SHA-256 of an in-memory buffer, hex encoded.
  String hashBytes(List<int> bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  // ---------------------------------------------------------------
  // Encryption
  // ---------------------------------------------------------------

  /// Encrypts [source] to [destination] under a freshly generated DEK,
  /// and wraps that DEK under [masterKey].
  ///
  /// [destination] is overwritten if it exists.
  ///
  /// The file is read twice, which is deliberate. The plaintext hash is
  /// used as AAD, so it has to be known before encryption starts -- and
  /// it cannot be known until the whole file has been read. Two streamed
  /// passes cost less than buffering the file to do it in one.
  Future<EncryptionResult> encryptFile({
    required File source,
    required File destination,
    required SecretKey masterKey,
  }) async {
    if (!await source.exists()) {
      throw ArgumentError('Source file does not exist: ${source.path}');
    }

    // Pass 1 -- the evidentiary hash, which also becomes the AAD.
    final plaintextSha256 = await hashFile(source);

    final aad = utf8.encode(plaintextSha256);

    final plaintextBytes = await source.length();

    // A fresh key and a fresh nonce for every single file. AES-GCM loses
    // confidentiality catastrophically if a nonce is ever reused under
    // the same key; generating both per-file means that cannot happen
    // even if the same file is captured twice.
    final dek = await _cipher.newSecretKey();

    final nonce = _cipher.newNonce();

    await destination.parent.create(recursive: true);

    final sink = destination.openWrite();

    Mac? mac;

    try {
      // Pass 2 -- stream the plaintext through AES-256-GCM.
      final cipherStream = _cipher.encryptStream(
        source.openRead(),
        secretKey: dek,
        nonce: nonce,
        aad: aad,
        onMac: (value) => mac = value,
      );

      await for (final chunk in cipherStream) {
        sink.add(chunk);
      }

      await sink.flush();
    } finally {
      await sink.close();
    }

    if (mac == null) {
      throw StateError(
        'AES-GCM produced no authentication tag. Refusing to record '
        'evidence that cannot be verified.',
      );
    }

    final wrappedDek = await _wrapDek(dek: dek, masterKey: masterKey);

    return EncryptionResult(
      plaintextSha256: plaintextSha256,
      ciphertextSha256: await hashFile(destination),
      wrappedDek: wrappedDek,
      nonce: base64.encode(nonce),
      gcmTag: base64.encode(mac!.bytes),
      encryptionAlgorithm: algorithmLabel,
      keyVersion: currentKeyVersion,
      plaintextBytes: plaintextBytes,
      ciphertextBytes: await destination.length(),
    );
  }

  // ---------------------------------------------------------------
  // Decryption
  // ---------------------------------------------------------------

  /// Decrypts [source] to [destination] and returns the written file.
  ///
  /// Throws [EvidenceIntegrityException] if the blob, the tag, the AAD
  /// or the wrapped key have been altered. It never returns partially
  /// decrypted output: on failure the destination is removed, because
  /// half a decrypted file is worse than none -- it looks like evidence.
  Future<File> decryptToFile({
    required File source,
    required File destination,
    required SecretKey masterKey,
    required String wrappedDek,
    required String nonce,
    required String gcmTag,
    required String plaintextSha256,
  }) async {
    if (!await source.exists()) {
      throw ArgumentError('Encrypted file does not exist: ${source.path}');
    }

    final dek = await _unwrapDek(wrapped: wrappedDek, masterKey: masterKey);

    // The AAD must be byte-identical to what was bound in at encryption
    // time. If the stored hash has been edited to match a substituted
    // file, this is where that shows up.
    final aad = utf8.encode(plaintextSha256);

    await destination.parent.create(recursive: true);

    final sink = destination.openWrite();

    try {
      final plainStream = _cipher.decryptStream(
        source.openRead(),
        secretKey: dek,
        nonce: base64.decode(nonce),
        mac: Mac(base64.decode(gcmTag)),
        aad: aad,
      );

      await for (final chunk in plainStream) {
        sink.add(chunk);
      }

      await sink.flush();
    } on SecretBoxAuthenticationError catch (error) {
      await sink.close();
      await _discard(destination);

      throw EvidenceIntegrityException(
        'Authentication failed while decrypting ${source.path}. The '
        'evidence file, its authentication tag or its recorded hash has '
        'been modified. ($error)',
      );
    } catch (_) {
      await sink.close();
      await _discard(destination);

      rethrow;
    }

    await sink.close();

    return destination;
  }

  /// Decrypts [source] into the system temp directory.
  ///
  /// The caller owns the returned file and MUST delete it when the
  /// viewing screen is disposed. Plaintext evidence must never outlive
  /// the screen showing it, and must never be written into the evidence
  /// directory itself.
  Future<File> decryptToTemp({
    required File source,
    required SecretKey masterKey,
    required String wrappedDek,
    required String nonce,
    required String gcmTag,
    required String plaintextSha256,
    required String fileExtension,
  }) async {
    final directory = await Directory.systemTemp.createTemp('evidence_view_');

    final destination = File('${directory.path}/preview$fileExtension');

    return decryptToFile(
      source: source,
      destination: destination,
      masterKey: masterKey,
      wrappedDek: wrappedDek,
      nonce: nonce,
      gcmTag: gcmTag,
      plaintextSha256: plaintextSha256,
    );
  }

  // ---------------------------------------------------------------
  // Verification
  // ---------------------------------------------------------------

  /// Decrypts [source] to a throwaway location, re-hashes the recovered
  /// plaintext and compares it with [plaintextSha256].
  ///
  /// Returns true only if the evidence is byte-for-byte what was
  /// captured. Any tampering returns false rather than throwing, so a
  /// verification screen can show a clear failure for one item without
  /// the whole list blowing up.
  Future<bool> verifyIntegrity({
    required File source,
    required SecretKey masterKey,
    required String wrappedDek,
    required String nonce,
    required String gcmTag,
    required String plaintextSha256,
  }) async {
    Directory? scratch;

    try {
      scratch = await Directory.systemTemp.createTemp('evidence_verify_');

      final recovered = await decryptToFile(
        source: source,
        destination: File('${scratch.path}/recovered'),
        masterKey: masterKey,
        wrappedDek: wrappedDek,
        nonce: nonce,
        gcmTag: gcmTag,
        plaintextSha256: plaintextSha256,
      );

      return await hashFile(recovered) == plaintextSha256;
    } on EvidenceIntegrityException {
      return false;
    } finally {
      if (scratch != null && await scratch.exists()) {
        await scratch.delete(recursive: true);
      }
    }
  }

  /// Verifies the encrypted blob against [ciphertextSha256] without
  /// decrypting it. Cheap enough to run on every load; catches storage
  /// corruption and truncated downloads.
  Future<bool> verifyCiphertext({
    required File source,
    required String ciphertextSha256,
  }) async {
    if (!await source.exists()) {
      return false;
    }

    return await hashFile(source) == ciphertextSha256;
  }

  // ---------------------------------------------------------------
  // DEK wrapping
  // ---------------------------------------------------------------

  /// Encrypts the per-file DEK under the master key.
  ///
  /// Wrapping the key rather than the file is what makes a PIN change
  /// instant: changing the PIN re-wraps 32 bytes, not gigabytes of
  /// video.
  Future<String> _wrapDek({
    required SecretKey dek,
    required SecretKey masterKey,
  }) async {
    final dekBytes = await dek.extractBytes();

    final nonce = _cipher.newNonce();

    final box = await _cipher.encrypt(
      dekBytes,
      secretKey: masterKey,
      nonce: nonce,
    );

    return base64.encode([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Reverses [_wrapDek].
  ///
  /// A wrong master key -- meaning a wrong PIN -- fails here, which is
  /// exactly how PIN verification works: we never compare the PIN
  /// against a stored value, we just see whether it unwraps the key.
  Future<SecretKey> _unwrapDek({
    required String wrapped,
    required SecretKey masterKey,
  }) async {
    final raw = base64.decode(wrapped);

    final expectedLength = nonceLength + _dekCipherTextLength + _macLength;

    if (raw.length != expectedLength) {
      throw EvidenceIntegrityException(
        'Wrapped key is ${raw.length} bytes, expected $expectedLength. '
        'The stored key material has been truncated or altered.',
      );
    }

    final box = SecretBox(
      raw.sublist(nonceLength, nonceLength + _dekCipherTextLength),
      nonce: raw.sublist(0, nonceLength),
      mac: Mac(raw.sublist(nonceLength + _dekCipherTextLength)),
    );

    try {
      final dekBytes = await _cipher.decrypt(box, secretKey: masterKey);

      return SecretKey(dekBytes);
    } on SecretBoxAuthenticationError catch (error) {
      throw EvidenceIntegrityException(
        'Could not unwrap the file key. Either the master key is wrong '
        '(incorrect PIN) or the stored key material has been modified. '
        '($error)',
      );
    }
  }

  // ---------------------------------------------------------------

  Future<void> _discard(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
