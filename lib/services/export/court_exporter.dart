import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:uuid/uuid.dart';

import '../../models/audit/audit_entry.dart';
import '../../models/evidence/evidence_item.dart';
import '../../models/evidence/verification_verdict.dart';
import '../audit/audit_log.dart';
import '../storage/evidence_storage.dart';
import '../storage/secure_delete.dart';
import '../sync/evidence_sync.dart';
import 'export_manifest.dart';
import 'export_password.dart';
import 'manifest_pdf.dart';

/// How far an export has got, for the progress text.
class ExportProgress {
  const ExportProgress(this.done, this.total);

  final int done;
  final int total;
}

/// Thrown when the screen that started an export goes away -- most
/// likely a panic -- so the work stops and cleans up.
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => 'ExportCancelledException';
}

class ExportResult {
  const ExportResult({
    required this.bundle,
    required this.password,
    required this.manifest,
  });

  /// Null when none of the selected items could be exported; [manifest]
  /// then says why for each.
  final File? bundle;

  /// Shown once, never stored. Null for an unprotected bundle.
  final String? password;

  final ExportManifest manifest;

  /// Destroys the bundle. Called when the export screen closes: once
  /// shared, the receiving app has its own copy.
  Future<void> discard() async {
    final file = bundle;
    if (file != null) await destroyPlaintext(file);
  }
}

/// Builds the bundle a lawyer or court can use: the evidence, a manifest
/// of fingerprints and custody, and instructions for checking it without
/// this app.
///
/// This is the one place evidence deliberately leaves protection, so it
/// is written around what must not happen:
///
///  * nothing unverified goes out -- an item that fails is listed, not
///    included;
///  * nothing decrypted is left behind -- every intermediate file is
///    destroyed in `finally`, whatever happens, and the directory is swept
///    at launch in case the process dies first;
///  * nothing leaks through names -- ZIP encryption hides contents, not
///    file names, so every name is neutral.
class CourtExporter {
  CourtExporter({
    required this._storage,
    required this._sync,
    required this._audit,
    required Directory cacheDirectory,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now,
       directory = Directory('${cacheDirectory.path}/export');

  final EvidenceStorage _storage;
  final EvidenceSync _sync;
  final AuditLog _audit;
  final DateTime Function() _now;

  /// Where bundles and their intermediate files are built.
  final Directory directory;

  /// The ZIP library encrypts each file in memory, so the largest file
  /// sets peak memory. Beyond this, a protected export would risk the
  /// app being killed mid-way on an ordinary phone.
  static const int maxProtectedItemBytes = 256 * 1024 * 1024;

  static const Uuid _uuid = Uuid();

  /// Exports [items]. [protect] makes it an AES-256 ZIP with a generated
  /// password.
  ///
  /// Throws [ExportCancelledException] if [isCancelled] turns true, and
  /// lets a locked vault's `StateError` through: either way, nothing is
  /// left behind.
  Future<ExportResult> export(
    List<EvidenceItem> items, {
    required bool protect,
    void Function(ExportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) throw const ExportCancelledException();
    }

    final work = Directory('${directory.path}/${_uuid.v4()}');
    await work.create(recursive: true);

    final password = protect ? ExportPassword.generate() : null;

    final exported = <ExportedItem>[];
    final notExported = <NotExportedItem>[];
    final contents = <(File, String)>[];

    File? bundle;

    try {
      final chain = await _audit.verify();

      List<AuditEntry> log;
      try {
        log = await _audit.entries();
      } on AuditLogCorruptedException {
        // The chain report already says the log is broken; with nothing
        // trustworthy to quote, custody is left empty.
        log = const [];
      }

      for (var i = 0; i < items.length; i++) {
        checkCancelled();
        onProgress?.call(ExportProgress(i, items.length));

        final item = items[i];
        final capturedAt = item.capturedAt.toUtc().toIso8601String();

        void skip(String reason) => notExported.add(
          NotExportedItem(
            evidenceId: item.id,
            type: item.type.name,
            capturedAt: capturedAt,
            reason: reason,
          ),
        );

        if (protect && item.fileSizeBytes > maxProtectedItemBytes) {
          skip(
            'Too large to include in a password-protected bundle on this '
            'phone (${item.fileSizeLabel}). Export it on its own.',
          );
          continue;
        }

        // In parallel, but not with a record `.wait`: that would wrap a
        // locked vault's StateError in a ParallelWaitError. The server
        // check never throws, so starting it first and awaiting it after
        // loses nothing.
        final serverCheck = _sync.checkServerRecord(item);
        final report = await _storage.checkIntegrity(item);
        final server = await serverCheck;

        final result = VerificationVerdict(local: report, server: server);

        if (result.verdict == Verdict.notVerified) {
          skip('Failed verification: ${result.explanation}');
          continue;
        }

        final preview = await _storage.openPreview(item);
        final extension = preview.path.contains('.')
            ? preview.path.substring(preview.path.lastIndexOf('.'))
            : '';
        final name =
            'item-${(exported.length + 1).toString().padLeft(2, '0')}$extension';
        final file = await _moveInto(preview, work, name);

        contents.add((file, name));

        // The file that goes into the bundle, hashed again. Decryption has
        // already checked it; this checks the thing actually being handed
        // over.
        if (await _sha256(file) != item.plaintextSha256) {
          contents.removeLast();
          await destroyPlaintext(file);
          skip('The decrypted copy did not match the recorded fingerprint.');
          continue;
        }

        exported.add(
          ExportedItem(
            bundleName: name,
            evidenceId: item.id,
            type: item.type.name,
            capturedAt: capturedAt,
            sizeBytes: await file.length(),
            sha256: item.plaintextSha256!,
            storedFileSha256: item.ciphertextSha256!,
            verdict: result.verdict.name,
            serverCheck: server.status.name,
            serverNote: server.reason,
            custody: _custodyOf(item.id, log),
          ),
        );
      }

      checkCancelled();
      onProgress?.call(ExportProgress(items.length, items.length));

      final manifest = ExportManifest(
        generatedAt: _now().toUtc().toIso8601String(),
        passwordProtected: protect,
        logIntact: chain.intact,
        logStatus: chain.intact ? 'intact' : chain.problem!,
        logEntries: chain.entryCount,
        logHeadHash: log.isEmpty ? null : log.last.hash,
        items: exported,
        notExported: notExported,
      );

      if (exported.isEmpty) {
        return ExportResult(bundle: null, password: null, manifest: manifest);
      }

      final json = utf8.encode(manifest.toPrettyJson());
      final jsonHash = crypto.sha256.convert(json).toString();

      final jsonFile = File('${work.path}/manifest.json');
      final pdfFile = File('${work.path}/manifest.pdf');
      final readmeFile = File('${work.path}/README.txt');

      await jsonFile.writeAsBytes(json, flush: true);
      await pdfFile.writeAsBytes(
        await ManifestPdf.render(manifest, manifestSha256: jsonHash),
        flush: true,
      );
      await readmeFile.writeAsString(
        manifest.readme(manifestSha256: jsonHash),
        flush: true,
      );

      checkCancelled();

      bundle = File('${directory.path}/${_bundleName()}');

      final encoder = ZipFileEncoder(password: password);
      encoder.create(bundle.path);

      // Media is already compressed; storing it saves time for nothing lost.
      for (final (file, name) in contents) {
        await encoder.addFile(file, name, ZipFileEncoder.store);
      }
      await encoder.addFile(pdfFile, 'manifest.pdf');
      await encoder.addFile(jsonFile, 'manifest.json');
      await encoder.addFile(readmeFile, 'README.txt');
      await encoder.close();

      // Part of the chain of custody: which items left, and whether they
      // left protected.
      await _audit.record(
        AuditEventType.exported,
        detail: {
          'items': [for (final item in exported) item.evidenceId],
          'protected': protect,
        },
      );

      return ExportResult(
        bundle: bundle,
        password: password,
        manifest: manifest,
      );
    } catch (_) {
      if (bundle != null) await destroyPlaintext(bundle);
      rethrow;
    } finally {
      // Every decrypted copy, whatever happened above.
      for (final (file, _) in contents) {
        await destroyPlaintext(file);
      }

      if (await work.exists()) {
        await for (final entity in work.list()) {
          if (entity is File) await destroyPlaintext(entity);
        }
        await work.delete(recursive: true);
      }
    }
  }

  /// Destroys anything a killed export left behind, and the copy the
  /// share sheet keeps for the receiving app. Called at launch, before
  /// anything can be exporting or sharing.
  static Future<void> sweep(Directory cacheDirectory) async {
    for (final name in const ['export', 'share_plus']) {
      final dir = Directory('${cacheDirectory.path}/$name');
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) await destroyPlaintext(entity);
      }

      await dir.delete(recursive: true);
    }
  }

  /// This item's entries from the activity log, including earlier exports
  /// that named it.
  static List<CustodyEvent> _custodyOf(String id, List<AuditEntry> log) {
    return [
      for (final entry in log)
        if (entry.evidenceId == id ||
            (entry.type == AuditEventType.exported.name &&
                (entry.detail['items'] as List?)?.contains(id) == true))
          CustodyEvent(seq: entry.seq, at: entry.at, event: entry.type),
    ];
  }

  /// A name that gives nothing away in a chat or an inbox. "evidence"
  /// would.
  String _bundleName() {
    final t = _now();
    String two(int n) => n.toString().padLeft(2, '0');

    return 'bundle-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.zip';
  }

  static Future<File> _moveInto(File file, Directory into, String name) async {
    final target = '${into.path}/$name';

    try {
      return await file.rename(target);
    } on FileSystemException {
      // Different filesystem: copy, then destroy the original.
      final copy = await file.copy(target);
      await destroyPlaintext(file);
      return copy;
    }
  }

  static Future<String> _sha256(File file) async =>
      (await crypto.sha256.bind(file.openRead()).first).toString();
}
