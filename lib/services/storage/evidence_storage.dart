import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/evidence/evidence_item.dart';

class EvidenceStorage {
  EvidenceStorage._();

  static final EvidenceStorage instance = EvidenceStorage._();

  static const String _indexKey = 'immutable_evidence_index';

  final Uuid _uuid = const Uuid();

  Future<Directory> _evidenceDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();

    final directory = Directory('${appDirectory.path}/evidence');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  /// Saves a captured evidence file into the application's
  /// protected evidence directory.
  ///
  /// There is intentionally NO deleteEvidence() or
  /// updateEvidence() method.
  Future<EvidenceItem> addEvidence({
    required File sourceFile,
    required EvidenceType type,
    String? originalFileName,
  }) async {
    if (!await sourceFile.exists()) {
      throw Exception('Evidence source file does not exist.');
    }

    final directory = await _evidenceDirectory();

    final id = _uuid.v4();

    final extension = _extensionOf(sourceFile.path, type);

    final storedFileName = '$id$extension';

    final destination = File('${directory.path}/$storedFileName');

    // Copy instead of moving so the original capture remains
    // untouched until the evidence copy is successfully stored.
    await sourceFile.copy(destination.path);

    final stat = await destination.stat();

    final item = EvidenceItem(
      id: id,
      type: type,
      filePath: destination.path,
      originalFileName: originalFileName ?? _fileName(sourceFile.path),
      capturedAt: DateTime.now().toUtc(),
      fileSizeBytes: stat.size,
      hash: null,
    );

    await _appendToIndex(item);

    return item;
  }

  Future<List<EvidenceItem>> getEvidence() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_indexKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);

    if (decoded is! List) {
      return [];
    }

    final items = decoded
        .whereType<Map<String, dynamic>>()
        .map(EvidenceItem.fromMap)
        .toList();

    // Newest first.
    items.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    return items;
  }

  Future<void> _appendToIndex(EvidenceItem item) async {
    final prefs = await SharedPreferences.getInstance();

    final current = await getEvidence();

    final updated = [item, ...current];

    final encoded = jsonEncode(updated.map((e) => e.toMap()).toList());

    final success = await prefs.setString(_indexKey, encoded);

    if (!success) {
      throw Exception('Could not persist evidence index.');
    }
  }

  String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String _extensionOf(String path, EvidenceType type) {
    final fileName = _fileName(path);

    final dot = fileName.lastIndexOf('.');

    if (dot != -1) {
      return fileName.substring(dot);
    }

    switch (type) {
      case EvidenceType.photo:
        return '.jpg';

      case EvidenceType.video:
        return '.mp4';

      case EvidenceType.audio:
        return '.m4a';
    }
  }
}
