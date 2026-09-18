import 'package:secure_evidence_app/services/crypto/secure_store.dart';

/// In-memory [SecureStore]. Sharing one instance between two
/// KeyManagers simulates an app restart over the same device storage.
class FakeSecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
