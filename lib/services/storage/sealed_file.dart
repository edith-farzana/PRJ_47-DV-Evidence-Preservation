import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../crypto/secure_store.dart';

/// An encrypted list of JSON records on disk, with a seal that catches an
/// older copy being put back.
///
/// Layout: nonce(12) || AES-256-GCM ciphertext || tag(16), over the JSON
/// list. The key is derived from the master key with HKDF under [hkdfInfo],
/// so each file using this has its own key and never shares one with any
/// evidence file.
///
/// GCM detects any edit. What it cannot detect is someone replacing the
/// file with an OLDER genuine copy -- or, for an append-only log, the same
/// file with its newest records cut off. So a seal, the record count plus
/// the SHA-256 of the current file, is kept in [SecureStore]
/// (Keystore-backed), and every load checks the file against it.
///
/// Used by the evidence index and the activity log. The on-disk format and
/// the seal's JSON shape are load-bearing: changing either would make every
/// existing install's data read as corrupted.
class SealedFile {
  SealedFile({
    required this.file,
    required this._store,
    required this._masterKey,
    required this._sealKey,
    required this._aad,
    required this._hkdfInfo,
    required this._corrupted,
  });

  final File file;
  final SecureStore _store;
  final SecretKey Function() _masterKey;
  final String _sealKey;
  final List<int> _aad;
  final List<int> _hkdfInfo;

  /// Builds the caller's own exception type, so the index and the log each
  /// report corruption in terms their callers already handle.
  final Exception Function(String message) _corrupted;

  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final AesGcm _cipher = AesGcm.with256bits();

  // Changes are read-modify-write; two in quick succession must not both
  // read N records and each write N+1.
  Future<void> _queue = Future.value();

  File get _temp => File('${file.path}.tmp');

  String get _name => file.uri.pathSegments.last;

  /// All records, in stored order. Returns `[]` only for a file that has
  /// genuinely never been written.
  Future<List<Map<String, dynamic>>> load() => _serialized(_load);

  /// Replaces the records with `change(current)`. The file is replaced
  /// atomically (write temp, rename), so a crash leaves either the old
  /// version or the new one.
  Future<void> update(
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current)
    change,
  ) => _serialized(() async => _write(change(await _load())));

  // ---------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());

    _queue = result.then<void>((_) {}, onError: (_) {});

    return result;
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final seal = await _readSeal();
    final exists = await file.exists();

    if (!exists) {
      if (seal == null || seal.count == 0) {
        return [];
      }

      throw _corrupted(
        '$_name is missing, but ${seal.count} records were written.',
      );
    }

    if (seal == null) {
      throw _corrupted('$_name exists but no seal was recorded for it.');
    }

    final bytes = await file.readAsBytes();
    final hash = crypto.sha256.convert(bytes).toString();

    final int expectedCount;

    if (hash == seal.hash) {
      expectedCount = seal.count;

      if (seal.pendingHash != null) {
        // A write crashed before its rename: the old file stands.
        await _writeSeal(_Seal(count: seal.count, hash: seal.hash));

        if (await _temp.exists()) {
          await _temp.delete();
        }
      }
    } else if (hash == seal.pendingHash) {
      // The last write renamed the file but crashed before confirming the
      // seal. The file is the newer one; finish the job.
      expectedCount = seal.pendingCount!;
      await _writeSeal(_Seal(count: expectedCount, hash: hash));
    } else {
      throw _corrupted(
        '$_name does not match its seal. It has been replaced, possibly '
        'with an older copy.',
      );
    }

    final records = await _decrypt(bytes);

    if (records.length != expectedCount) {
      throw _corrupted(
        '$_name holds ${records.length} records, expected $expectedCount.',
      );
    }

    return records;
  }

  Future<void> _write(List<Map<String, dynamic>> records) async {
    final bytes = await _encrypt(records);
    final hash = crypto.sha256.convert(bytes).toString();

    final previous = await _readSeal();

    await file.parent.create(recursive: true);
    await _temp.writeAsBytes(bytes, flush: true);

    // Record the new hash as pending BEFORE the rename. A crash after this
    // line leaves either the old file (matches `hash`) or the new one
    // (matches `pendingHash`) -- both load. A crash before it leaves the
    // old file and the old seal.
    await _writeSeal(
      _Seal(
        count: previous?.count ?? 0,
        hash: previous?.hash ?? '',
        pendingCount: records.length,
        pendingHash: hash,
      ),
    );

    await _temp.rename(file.path);

    await _writeSeal(_Seal(count: records.length, hash: hash));
  }

  Future<SecretKey> _key() {
    return Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(secretKey: _masterKey(), info: _hkdfInfo);
  }

  Future<List<int>> _encrypt(List<Map<String, dynamic>> records) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(records)),
      secretKey: await _key(),
      aad: _aad,
    );

    return [...box.nonce, ...box.cipherText, ...box.mac.bytes];
  }

  Future<List<Map<String, dynamic>>> _decrypt(List<int> bytes) async {
    if (bytes.length < _nonceLength + _macLength) {
      throw _corrupted('$_name is truncated.');
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
        secretKey: await _key(),
        aad: _aad,
      );
    } on SecretBoxAuthenticationError {
      throw _corrupted(
        '$_name failed authentication: wrong key or modified file.',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(plaintext)) as List<dynamic>;

      return decoded.cast<Map<String, dynamic>>().toList();
    } catch (error) {
      throw _corrupted('Unreadable records ($error).');
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
      throw _corrupted('Unreadable seal ($error).');
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
