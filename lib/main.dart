import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/app_lock_controller.dart';
import 'features/evidence/capture/capture_temp.dart';
import 'services/crypto/key_manager.dart';
import 'services/crypto/secure_store.dart';
import 'services/storage/evidence_storage.dart';
import 'services/sync/backup_state_store.dart';
import 'services/sync/evidence_sync.dart';
import 'services/sync/firebase_evidence_client.dart';

/// Starts Firebase if this build has been configured for it.
///
/// Configuration is `google-services.json`, which `flutterfire
/// configure` writes and which is not in the repository. Without it the
/// app must still run: everything local -- capture, encryption, the
/// vault, verification -- works with no backend at all.
///
/// This only reads local configuration. Nothing is sent: the first
/// contact with Google happens on the first sync after unlock.
Future<void> _startFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase is not configured; running local-only: $error');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _startFirebase();

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

  final sync = EvidenceSync(
    client: FirebaseEvidenceClient(),
    states: BackupStateStore(store),
  );
  await sync.load();

  // Plaintext left behind if the app was killed mid-capture, or while
  // a decrypted item was on screen.
  await CaptureTemp.sweep();
  await storage.sweepPreviews();

  runApp(
    SecureEvidenceApp(
      keyManager: keyManager,
      storage: storage,
      lockController: lockController,
      sync: sync,
      unlockSequence: unlockSequence,
    ),
  );
}
