import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/crypto/key_manager.dart';
import 'services/crypto/secure_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final keyManager = KeyManager(FlutterSecureStore());

  // Read before the first frame, so the app never flashes the wrong
  // screen (e.g. setup) in front of someone looking at the phone.
  final unlockSequence = await keyManager.isSetUp()
      ? await keyManager.unlockSequence()
      : null;

  runApp(
    SecureEvidenceApp(keyManager: keyManager, unlockSequence: unlockSequence),
  );
}
