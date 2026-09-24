import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/audit/audit_entry.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/services/audit/audit_log.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/export/court_exporter.dart';
import 'package:secure_evidence_app/services/storage/evidence_storage.dart';

import '../helpers/fake_secure_store.dart';
import '../helpers/offline_sync.dart';

void main() {
  late Directory workspace;
  late Directory cache;
  late FakeSecureStore store;
  late KeyManager keyManager;
  late EvidenceStorage storage;
  late AuditLog audit;
  late CourtExporter exporter;

  final originals = <String, Uint8List>{};

  Uint8List bytes(int seed, {int length = 4096}) {
    final random = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<EvidenceItem> capture(
    String name,
    EvidenceType type, {
    required int seed,
  }) async {
    final data = bytes(seed);
    final source = File('${workspace.path}/capture/$name');
    await source.parent.create(recursive: true);
    await source.writeAsBytes(data);

    final item = await storage.addEvidence(
      sourceFile: source,
      type: type,
      originalFileName: name,
    );

    originals[item.id] = data;
    await audit.record(AuditEventType.captured, evidenceId: item.id);

    return item;
  }

  Archive open(File bundle, {String? password}) =>
      ZipDecoder().decodeBytes(bundle.readAsBytesSync(), password: password);

  /// Everything still on disk under the exporter's working directory.
  List<String> leftovers() {
    if (!exporter.directory.existsSync()) return const [];
    return exporter.directory
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .toList();
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('export_test_');
    cache = Directory('${workspace.path}/cache');
    store = FakeSecureStore();
    keyManager = KeyManager(store, kdfIterations: 1000);
    await keyManager.setUp(pin: '1234', unlockSequence: '7×3-1=');

    storage = EvidenceStorage(
      baseDirectory: workspace,
      keyManager: keyManager,
      store: store,
    );

    audit = AuditLog(
      baseDirectory: workspace,
      store: store,
      keyManager: keyManager,
    );

    exporter = CourtExporter(
      storage: storage,
      // No server: every item comes out "verified on this phone".
      sync: offlineSync(),
      audit: audit,
      cacheDirectory: cache,
    );

    originals.clear();
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  group('a protected bundle', () {
    test(
      'opens with its password, and holds exactly what was captured',
      () async {
        final photo = await capture(
          'bruises_18sep.jpg',
          EvidenceType.photo,
          seed: 1,
        );
        final audio = await capture('call.m4a', EvidenceType.audio, seed: 2);

        final result = await exporter.export([photo, audio], protect: true);
        final archive = open(result.bundle!, password: result.password);

        expect(archive.findFile('item-01.jpg')!.content, originals[photo.id]);
        expect(archive.findFile('item-02.m4a')!.content, originals[audio.id]);
        expect(archive.findFile('manifest.pdf'), isNotNull);
        expect(archive.findFile('manifest.json'), isNotNull);
        expect(archive.findFile('README.txt'), isNotNull);
      },
    );

    test('does not open with the wrong password', () async {
      final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

      final result = await exporter.export([photo], protect: true);

      Uint8List? read(String password) {
        try {
          return open(
            result.bundle!,
            password: password,
          ).findFile('item-01.jpg')?.content;
        } catch (_) {
          return null;
        }
      }

      expect(read('AAAA-BBBB-CCCC-DDDD-EEEE'), isNot(originals[photo.id]));
    });

    test('its contents are not readable without a password', () async {
      final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

      final result = await exporter.export([photo], protect: true);
      final raw = await result.bundle!.readAsBytes();
      final sample = originals[photo.id]!.sublist(0, 64);

      // The evidence bytes do not appear anywhere in the file.
      expect(
        String.fromCharCodes(raw).contains(String.fromCharCodes(sample)),
        isFalse,
      );
    });
  });

  test('a plain bundle opens without a password', () async {
    final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

    final result = await exporter.export([photo], protect: false);

    expect(result.password, isNull);
    expect(
      open(result.bundle!).findFile('item-01.jpg')!.content,
      originals[photo.id],
    );
  });

  // The claim the whole bundle rests on: anyone can check it with
  // standard tools, without this app.
  test('each file hashes to exactly what the shipped manifest says', () async {
    final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);
    final video = await capture('b.mp4', EvidenceType.video, seed: 3);

    final result = await exporter.export([photo, video], protect: true);
    final archive = open(result.bundle!, password: result.password);

    final shipped = jsonDecode(
      utf8.decode(archive.findFile('manifest.json')!.content),
    ) as Map<String, dynamic>;

    for (final entry in shipped['items'] as List) {
      final item = entry as Map<String, dynamic>;
      final content = archive.findFile(item['file'] as String)!.content;

      expect(crypto.sha256.convert(content).toString(), item['sha256']);
    }

    expect((shipped['items'] as List), hasLength(2));
  });

  test('the README carries the fingerprint of the manifest', () async {
    final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

    final result = await exporter.export([photo], protect: false);
    final archive = open(result.bundle!);

    final json = archive.findFile('manifest.json')!.content;
    final readme = utf8.decode(archive.findFile('README.txt')!.content);

    expect(readme, contains(crypto.sha256.convert(json).toString()));
  });

  group('what leaves the phone', () {
    test('a tampered item is left out, and listed with the reason', () async {
      final good = await capture('a.jpg', EvidenceType.photo, seed: 1);
      final bad = await capture('b.jpg', EvidenceType.photo, seed: 2);

      final blob = File(bad.filePath);
      final data = await blob.readAsBytes();
      data[data.length ~/ 2] ^= 0x01;
      await blob.writeAsBytes(data);

      final result = await exporter.export([good, bad], protect: true);

      expect(result.manifest.items.map((item) => item.evidenceId), [good.id]);
      expect(result.manifest.notExported.single.evidenceId, bad.id);
      expect(
        result.manifest.notExported.single.reason,
        contains('Failed verification'),
      );
      expect(
        open(
          result.bundle!,
          password: result.password,
        ).files.where((file) => file.name.startsWith('item-')),
        hasLength(1),
      );
    });

    test('an item too large to protect is left out, not risked', () async {
      final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);
      final huge = EvidenceItem(
        id: photo.id,
        type: photo.type,
        filePath: photo.filePath,
        originalFileName: photo.originalFileName,
        capturedAt: photo.capturedAt,
        fileSizeBytes: CourtExporter.maxProtectedItemBytes + 1,
        plaintextSha256: photo.plaintextSha256,
        ciphertextSha256: photo.ciphertextSha256,
        wrappedDek: photo.wrappedDek,
        nonce: photo.nonce,
        gcmTag: photo.gcmTag,
        encryptionAlgorithm: photo.encryptionAlgorithm,
        keyVersion: photo.keyVersion,
      );

      final result = await exporter.export([huge], protect: true);

      expect(result.bundle, isNull);
      expect(result.manifest.notExported.single.reason, contains('Too large'));
    });

    test('names inside and outside the ZIP give nothing away', () async {
      final photo = await capture(
        'bruises_18sep.jpg',
        EvidenceType.photo,
        seed: 1,
      );

      final result = await exporter.export([photo], protect: true);
      final names = open(
        result.bundle!,
        password: result.password,
      ).files.map((file) => file.name);

      for (final name in names) {
        expect(
          name,
          matches(
            RegExp(
              r'^(item-\d{2}\.[a-z0-9]+|manifest\.pdf|manifest\.json|README\.txt)$',
            ),
          ),
        );
      }

      final bundleName = result.bundle!.uri.pathSegments.last;
      expect(bundleName, matches(RegExp(r'^bundle-\d{8}-\d{6}\.zip$')));
    });

    test('the manifest carries no keys and no original filenames', () async {
      final photo = await capture(
        'bruises_18sep.jpg',
        EvidenceType.photo,
        seed: 1,
      );

      final result = await exporter.export([photo], protect: false);
      final json = utf8.decode(
        open(result.bundle!).findFile('manifest.json')!.content,
      );

      expect(json, isNot(contains(photo.wrappedDek!)));
      expect(json, isNot(contains(photo.nonce!)));
      expect(json, isNot(contains(photo.gcmTag!)));
      expect(json, isNot(contains('wrappedDek')));
      expect(json, isNot(contains('bruises')));
    });

    test('custody lists the item\'s own history only', () async {
      final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);
      await audit.record(AuditEventType.viewed, evidenceId: photo.id);
      await audit.record(AuditEventType.panic);

      final result = await exporter.export([photo], protect: true);
      final custody = result.manifest.items.single.custody.map((e) => e.event);

      expect(custody, ['captured', 'viewed']);
      expect(custody, isNot(contains('panic')));
    });
  });

  group('cleaning up', () {
    test('nothing decrypted remains, only the bundle', () async {
      final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

      final result = await exporter.export([photo], protect: true);

      expect(leftovers(), [result.bundle!.path]);
      expect(
        storage.previewDirectory.existsSync()
            ? storage.previewDirectory.listSync()
            : const [],
        isEmpty,
      );
    });

    test('discarding destroys the bundle', () async {
      final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

      final result = await exporter.export([photo], protect: true);
      await result.discard();

      expect(leftovers(), isEmpty);
    });

    // Panic destroys the key; the export must stop and leave nothing.
    test('locking mid-export aborts it and leaves nothing behind', () async {
      final items = [
        await capture('a.jpg', EvidenceType.photo, seed: 1),
        await capture('b.jpg', EvidenceType.photo, seed: 2),
        await capture('c.jpg', EvidenceType.photo, seed: 3),
      ];

      await expectLater(
        exporter.export(
          items,
          protect: true,
          onProgress: (progress) {
            if (progress.done == 1) keyManager.lock();
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(leftovers(), isEmpty);
    });

    test('closing the screen cancels it and leaves nothing behind', () async {
      final items = [
        await capture('a.jpg', EvidenceType.photo, seed: 1),
        await capture('b.jpg', EvidenceType.photo, seed: 2),
      ];
      var closed = false;

      await expectLater(
        exporter.export(
          items,
          protect: true,
          onProgress: (progress) => closed = progress.done == 1,
          isCancelled: () => closed,
        ),
        throwsA(isA<ExportCancelledException>()),
      );

      expect(leftovers(), isEmpty);
    });

    test('when nothing can be exported, no bundle is made', () async {
      final bad = await capture('a.jpg', EvidenceType.photo, seed: 1);
      await File(bad.filePath).delete();

      final result = await exporter.export([bad], protect: true);

      expect(result.bundle, isNull);
      expect(result.manifest.notExported, hasLength(1));
      expect(leftovers(), isEmpty);
    });

    test('the launch sweep clears export and share leftovers', () async {
      for (final path in ['export/old/item-01.jpg', 'share_plus/bundle.zip']) {
        final file = File('${cache.path}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsBytes([1, 2, 3]);
      }

      await CourtExporter.sweep(cache);

      expect(Directory('${cache.path}/export').existsSync(), isFalse);
      expect(Directory('${cache.path}/share_plus').existsSync(), isFalse);
    });
  });

  test('the export is recorded in the activity log', () async {
    final photo = await capture('a.jpg', EvidenceType.photo, seed: 1);

    await exporter.export([photo], protect: true);

    final last = (await audit.entries()).last;

    expect(last.type, AuditEventType.exported.name);
    expect(last.detail['items'], [photo.id]);
    expect(last.detail['protected'], isTrue);
    expect((await audit.verify()).intact, isTrue);
  });
}
