import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'services/crypto/key_manager.dart';
import 'services/crypto/secure_store.dart';
import 'services/storage/evidence_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = FlutterSecureStore();
  final keyManager = KeyManager(store);

  final storage = EvidenceStorage(
    baseDirectory: await getApplicationDocumentsDirectory(),
    keyManager: keyManager,
    store: store,
  );

  // Read before the first frame, so the app never flashes the wrong
  // screen (e.g. setup) in front of someone looking at the phone.
  final unlockSequence = await keyManager.isSetUp()
      ? await keyManager.unlockSequence()
      : null;

  runApp(
    SecureEvidenceApp(
      keyManager: keyManager,
      storage: storage,
      unlockSequence: unlockSequence,
    ),
  );
}
