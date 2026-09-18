import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../models/evidence/evidence_item.dart';
import '../crypto/secure_store.dart';

/// Thrown when the index cannot be trusted: undecryptable, edited,
/// missing when it should exist, or rolled back to an older copy.
///
/// Callers must surface this. Showing an empty vault instead would tell
/// a survivor their evidence is gone when it is still on disk.
class EvidenceIndexCorruptedException implements Exception {
  final String message;

  const EvidenceIndexCorruptedException(this.message);

  @override
  String toString() => 'EvidenceIndexCorruptedException: $message';
}

/// The encrypted list of evidence records, `evidence/index.enc`.
///
/// Layout: nonce(12) || AES-256-GCM ciphertext || tag(16), over the
/// JSON list of [EvidenceItem] maps. The key is derived from the master
/// key with HKDF, so the index never shares a key with any evidence
/// file.
///
/// GCM detects any edit. What it cannot detect is someone replacing
/// index.enc with an OLDER genuine copy, which would silently hide
/// everything captured since. So a "seal" -- the item count and the
/// SHA-256 of the current index.enc -- is kept in [SecureStore]
/// (Keystore-backed), and every load checks the file against it.
class EvidenceIndex {
  EvidenceIndex({
    required this.directory,
    required this._store,
    required this._masterKey,
  });

  final Directory directory;
  final SecureStore _store;
  final SecretKey Function() _masterKey;

  static const String _sealKey = 'idx.v1.seal';
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final List<int> _aad = utf8.encode('secure-evidence/index/v1');
  static final List<int> _hkdfInfo = utf8.encode('evidence-index/v1');

  final AesGcm _cipher = AesGcm.with256bits();

  // Appends are read-modify-write; two captures in quick succession
  // must not both read N items and each write N+1.
  Future<void> _queue = Future.value();

  File get _file => File('${directory.path}/index.enc');
  File get _temp => File('${directory.path}/index.enc.tmp');

  /// All records, in stored order. Returns `[]` only for a vault that
  /// has genuinely never had anything written to it.
  Future<List<EvidenceItem>> load() => _serialized(_load);

  /// Adds [item]. The file is replaced atomically (write temp, rename),
  /// so a crash leaves either the old index or the new one.
  Future<void> append(EvidenceItem item) => _serialized(() async {
    final current = await _load();

    await _write([...current, item]);
  });

  // ---------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());

    _queue = result.then<void>((_) {}, onError: (_) {});

    return result;
  }

  Future<List<EvidenceItem>> _load() async {
    final seal = await _readSeal();
    final exists = await _file.exists();

    if (!exists) {
      if (seal == null || seal.count == 0) {
        return [];
      }

      throw EvidenceIndexCorruptedException(
        'index.enc is missing, but ${seal.count} records were written.',
      );
    }

    if (seal == null) {
      throw const EvidenceIndexCorruptedException(
        'index.enc exists but no seal was recorded for it.',
      );
    }

    final bytes = await _file.readAsBytes();
    final hash = crypto.sha256.convert(bytes).toString();

    final int expectedCount;

    if (hash == seal.hash) {
      expectedCount = seal.count;

      if (seal.pendingHash != null) {
        // A write crashed before its rename: the old index stands, and
        // the capture it was recording kept its plaintext source.
        await _writeSeal(_Seal(count: seal.count, hash: seal.hash));

        if (await _temp.exists()) {
          await _temp.delete();
        }
      }
    } else if (hash == seal.pendingHash) {
      // The last write renamed the file but crashed before confirming
      // the seal. The file is the newer one; finish the job.
      expectedCount = seal.pendingCount!;
      await _writeSeal(_Seal(count: expectedCount, hash: hash));
    } else {
      throw const EvidenceIndexCorruptedException(
        'index.enc does not match its seal. It has been replaced, '
        'possibly with an older copy.',
      );
    }

    final items = await _decrypt(bytes);

    if (items.length != expectedCount) {
      throw EvidenceIndexCorruptedException(
        'index.enc holds ${items.length} records, expected $expectedCount.',
      );
    }

    return items;
  }

  Future<void> _write(List<EvidenceItem> items) async {
    final bytes = await _encrypt(items);
    final hash = crypto.sha256.convert(bytes).toString();

    final previous = await _readSeal();

    await directory.create(recursive: true);
    await _temp.writeAsBytes(bytes, flush: true);

    // Record the new hash as pending BEFORE the rename. A crash after
    // this line leaves either the old file (matches `hash`) or the new
    // one (matches `pendingHash`) -- both load. A crash before it
    // leaves the old file and the old seal.
    await _writeSeal(
      _Seal(
        count: previous?.count ?? 0,
        hash: previous?.hash ?? '',
        pendingCount: items.length,
        pendingHash: hash,
      ),
    );

    await _temp.rename(_file.path);

    await _writeSeal(_Seal(count: items.length, hash: hash));
  }

  Future<SecretKey> _indexKey() {
    return Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(secretKey: _masterKey(), info: _hkdfInfo);
  }

  Future<List<int>> _encrypt(List<EvidenceItem> items) async {
    final plaintext = utf8.encode(
      jsonEncode(items.map((item) => item.toMap()).toList()),
    );

    final box = await _cipher.encrypt(
      plaintext,
      secretKey: await _indexKey(),
      aad: _aad,
    );

    return [...box.nonce, ...box.cipherText, ...box.mac.bytes];
  }

  Future<List<EvidenceItem>> _decrypt(List<int> bytes) async {
    if (bytes.length < _nonceLength + _macLength) {
      throw const EvidenceIndexCorruptedException('index.enc is truncated.');
    }

    final box = SecretBox(
      bytes.sublist(_nonceLength, bytes.length - _macLength),
      nonce: bytes.sublist(0, _nonceLength),
      mac: Mac(bytes.sublist(bytes.length - _macLength)),
    );

    final List<int> plaintext;

    try {
      plaintext = await _cipher.decrypt(
        box,
        secretKey: await _indexKey(),
        aad: _aad,
      );
    } on SecretBoxAuthenticationError {
      throw const EvidenceIndexCorruptedException(
        'index.enc failed authentication: wrong key or modified file.',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(plaintext)) as List<dynamic>;

      return decoded
          .map((entry) => EvidenceItem.fromMap(entry as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw EvidenceIndexCorruptedException('Unreadable records ($error).');
    }
  }

  Future<_Seal?> _readSeal() async {
    final raw = await _store.read(_sealKey);

    if (raw == null) {
      return null;
    }

    try {
      return _Seal.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      throw EvidenceIndexCorruptedException('Unreadable seal ($error).');
    }
  }

  Future<void> _writeSeal(_Seal seal) {
    return _store.write(_sealKey, jsonEncode(seal.toJson()));
  }
}

class _Seal {
  const _Seal({
    required this.count,
    required this.hash,
    this.pendingCount,
    this.pendingHash,
  });

  final int count;
  final String hash;
  final int? pendingCount;
  final String? pendingHash;

  factory _Seal.fromJson(Map<String, dynamic> json) {
    return _Seal(
      count: json['count'] as int,
      hash: json['hash'] as String,
      pendingCount: json['pendingCount'] as int?,
      pendingHash: json['pendingHash'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'count': count,
    'hash': hash,
    if (pendingHash != null) 'pendingCount': pendingCount,
    if (pendingHash != null) 'pendingHash': pendingHash,
  };
}
