import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/evidence/evidence_item.dart';
import 'package:secure_evidence_app/services/storage/evidence_index.dart';

import '../helpers/fake_secure_store.dart';

void main() {
  late Directory workspace;
  late FakeSecureStore store;
  late SecretKey masterKey;
  late EvidenceIndex index;

  File indexFile() => File('${workspace.path}/index.enc');

  EvidenceIndex newIndex({SecretKey? key}) {
    return EvidenceIndex(
      directory: workspace,
      store: store,
      masterKey: () => key ?? masterKey,
    );
  }

  EvidenceItem item(int n) {
    return EvidenceItem(
      id: 'id-$n',
      type: EvidenceType.values[n % 3],
      filePath: '/evidence/id-$n.enc',
      originalFileName: 'capture_$n.jpg',
      capturedAt: DateTime.utc(2026, 9, 18, 10, n),
      fileSizeBytes: 1000 + n,
      plaintextSha256: 'a' * 63 + '$n',
      ciphertextSha256: 'b' * 63 + '$n',
      wrappedDek: base64.encode(List.filled(60, n)),
      nonce: base64.encode(List.filled(12, n)),
      gcmTag: base64.encode(List.filled(16, n)),
      encryptionAlgorithm: 'AES-256-GCM',
      keyVersion: 1,
    );
  }

  Future<String> sealHash() async {
    final seal = jsonDecode(store.values['idx.v1.seal']!) as Map;
    return seal['hash'] as String;
  }

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('index_test_');
    store = FakeSecureStore();
    masterKey = await AesGcm.with256bits().newSecretKey();
    index = newIndex();
  });

  tearDown(() async {
    if (await workspace.exists()) {
      await workspace.delete(recursive: true);
    }
  });

  test('a never-written index loads as empty', () async {
    expect(await index.load(), isEmpty);
  });

  test('N items round-trip with every field intact', () async {
    for (var n = 0; n < 5; n++) {
      await index.append(item(n));
    }

    final loaded = await newIndex().load();

    expect(loaded, hasLength(5));

    for (var n = 0; n < 5; n++) {
      expect(loaded[n].toMap(), item(n).toMap());
    }
  });

  test(
    'the index file does not contain record contents in the clear',
    () async {
      await index.append(item(1));

      final raw = String.fromCharCodes(await indexFile().readAsBytes());

      expect(raw, isNot(contains('capture_1')));
      expect(raw, isNot(contains('id-1')));
    },
  );

  test('concurrent appends are both kept', () async {
    await Future.wait([
      index.append(item(1)),
      index.append(item(2)),
      index.append(item(3)),
    ]);

    expect(await index.load(), hasLength(3));
  });

  test('a flipped byte is detected', () async {
    await index.append(item(1));

    final bytes = await indexFile().readAsBytes();
    bytes[20] ^= 0x01;
    await indexFile().writeAsBytes(bytes);

    await expectLater(
      index.load(),
      throwsA(isA<EvidenceIndexCorruptedException>()),
    );
  });

  test('the wrong master key is detected', () async {
    await index.append(item(1));

    final other = newIndex(key: await AesGcm.with256bits().newSecretKey());

    await expectLater(
      other.load(),
      throwsA(isA<EvidenceIndexCorruptedException>()),
    );
  });

  test('ROLLBACK: restoring an older genuine index.enc is detected', () async {
    await index.append(item(1));
    final older = await indexFile().readAsBytes();

    await index.append(item(2));

    // The older file is authentic -- same key, valid GCM tag -- so only
    // the seal can tell that it is stale.
    await indexFile().writeAsBytes(older);

    await expectLater(
      index.load(),
      throwsA(isA<EvidenceIndexCorruptedException>()),
    );
  });

  test('a deleted index.enc is detected once records exist', () async {
    await index.append(item(1));
    await indexFile().delete();

    await expectLater(
      index.load(),
      throwsA(isA<EvidenceIndexCorruptedException>()),
    );
  });

  test('an index.enc with no seal is rejected', () async {
    await index.append(item(1));
    store.values.remove('idx.v1.seal');

    await expectLater(
      index.load(),
      throwsA(isA<EvidenceIndexCorruptedException>()),
    );
  });

  group('crash recovery', () {
    test('crash after the rename, before the seal was confirmed', () async {
      await index.append(item(1));
      final oldHash = await sealHash();

      await index.append(item(2));
      final newHash = await sealHash();

      // The state _write leaves if it dies right after the rename.
      store.values['idx.v1.seal'] = jsonEncode({
        'count': 1,
        'hash': oldHash,
        'pendingCount': 2,
        'pendingHash': newHash,
      });

      expect(await newIndex().load(), hasLength(2));
      expect(await sealHash(), newHash);
    });

    test('crash before the rename keeps the old index', () async {
      await index.append(item(1));
      final oldHash = await sealHash();

      // A temp file and a pending seal, but the rename never happened.
      final pending = utf8.encode('never renamed');
      await File('${workspace.path}/index.enc.tmp').writeAsBytes(pending);

      store.values['idx.v1.seal'] = jsonEncode({
        'count': 1,
        'hash': oldHash,
        'pendingCount': 2,
        'pendingHash': crypto.sha256.convert(pending).toString(),
      });

      expect(await newIndex().load(), hasLength(1));
      expect(await File('${workspace.path}/index.enc.tmp').exists(), isFalse);
      expect(store.values['idx.v1.seal'], isNot(contains('pending')));
    });
  });
}
