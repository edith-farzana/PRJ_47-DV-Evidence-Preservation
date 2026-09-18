import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key-value storage for key material and lockout state.
///
/// KeyManager depends on this interface rather than on
/// FlutterSecureStorage directly, so the key logic can be unit tested
/// with an in-memory fake. flutter_secure_storage 9.x ships no mock.
abstract class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The production [SecureStore].
///
/// On Android, flutter_secure_storage encrypts every value with an AES
/// key that is itself wrapped by a non-exportable RSA key in the
/// Android Keystore. That is the second layer around the PIN-wrapped
/// master key (docs/SECURITY.md §2.2): a copy of the app's files is
/// useless without this specific phone's Keystore, so the 10,000
/// possible PINs cannot be tried offline against a backup or a
/// forensic image.
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore()
    : _storage = const FlutterSecureStorage(
        // The default Keystore RSA path, stated explicitly so a later
        // options change is a visible decision rather than an accident.
        aOptions: AndroidOptions(encryptedSharedPreferences: false),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
