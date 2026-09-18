import 'package:flutter/widgets.dart';

import '../services/crypto/key_manager.dart';
import '../services/storage/evidence_storage.dart';
import 'app_lock_controller.dart';

/// Makes the app's long-lived services reachable from any screen,
/// including routes pushed with Navigator, without threading them
/// through every constructor.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.lock, required super.child});

  final AppLockController lock;

  KeyManager get keyManager => lock.keyManager;
  EvidenceStorage get storage => lock.storage;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();

    assert(scope != null, 'No AppScope above this widget.');

    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => lock != oldWidget.lock;
}
