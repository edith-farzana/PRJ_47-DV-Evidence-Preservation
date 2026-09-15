import 'dart:convert';

import '../../services/crypto/crypto_service.dart';

enum EvidenceType { photo, video, audio }

class EvidenceItem {
  final String id;
  final EvidenceType type;
  final String filePath;
  final String originalFileName;
  final DateTime capturedAt;
  final int fileSizeBytes;

  // -----------------------------------------------------------------
  // Cryptographic metadata.
  //
  // Nullable because storage does not route through CryptoService until
  // P3. Once it does, an item with a null [plaintextSha256] is an
  // unencrypted legacy record and should be treated as unverifiable --
  // see [isEncrypted].
  // -----------------------------------------------------------------

  /// SHA-256 of the original captured file, hex encoded.
  ///
  /// The evidentiary hash. Also bound into the ciphertext as AAD, so it
  /// cannot be swapped for another file's hash without decryption
  /// failing.
  final String? plaintextSha256;

  /// SHA-256 of the encrypted blob, hex encoded. Detects storage or
  /// transport corruption without decrypting.
  final String? ciphertextSha256;

  /// The per-file data encryption key, wrapped under the master key.
  /// Base64 of: nonce(12) || ciphertext(32) || mac(16).
  final String? wrappedDek;

  /// Base64 of the 96-bit AES-GCM nonce for this file.
  final String? nonce;

  /// Base64 of the 128-bit AES-GCM authentication tag for this file.
  final String? gcmTag;

  /// e.g. "AES-256-GCM". Recorded so that a future scheme change stays
  /// backward compatible.
  final String? encryptionAlgorithm;

  /// Which generation of the key hierarchy produced this record.
  final int? keyVersion;

  const EvidenceItem({
    required this.id,
    required this.type,
    required this.filePath,
    required this.originalFileName,
    required this.capturedAt,
    required this.fileSizeBytes,
    this.plaintextSha256,
    this.ciphertextSha256,
    this.wrappedDek,
    this.nonce,
    this.gcmTag,
    this.encryptionAlgorithm,
    this.keyVersion,
  });

  /// Builds an item from a capture plus the output of [CryptoService].
  factory EvidenceItem.encrypted({
    required String id,
    required EvidenceType type,
    required String filePath,
    required String originalFileName,
    required DateTime capturedAt,
    required EncryptionResult encryption,
  }) {
    return EvidenceItem(
      id: id,
      type: type,
      filePath: filePath,
      originalFileName: originalFileName,
      capturedAt: capturedAt,
      fileSizeBytes: encryption.ciphertextBytes,
      plaintextSha256: encryption.plaintextSha256,
      ciphertextSha256: encryption.ciphertextSha256,
      wrappedDek: encryption.wrappedDek,
      nonce: encryption.nonce,
      gcmTag: encryption.gcmTag,
      encryptionAlgorithm: encryption.encryptionAlgorithm,
      keyVersion: encryption.keyVersion,
    );
  }

  /// True when this record carries everything needed to decrypt and
  /// verify it. A false here means the item predates encryption and
  /// cannot be shown as protected in the UI.
  bool get isEncrypted {
    return plaintextSha256 != null &&
        wrappedDek != null &&
        nonce != null &&
        gcmTag != null;
  }

  String get typeLabel {
    switch (type) {
      case EvidenceType.photo:
        return 'Photo';
      case EvidenceType.video:
        return 'Video';
      case EvidenceType.audio:
        return 'Audio';
    }
  }

  String get fileSizeLabel {
    if (fileSizeBytes < 1024) {
      return '$fileSizeBytes B';
    }

    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Short prefix of the evidentiary hash, for display next to an item.
  String get shortHash {
    final hash = plaintextSha256;

    if (hash == null || hash.length < 12) {
      return '—';
    }

    return hash.substring(0, 12).toUpperCase();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'filePath': filePath,
      'originalFileName': originalFileName,
      'capturedAt': capturedAt.toIso8601String(),
      'fileSizeBytes': fileSizeBytes,
      'plaintextSha256': plaintextSha256,
      'ciphertextSha256': ciphertextSha256,
      'wrappedDek': wrappedDek,
      'nonce': nonce,
      'gcmTag': gcmTag,
      'encryptionAlgorithm': encryptionAlgorithm,
      'keyVersion': keyVersion,
    };
  }

  factory EvidenceItem.fromMap(Map<String, dynamic> map) {
    return EvidenceItem(
      id: map['id'] as String,
      type: EvidenceType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => EvidenceType.photo,
      ),
      filePath: map['filePath'] as String,
      originalFileName: map['originalFileName'] as String,
      capturedAt: DateTime.parse(map['capturedAt'] as String),
      fileSizeBytes: map['fileSizeBytes'] as int,
      plaintextSha256: map['plaintextSha256'] as String?,
      ciphertextSha256: map['ciphertextSha256'] as String?,
      wrappedDek: map['wrappedDek'] as String?,
      nonce: map['nonce'] as String?,
      gcmTag: map['gcmTag'] as String?,
      encryptionAlgorithm: map['encryptionAlgorithm'] as String?,
      keyVersion: map['keyVersion'] as int?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory EvidenceItem.fromJson(String source) {
    return EvidenceItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
