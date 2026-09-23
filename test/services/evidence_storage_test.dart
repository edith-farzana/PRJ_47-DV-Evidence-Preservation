import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/services/crypto/crypto_service.dart';
import 'package:secure_evidence_app/services/crypto/key_manager.dart';
import 'package:secure_evidence_app/services/storage/evidence_index.dart';
import 'package:secure_evidence_app/services/storage/evidence_storage.dart';

import '../helpers/fake_secure_store.dart';

/// A store whose writes to [failKey] throw, to simulate the index write
/// failing part-way through a capture.
class _FailingStore extends FakeSecureStore {
  _FailingStore(this.failKey);

  final String failKey;
  bool failing = false;

  @override
  Future<void> write(String key, String value) async {
    if (failing && key == failKey) {
      throw const FileSystemException('simulated storage failure');
    }
    return super.write(key, value);
  }
}

/// Encrypts normally but reports that verification failed.
class _UnverifiableCrypto extends CryptoService {
  @override
  Future<bool> verifyIntegrity({
    required File source,
    required SecretKey masterKey,
    required String wrappedDek,
    required String nonce,
    required String gcmTag,
    required String plaintextSha256,
  }) async => false;
}

void main() {
  late Directory workspace;
  late FakeSecureStore store;
  late KeyManager keyManager;
  late EvidenceStorage storage;

  final crypto = CryptoService();

  EvidenceStorage newStorage({CryptoService? cryptoService}) {
    return EvidenceStorage(
      baseDirectory: workspace,
      keyManager: keyManager,
      store: store,
      crypto: cryptoService,
    );
  }

  Future<File> writeSource(String name, List<int> bytes) async {
    final file = File('${workspace.path}/capture/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// A minimal JPEG-looking payload: SOI marker, JFIF header, noise.
  Uint8List fakeJpeg() {
    final random = Random(7);
    return Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, // SOI + APP0
      ...'JFIF'.codeUnits,
      ...List<int>.generate(4096, (_) => random.nextInt(256)),
    ]);
  }

  /// A minimal MP4-looking payload: box size, then `ftyp`.
  Uint8List fakeMp4() {
    return Uint8List.fromList([
      0x00,
      0x00,
      0x00,
      0x20,
      ...'ftypisom'.codeUnits,
      ...List<int>.filled(4096, 0x42),
    ]);
  }

  Future<void> useStore(FakeSecureStore newStore) async {
    store = newStore;
    keyManager = KeyManager(store, kdfIterations: 1000);
    await keyManager.setUp(pin: '1234', unlockSequence: '7×3-1=');
    storage = newStorage();
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('storage_test_');
    await useStore(FakeSecureStore());
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  // =================================================================
  // Encryption actually happens
  // =================================================================

  group('stored evidence is encrypted', () {
    test('the stored blob is not byte-identical to the source', () async {
      final original = fakeJpeg();
      final source = await writeSource('photo.jpg', original);

      final item = await storage.addEvidence(
        sourceFile: source,
        type: EvidenceType.photo,
      );

      final stored = await File(item.filePath).readAsBytes();

      // Same length is expected: GCM is a stream cipher, and the tag is
      // kept in the metadata rather than in the blob.
      expect(stored, isNot(equals(original)));
    });

    test('the blob carries no JPEG or MP4 header', () async {
      final photo = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );
      final video = await storage.addEvidence(
        sourceFile: await writeSource('video.mp4', fakeMp4()),
        type: EvidenceType.video,
      );

      final photoBytes = await File(photo.filePath).readAsBytes();
      final videoBytes = await File(video.filePath).readAsBytes();

      expect(photoBytes.sublist(0, 3), isNot([0xFF, 0xD8, 0xFF]));
      expect(String.fromCharCodes(photoBytes), isNot(contains('JFIF')));
      expect(String.fromCharCodes(videoBytes), isNot(contains('ftyp')));
    });

    test(
      'the blob name reveals neither the type nor the original name',
      () async {
        final item = await storage.addEvidence(
          sourceFile: await writeSource('IMG_20260918.jpg', fakeJpeg()),
          type: EvidenceType.photo,
        );

        final name = item.filePath.split(Platform.pathSeparator).last;

        expect(name, endsWith('.enc'));
        expect(name, isNot(contains('jpg')));
        expect(name, isNot(contains('IMG')));
      },
    );

    test('the blob decrypts back to exactly the source', () async {
      final original = fakeJpeg();

      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', original),
        type: EvidenceType.photo,
      );

      final recovered = await crypto.decryptToFile(
        source: File(item.filePath),
        destination: File('${workspace.path}/recovered.jpg'),
        masterKey: keyManager.masterKey,
        wrappedDek: item.wrappedDek!,
        nonce: item.nonce!,
        gcmTag: item.gcmTag!,
        plaintextSha256: item.plaintextSha256!,
      );

      expect(await recovered.readAsBytes(), original);
      expect(item.isEncrypted, isTrue);
    });

    test('nothing in the evidence directory is plaintext', () async {
      await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
        originalFileName: 'bruises_18sep.jpg',
      );

      final names = await storage.directory
          .list()
          .map((entry) => entry.path.split(Platform.pathSeparator).last)
          .toList();

      expect(names, everyElement(endsWith('.enc')));

      // The original name lives only inside the encrypted index.
      for (final entry in await storage.directory.list().toList()) {
        final bytes = await File(entry.path).readAsBytes();
        expect(String.fromCharCodes(bytes), isNot(contains('bruises')));
      }
    });
  });

  // =================================================================
  // The plaintext source
  // =================================================================

  group('plaintext source', () {
    test('is deleted after a successful add', () async {
      final source = await writeSource('photo.jpg', fakeJpeg());

      await storage.addEvidence(sourceFile: source, type: EvidenceType.photo);

      expect(await source.exists(), isFalse);
    });

    test('is kept, and no blob left behind, when verification fails', () async {
      final source = await writeSource('photo.jpg', fakeJpeg());
      final failing = newStorage(cryptoService: _UnverifiableCrypto());

      await expectLater(
        failing.addEvidence(sourceFile: source, type: EvidenceType.photo),
        throwsA(isA<EvidenceIntegrityException>()),
      );

      expect(await source.exists(), isTrue);
      expect(await storage.directory.list().toList(), isEmpty);
    });

    test(
      'is kept, and no blob left behind, when the index write fails',
      () async {
        final failingStore = _FailingStore('idx.v1.seal');
        await useStore(failingStore);

        final source = await writeSource('photo.jpg', fakeJpeg());
        failingStore.failing = true;

        await expectLater(
          storage.addEvidence(sourceFile: source, type: EvidenceType.photo),
          throwsA(isA<FileSystemException>()),
        );

        expect(await source.exists(), isTrue);

        final blobs = await storage.directory
            .list()
            .where((entry) => entry.path.endsWith('.enc'))
            .where((entry) => !entry.path.endsWith('index.enc'))
            .toList();
        expect(blobs, isEmpty);

        failingStore.failing = false;
        expect(await storage.getEvidence(), isEmpty);
      },
    );

    test('is kept when the vault is locked', () async {
      final source = await writeSource('photo.jpg', fakeJpeg());
      keyManager.lock();

      await expectLater(
        storage.addEvidence(sourceFile: source, type: EvidenceType.photo),
        throwsStateError,
      );

      expect(await source.exists(), isTrue);
    });
  });

  // =================================================================
  // Listing
  // =================================================================

  group('listing', () {
    test('a fresh vault is empty', () async {
      expect(await storage.getEvidence(), isEmpty);
    });

    test('items are listed newest first and survive a restart', () async {
      for (final name in ['a.jpg', 'b.jpg', 'c.jpg']) {
        await storage.addEvidence(
          sourceFile: await writeSource(name, fakeJpeg()),
          type: EvidenceType.photo,
          originalFileName: name,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // New KeyManager + storage over the same files and store.
      keyManager = KeyManager(store, kdfIterations: 1000);
      await keyManager.unlock('1234');
      final restarted = newStorage();

      final items = await restarted.getEvidence();

      expect(items.map((item) => item.originalFileName), [
        'c.jpg',
        'b.jpg',
        'a.jpg',
      ]);
    });

    test('a tampered index is reported, never shown as empty', () async {
      await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      final index = File('${storage.directory.path}/index.enc');
      final bytes = await index.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 0x01;
      await index.writeAsBytes(bytes);

      await expectLater(
        storage.getEvidence(),
        throwsA(isA<EvidenceIndexCorruptedException>()),
      );
    });
  });

  // =================================================================
  // Viewing evidence
  // =================================================================

  group('opening evidence for viewing', () {
    test('decrypts back to exactly the captured bytes', () async {
      final original = fakeJpeg();

      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', original),
        type: EvidenceType.photo,
      );

      final preview = await storage.openPreview(item);

      expect(await preview.readAsBytes(), equals(original));
    });

    test('the plaintext never lands in the evidence directory', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      final preview = await storage.openPreview(item);

      expect(preview.path, startsWith(storage.previewDirectory.path));
      expect(preview.path, isNot(startsWith(storage.directory.path)));

      final stored = storage.directory.listSync().whereType<File>().map(
        (file) => file.path,
      );

      expect(stored.every((path) => !path.endsWith('.jpg')), isTrue);
    });

    test('keeps the original extension, so a player can decode it', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('clip.mp4', fakeMp4()),
        type: EvidenceType.video,
      );

      expect((await storage.openPreview(item)).path, endsWith('.mp4'));
    });

    test('closing destroys the decrypted copy', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      final preview = await storage.openPreview(item);
      expect(await preview.exists(), isTrue);

      await storage.closePreview(preview);

      expect(await preview.exists(), isFalse);
    });

    test('a preview left by a crash is swept at launch', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      // Opened and never closed: what a force-stop leaves behind.
      final orphan = await storage.openPreview(item);

      await newStorage().sweepPreviews();

      expect(await orphan.exists(), isFalse);
    });

    test('is refused while the vault is locked', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      keyManager.lock();

      await expectLater(storage.openPreview(item), throwsA(isA<StateError>()));
    });
  });

  // =================================================================
  // Integrity verification
  // =================================================================

  group('integrity verification', () {
    test('untouched evidence verifies, and the hashes match', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      final report = await storage.checkIntegrity(item);

      expect(report.verified, isTrue);
      expect(report.failure, isNull);
      expect(report.recalculatedPlaintextSha256, equals(item.plaintextSha256));
      expect(
        report.recalculatedCiphertextSha256,
        equals(item.ciphertextSha256),
      );
    });

    test('a modified blob fails, and says the stored file moved', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      final blob = File(item.filePath);
      final bytes = await blob.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 0x01;
      await blob.writeAsBytes(bytes);

      final report = await storage.checkIntegrity(item);

      expect(report.verified, isFalse);
      expect(report.ciphertextMatches, isFalse);
      // Decryption fails outright, so there is no plaintext to re-hash.
      expect(report.recalculatedPlaintextSha256, isNull);
      expect(report.failure, isNotNull);
    });

    test('a missing blob is a finding, not a pass', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      await File(item.filePath).delete();

      final report = await storage.checkIntegrity(item);

      expect(report.blobExists, isFalse);
      expect(report.verified, isFalse);
      expect(report.failure, contains('missing'));
    });

    test('verification leaves no decrypted copy behind', () async {
      final item = await storage.addEvidence(
        sourceFile: await writeSource('photo.jpg', fakeJpeg()),
        type: EvidenceType.photo,
      );

      await storage.checkIntegrity(item);

      final left = storage.previewDirectory.existsSync()
          ? storage.previewDirectory.listSync()
          : const <FileSystemEntity>[];

      expect(left, isEmpty);
    });

    test('a record with no crypto metadata cannot be verified', () async {
      final legacy = EvidenceItem(
        id: 'legacy',
        type: EvidenceType.photo,
        filePath: '/nowhere/legacy.jpg',
        originalFileName: 'legacy.jpg',
        capturedAt: DateTime.utc(2026, 1, 1),
        fileSizeBytes: 10,
      );

      final report = await storage.checkIntegrity(legacy);

      expect(report.verified, isFalse);
      expect(report.failure, contains('before evidence was encrypted'));
    });
  });
}
