import 'dart:convert';

enum EvidenceType { photo, video, audio }

class EvidenceItem {
  final String id;
  final EvidenceType type;
  final String filePath;
  final String originalFileName;
  final DateTime capturedAt;
  final int fileSizeBytes;

  /// SHA-256 will be added later.
  /// Encryption will also be added later.
  final String? hash;

  const EvidenceItem({
    required this.id,
    required this.type,
    required this.filePath,
    required this.originalFileName,
    required this.capturedAt,
    required this.fileSizeBytes,
    this.hash,
  });

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'filePath': filePath,
      'originalFileName': originalFileName,
      'capturedAt': capturedAt.toIso8601String(),
      'fileSizeBytes': fileSizeBytes,
      'hash': hash,
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
      hash: map['hash'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory EvidenceItem.fromJson(String source) {
    return EvidenceItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
