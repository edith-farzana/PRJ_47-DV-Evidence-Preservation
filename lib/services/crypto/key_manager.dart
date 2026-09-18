import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'secure_store.dart';

/// Thrown when the stored key record exists but cannot be parsed.
///
/// Deliberately not recovered from automatically: resetting would
/// generate a new master key and make every existing evidence file
/// permanently unreadable.
class KeyStoreCorruptedException implements Exception {
  final String message;

  const KeyStoreCorruptedException(this.message);

  @override
  String toString() => 'KeyStoreCorruptedException: $message';
}

enum UnlockStatus { success, wrongPin, lockedOut }

class UnlockResult {
  final UnlockStatus status;

  /// Consecutive failures so far, including this attempt.
  final int failedAttempts;

  /// Set when further attempts are refused until this moment.
  final DateTime? lockedUntil;

  const UnlockResult._(this.status, this.failedAttempts, this.lockedUntil);

  bool get isSuccess => status == UnlockStatus.success;
}

/// Owns the top of the key hierarchy (docs/SECURITY.md §2.2):
///
///   PIN -> PBKDF2 -> PIN-derived key -> master key (KEK)
///
/// The master key is generated once, wrapped under a key derived from
/// the PIN, and stored in [SecureStore] -- which on Android is itself
/// encrypted under a non-exportable Keystore key. The PIN is never
/// stored or compared: a wrong PIN simply fails the GCM authentication
/// when unwrapping.
///
/// Per-file keys are CryptoService's job; it is handed [masterKey].
class KeyManager {
  KeyManager(
    this._store, {
    @visibleForTesting this._kdfIterations = defaultKdfIterations,
    @visibleForTesting DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// NIST SP 800-132 / OWASP floor for PBKDF2-HMAC-SHA256 at the time
  /// of writing. A test guards this so it cannot be lowered for test
  /// speed and forgotten.
  static const int defaultKdfIterations = 150000;

  /// Failures allowed before the first lockout.
  static const int freeAttempts = 4;

  /// Lockout after each failure past [freeAttempts]; the last entry
  /// repeats. There is intentionally no "wipe after N failures": an
  /// abuser could use that to destroy the evidence by typing wrong PINs.
  static const List<Duration> lockoutSchedule = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const int _macLength = 16;

  // Binds the wrapped key to its purpose, so the blob cannot be passed
  // off as some other AES-GCM ciphertext under the same key.
  static final List<int> _wrapAad = utf8.encode(
    'secure-evidence/master-key/v1',
  );

  // One record for salt, iterations and wrapped key, written in a single
  // call: a crash between two separate writes could otherwise leave a
  // salt that does not match the wrapped key, bricking the vault.
  static const String _vaultKey = 'km.v1.vault';
  static const String _unlockSequenceKey = 'km.v1.unlockSequence';
  static const String _failedAttemptsKey = 'km.v1.failedAttempts';
  static const String _lockedUntilKey = 'km.v1.lockedUntil';

  final SecureStore _store;
  final int _kdfIterations;
  final DateTime Function() _now;

  final AesGcm _cipher = AesGcm.with256bits();

  SecretKeyData? _masterKey;

  bool get isUnlocked => _masterKey != null && !_masterKey!.isDestroyed;

  /// The unwrapped master key. Throws if locked -- callers must not be
  /// able to proceed silently without it.
  SecretKey get masterKey {
    if (!isUnlocked) {
      throw StateError('KeyManager is locked. Unlock with the PIN first.');
    }

    return _masterKey!;
  }

  // ---------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------

  Future<bool> isSetUp() async => await _store.read(_vaultKey) != null;

  /// First run: generates the master key, wraps it under [pin] and
  /// stores the calculator [unlockSequence]. Leaves the manager
  /// unlocked.
  Future<void> setUp({
    required String pin,
    required String unlockSequence,
  }) async {
    if (await isSetUp()) {
      throw StateError(
        'A master key already exists. Setting up again would orphan '
        'every evidence file encrypted under it.',
      );
    }

    final masterKey = SecretKeyData.random(length: _keyLength);

    await _store.write(_vaultKey, await _wrapUnderPin(masterKey, pin));
    await _store.write(_unlockSequenceKey, unlockSequence);
    await _resetFailures();

    _masterKey = masterKey;
  }

  /// The calculator sequence that opens the PIN screen. Not a secret
  /// from the device itself, only from someone looking at the screen.
  Future<String?> unlockSequence() => _store.read(_unlockSequenceKey);

  // ---------------------------------------------------------------
  // Unlock / lock
  // ---------------------------------------------------------------

  /// When attempts are currently refused, or null if they are allowed.
  Future<DateTime?> lockedUntil() async {
    final raw = await _store.read(_lockedUntilKey);

    if (raw == null) {
      return null;
    }

    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(raw));

    return _now().isBefore(until) ? until : null;
  }

  Future<UnlockResult> unlock(String pin) async {
    final (key, result) = await _attempt(pin);

    if (key != null) {
      _masterKey?.destroy();
      _masterKey = key;
    }

    return result;
  }

  /// Destroys the in-memory master key. Its bytes are overwritten, not
  /// just dereferenced.
  void lock() {
    _masterKey?.destroy();
    _masterKey = null;
  }

  // ---------------------------------------------------------------
  // PIN change
  // ---------------------------------------------------------------

  /// Re-wraps the master key under [newPin] with a fresh salt.
  ///
  /// This rewrites one 256-bit key, not the evidence: every file stays
  /// encrypted under the same master key, so nothing is re-encrypted.
  /// A wrong [oldPin] counts toward the lockout, otherwise this screen
  /// would be a way round it.
  Future<UnlockResult> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    final (key, result) = await _attempt(oldPin);

    if (key == null) {
      return result;
    }

    await _store.write(_vaultKey, await _wrapUnderPin(key, newPin));

    _masterKey?.destroy();
    _masterKey = key;

    return result;
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  /// One PIN attempt with lockout accounting. The key is non-null only
  /// on success.
  Future<(SecretKeyData?, UnlockResult)> _attempt(String pin) async {
    final until = await lockedUntil();
    final failures = await _failedAttempts();

    if (until != null) {
      return (null, UnlockResult._(UnlockStatus.lockedOut, failures, until));
    }

    // Count the attempt BEFORE the slow KDF runs. Otherwise killing the
    // app mid-derivation would be a free guess.
    await _store.write(_failedAttemptsKey, '${failures + 1}');

    final masterKey = await _unwrapWithPin(pin);

    if (masterKey != null) {
      await _resetFailures();
      return (masterKey, const UnlockResult._(UnlockStatus.success, 0, null));
    }

    final total = failures + 1;

    if (total <= freeAttempts) {
      return (null, UnlockResult._(UnlockStatus.wrongPin, total, null));
    }

    final step = min(total - freeAttempts - 1, lockoutSchedule.length - 1);
    final lockEnd = _now().add(lockoutSchedule[step]);

    await _store.write(_lockedUntilKey, '${lockEnd.millisecondsSinceEpoch}');

    return (null, UnlockResult._(UnlockStatus.lockedOut, total, lockEnd));
  }

  Future<int> _failedAttempts() async {
    final raw = await _store.read(_failedAttemptsKey);

    return raw == null ? 0 : int.parse(raw);
  }

  Future<void> _resetFailures() async {
    await _store.delete(_failedAttemptsKey);
    await _store.delete(_lockedUntilKey);
  }

  Future<String> _wrapUnderPin(SecretKeyData masterKey, String pin) async {
    final salt = SecretKeyData.random(length: _saltLength).bytes;

    final pinKey = await _derive(pin, salt, _kdfIterations);

    final nonce = _cipher.newNonce();

    final box = await _cipher.encrypt(
      masterKey.bytes,
      secretKey: pinKey,
      nonce: nonce,
      aad: _wrapAad,
    );

    pinKey.destroy();

    return jsonEncode({
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _kdfIterations,
      'salt': base64.encode(salt),
      'wrapped': base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes]),
    });
  }

  /// Returns the master key, or null for a wrong PIN.
  Future<SecretKeyData?> _unwrapWithPin(String pin) async {
    final record = await _store.read(_vaultKey);

    if (record == null) {
      throw StateError('No master key has been set up yet.');
    }

    final List<int> salt;
    final int iterations;
    final List<int> raw;

    try {
      final json = jsonDecode(record) as Map<String, dynamic>;

      salt = base64.decode(json['salt'] as String);
      iterations = json['iterations'] as int;
      raw = base64.decode(json['wrapped'] as String);
    } catch (error) {
      throw KeyStoreCorruptedException('Unreadable key record ($error).');
    }

    if (raw.length != _nonceLength + _keyLength + _macLength) {
      throw KeyStoreCorruptedException(
        'Wrapped master key is ${raw.length} bytes, expected '
        '${_nonceLength + _keyLength + _macLength}.',
      );
    }

    final pinKey = await _derive(pin, salt, iterations);

    final box = SecretBox(
      raw.sublist(_nonceLength, _nonceLength + _keyLength),
      nonce: raw.sublist(0, _nonceLength),
      mac: Mac(raw.sublist(_nonceLength + _keyLength)),
    );

    try {
      final bytes = await _cipher.decrypt(
        box,
        secretKey: pinKey,
        aad: _wrapAad,
      );

      return SecretKeyData(bytes, overwriteWhenDestroyed: true);
    } on SecretBoxAuthenticationError {
      return null;
    } finally {
      pinKey.destroy();
    }
  }

  /// PBKDF2 in a background isolate: 150,000 iterations would otherwise
  /// freeze the PIN screen for the duration.
  ///
  /// Limitation: byte copies made while passing data between isolates
  /// cannot be zeroed. See docs/SECURITY.md §5.
  static Future<SecretKeyData> _derive(
    String pin,
    List<int> salt,
    int iterations,
  ) async {
    final bytes = await Isolate.run(() async {
      final kdf = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );

      final key = await kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );

      return key.extractBytes();
    });

    return SecretKeyData(bytes, overwriteWhenDestroyed: true);
  }
}
