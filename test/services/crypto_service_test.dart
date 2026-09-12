import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/services/crypto/crypto_service.dart';

void main() {
  late CryptoService crypto;
  late Directory workspace;
  late SecretKey masterKey;

  setUp(() async {
    crypto = CryptoService();

    workspace = await Directory.systemTemp.createTemp('crypto_test_');

    masterKey = await AesGcm.with256bits().newSecretKey();
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  File fileAt(String name) => File('${workspace.path}/$name');

  Future<File> writeFile(String name, List<int> bytes) async {
    final file = fileAt(name);
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Deterministic pseudo-random payload, so a failure is reproducible.
  Uint8List payload(int length, {int seed = 42}) {
    final random = Random(seed);

    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  // =================================================================
  // Round trip
  // =================================================================

  group('round trip', () {
    test('decrypted bytes are identical to the original', () async {
      final original = payload(64 * 1024);

      final source = await writeFile('original.bin', original);
      final encrypted = fileAt('original.enc');

      final result = await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );

      final recovered = await crypto.decryptToFile(
        source: encrypted,
        destination: fileAt('recovered.bin'),
        masterKey: masterKey,
        wrappedDek: result.wrappedDek,
        nonce: result.nonce,
        gcmTag: result.gcmTag,
        plaintextSha256: result.plaintextSha256,
      );

      expect(await recovered.readAsBytes(), equals(original));
    });

    test('an empty file round trips', () async {
      final source = await writeFile('empty.bin', <int>[]);
      final encrypted = fileAt('empty.enc');

      final result = await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );

      final recovered = await crypto.decryptToFile(
        source: encrypted,
        destination: fileAt('empty_out.bin'),
        masterKey: masterKey,
        wrappedDek: result.wrappedDek,
        nonce: result.nonce,
        gcmTag: result.gcmTag,
        plaintextSha256: result.plaintextSha256,
      );

      expect(await recovered.readAsBytes(), isEmpty);
    });

    test('the encrypted blob does not contain the plaintext', () async {
      final marker = utf8.encode('CONFIDENTIAL-EVIDENCE-MARKER');

      final source = await writeFile('marked.bin', marker);
      final encrypted = fileAt('marked.enc');

      await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );

      final blob = await encrypted.readAsBytes();

      expect(
        _containsSequence(blob, marker),
        isFalse,
        reason: 'plaintext leaked into the encrypted blob',
      );
    });

    test('two encryptions of the same file differ', () async {
      final source = await writeFile('same.bin', payload(4096));

      final first = fileAt('first.enc');
      final second = fileAt('second.enc');

      final resultA = await crypto.encryptFile(
        source: source,
        destination: first,
        masterKey: masterKey,
      );

      final resultB = await crypto.encryptFile(
        source: source,
        destination: second,
        masterKey: masterKey,
      );

      // Same plaintext, same evidentiary hash...
      expect(resultA.plaintextSha256, equals(resultB.plaintextSha256));

      // ...but a fresh DEK and nonce each time, so the ciphertext must
      // differ. Identical ciphertext would mean nonce reuse, which is
      // catastrophic for AES-GCM.
      expect(resultA.nonce, isNot(equals(resultB.nonce)));
      expect(
        await first.readAsBytes(),
        isNot(equals(await second.readAsBytes())),
      );
    });
  });

  // =================================================================
  // Hashing
  // =================================================================

  group('hashing', () {
    test('is stable across runs for the same input', () async {
      final file = await writeFile('stable.bin', payload(8192));

      expect(await crypto.hashFile(file), equals(await crypto.hashFile(file)));
    });

    test('changes for a one-byte difference', () async {
      final bytes = payload(4096);

      final a = await writeFile('a.bin', bytes);

      final mutated = Uint8List.fromList(bytes);
      mutated[1234] = mutated[1234] ^ 0xFF;

      final b = await writeFile('b.bin', mutated);

      expect(await crypto.hashFile(a), isNot(equals(await crypto.hashFile(b))));
    });

    test('matches a known SHA-256 vector', () async {
      // SHA-256("abc"), the standard NIST test vector.
      final file = await writeFile('abc.txt', utf8.encode('abc'));

      expect(
        await crypto.hashFile(file),
        equals(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      );
    });

    test('streams a large file without exhausting memory', () async {
      // 50MB. If hashing ever regresses to readAsBytes() this either
      // fails outright on a constrained runner or takes obviously long.
      final file = fileAt('large.bin');

      final sink = file.openWrite();
      final chunk = payload(1024 * 1024);

      for (var i = 0; i < 50; i++) {
        sink.add(chunk);
      }

      await sink.flush();
      await sink.close();

      expect(await file.length(), equals(50 * 1024 * 1024));

      final digest = await crypto.hashFile(file);

      expect(digest, hasLength(64));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // =================================================================
  // Tamper detection
  // =================================================================

  group('tamper detection', () {
    late File source;
    late File encrypted;
    late EncryptionResult result;

    setUp(() async {
      source = await writeFile('evidence.bin', payload(16 * 1024));
      encrypted = fileAt('evidence.enc');

      result = await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );
    });

    Future<void> expectRejected(Future<void> Function() action) async {
      await expectLater(action(), throwsA(isA<Exception>()));
    }

    test('a flipped ciphertext byte fails authentication', () async {
      final blob = await encrypted.readAsBytes();

      blob[blob.length ~/ 2] = blob[blob.length ~/ 2] ^ 0xFF;

      await encrypted.writeAsBytes(blob);

      await expectRejected(
        () => crypto.decryptToFile(
          source: encrypted,
          destination: fileAt('out.bin'),
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
      );
    });

    test('a truncated blob fails authentication', () async {
      final blob = await encrypted.readAsBytes();

      await encrypted.writeAsBytes(blob.sublist(0, blob.length - 64));

      await expectRejected(
        () => crypto.decryptToFile(
          source: encrypted,
          destination: fileAt('out.bin'),
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
      );
    });

    test('a substituted plaintext hash fails via the AAD binding', () async {
      // The attack this closes: swap the recorded hash so that a
      // substituted file appears to verify. AAD binding makes the
      // ciphertext and the hash inseparable.
      final forged = crypto.hashBytes(utf8.encode('a different file'));

      await expectRejected(
        () => crypto.decryptToFile(
          source: encrypted,
          destination: fileAt('out.bin'),
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: forged,
        ),
      );
    });

    test('a modified GCM tag fails authentication', () async {
      final tag = base64.decode(result.gcmTag);

      tag[0] = tag[0] ^ 0xFF;

      await expectRejected(
        () => crypto.decryptToFile(
          source: encrypted,
          destination: fileAt('out.bin'),
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: base64.encode(tag),
          plaintextSha256: result.plaintextSha256,
        ),
      );
    });

    test('the wrong master key fails to unwrap the file key', () async {
      final wrongKey = await AesGcm.with256bits().newSecretKey();

      await expectLater(
        crypto.decryptToFile(
          source: encrypted,
          destination: fileAt('out.bin'),
          masterKey: wrongKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
        throwsA(isA<EvidenceIntegrityException>()),
      );
    });

    test('a truncated wrapped key is rejected', () async {
      final truncated = base64.encode(
        base64.decode(result.wrappedDek).sublist(0, 30),
      );

      await expectLater(
        crypto.decryptToFile(
          source: encrypted,
          destination: fileAt('out.bin'),
          masterKey: masterKey,
          wrappedDek: truncated,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
        throwsA(isA<EvidenceIntegrityException>()),
      );
    });

    test('no partial plaintext is left behind after a failure', () async {
      final blob = await encrypted.readAsBytes();
      blob[10] = blob[10] ^ 0xFF;
      await encrypted.writeAsBytes(blob);

      final destination = fileAt('partial.bin');

      await expectRejected(
        () => crypto.decryptToFile(
          source: encrypted,
          destination: destination,
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
      );

      // Half a decrypted file is worse than none: it looks like evidence.
      expect(await destination.exists(), isFalse);
    });
  });

  // =================================================================
  // Verification
  // =================================================================

  group('verifyIntegrity', () {
    test('passes for untouched evidence', () async {
      final source = await writeFile('intact.bin', payload(8192));
      final encrypted = fileAt('intact.enc');

      final result = await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );

      expect(
        await crypto.verifyIntegrity(
          source: encrypted,
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
        isTrue,
      );
    });

    test('returns false rather than throwing for tampered evidence', () async {
      final source = await writeFile('tampered.bin', payload(8192));
      final encrypted = fileAt('tampered.enc');

      final result = await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );

      final blob = await encrypted.readAsBytes();
      blob[100] = blob[100] ^ 0xFF;
      await encrypted.writeAsBytes(blob);

      expect(
        await crypto.verifyIntegrity(
          source: encrypted,
          masterKey: masterKey,
          wrappedDek: result.wrappedDek,
          nonce: result.nonce,
          gcmTag: result.gcmTag,
          plaintextSha256: result.plaintextSha256,
        ),
        isFalse,
      );
    });

    test('verifyCiphertext detects storage corruption', () async {
      final source = await writeFile('corrupt.bin', payload(4096));
      final encrypted = fileAt('corrupt.enc');

      final result = await crypto.encryptFile(
        source: source,
        destination: encrypted,
        masterKey: masterKey,
      );

      expect(
        await crypto.verifyCiphertext(
          source: encrypted,
          ciphertextSha256: result.ciphertextSha256,
        ),
        isTrue,
      );

      final blob = await encrypted.readAsBytes();
      blob[0] = blob[0] ^ 0xFF;
      await encrypted.writeAsBytes(blob);

      expect(
        await crypto.verifyCiphertext(
          source: encrypted,
          ciphertextSha256: result.ciphertextSha256,
        ),
        isFalse,
      );
    });
  });

  // =================================================================
  // Metadata
  // =================================================================

  group('EncryptionResult metadata', () {
    test('records the algorithm, key version and sizes', () async {
      final original = payload(5000);

      final source = await writeFile('meta.bin', original);

      final result = await crypto.encryptFile(
        source: source,
        destination: fileAt('meta.enc'),
        masterKey: masterKey,
      );

      expect(result.encryptionAlgorithm, equals('AES-256-GCM'));
      expect(result.keyVersion, equals(CryptoService.currentKeyVersion));
      expect(result.plaintextBytes, equals(original.length));
      expect(result.plaintextSha256, hasLength(64));
      expect(result.ciphertextSha256, hasLength(64));
    });

    test('nonce is 96 bits and the tag is 128 bits', () async {
      final source = await writeFile('sizes.bin', payload(1024));

      final result = await crypto.encryptFile(
        source: source,
        destination: fileAt('sizes.enc'),
        masterKey: masterKey,
      );

      expect(base64.decode(result.nonce), hasLength(12));
      expect(base64.decode(result.gcmTag), hasLength(16));
      expect(base64.decode(result.wrappedDek), hasLength(12 + 32 + 16));
    });
  });

  // =================================================================
  // EvidenceItem
  // =================================================================

  group('EvidenceItem', () {
    test('round trips every crypto field through JSON', () async {
      final source = await writeFile('item.bin', payload(2048));

      final result = await crypto.encryptFile(
        source: source,
        destination: fileAt('item.enc'),
        masterKey: masterKey,
      );

      final original = EvidenceItem.encrypted(
        id: 'abc-123',
        type: EvidenceType.photo,
        filePath: '/evidence/abc-123.enc',
        originalFileName: 'IMG_0001.jpg',
        capturedAt: DateTime.utc(2026, 9, 13, 10, 30),
        encryption: result,
      );

      final restored = EvidenceItem.fromJson(original.toJson());

      expect(restored.id, equals(original.id));
      expect(restored.type, equals(original.type));
      expect(restored.filePath, equals(original.filePath));
      expect(restored.originalFileName, equals(original.originalFileName));
      expect(restored.capturedAt, equals(original.capturedAt));
      expect(restored.fileSizeBytes, equals(original.fileSizeBytes));
      expect(restored.plaintextSha256, equals(original.plaintextSha256));
      expect(restored.ciphertextSha256, equals(original.ciphertextSha256));
      expect(restored.wrappedDek, equals(original.wrappedDek));
      expect(restored.nonce, equals(original.nonce));
      expect(restored.gcmTag, equals(original.gcmTag));
      expect(
        restored.encryptionAlgorithm,
        equals(original.encryptionAlgorithm),
      );
      expect(restored.keyVersion, equals(original.keyVersion));
    });

    test('isEncrypted is false for a pre-encryption record', () {
      final legacy = EvidenceItem(
        id: 'legacy',
        type: EvidenceType.audio,
        filePath: '/evidence/legacy.m4a',
        originalFileName: 'audio.m4a',
        capturedAt: DateTime.utc(2026, 9, 1),
        fileSizeBytes: 1024,
      );

      expect(legacy.isEncrypted, isFalse);
      expect(legacy.shortHash, equals('—'));
      expect(EvidenceItem.fromJson(legacy.toJson()).isEncrypted, isFalse);
    });

    test('isEncrypted is true once crypto metadata is present', () async {
      final source = await writeFile('enc.bin', payload(512));

      final item = EvidenceItem.encrypted(
        id: 'enc',
        type: EvidenceType.video,
        filePath: '/evidence/enc.enc',
        originalFileName: 'VID_0001.mp4',
        capturedAt: DateTime.utc(2026, 9, 13),
        encryption: await crypto.encryptFile(
          source: source,
          destination: fileAt('enc.enc'),
          masterKey: masterKey,
        ),
      );

      expect(item.isEncrypted, isTrue);
      expect(item.shortHash, hasLength(12));
    });
  });
}

/// True if [haystack] contains [needle] as a contiguous run.
bool _containsSequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }

  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matched = true;

    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }

    if (matched) {
      return true;
    }
  }

  return false;
}
