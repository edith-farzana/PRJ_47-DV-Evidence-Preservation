import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/app_lock_controller.dart';
import 'features/evidence/capture/capture_temp.dart';
import 'services/crypto/key_manager.dart';
import 'services/crypto/secure_store.dart';
import 'services/storage/evidence_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = FlutterSecureStore();
  final keyManager = KeyManager(store);

  final storage = EvidenceStorage(
    baseDirectory: await getApplicationDocumentsDirectory(),
    cacheDirectory: await getTemporaryDirectory(),
    keyManager: keyManager,
    store: store,
  );

  // Read before the first frame, so the app never flashes the wrong
  // screen (e.g. setup) in front of someone looking at the phone.
  final unlockSequence = await keyManager.isSetUp()
      ? await keyManager.unlockSequence()
      : null;

  final lockController = AppLockController(
    keyManager: keyManager,
    store: store,
  );
  await lockController.load();

  // Plaintext left behind if the app was killed mid-capture, or while
  // a decrypted item was on screen.
  await CaptureTemp.sweep();
  await storage.sweepPreviews();

  runApp(
    SecureEvidenceApp(
      keyManager: keyManager,
      storage: storage,
      lockController: lockController,
      unlockSequence: unlockSequence,
    ),
  );
}
