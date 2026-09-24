import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/audit/audit_entry.dart';
import '../services/audit/audit_log.dart';
import '../services/crypto/key_manager.dart';
import '../services/crypto/secure_store.dart';

/// Which screen the app shell shows once setup is complete.
enum AppLockState {
  /// The decoy calculator. The master key is not in memory.
  locked,

  /// The PIN screen, reached through the calculator's unlock sequence.
  showPin,

  /// The evidence center. The master key is in memory.
  unlocked,
}

/// Why the app locked. Recorded in the activity log.
enum LockReason {
  /// A one-second hold anywhere.
  panic,

  /// The app went to the background with auto-lock on.
  background,
}

/// The app's lock state, and the only place that decides when to drop
/// the master key.
///
/// Panic and auto-lock both end in [lock]: the key is destroyed first,
/// then listeners are told, so no screen that still needs the key can
/// be built in between.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required this._keyManager,
    required this._store,
    this._audit,
  });

  final KeyManager _keyManager;
  final SecureStore _store;

  /// Optional so the lock logic can be tested on its own.
  final AuditLog? _audit;

  static const String _autoLockKey = 'app.v1.autoLock';

  AppLockState _state = AppLockState.locked;
  bool _autoLock = true;
  bool _inBackground = false;
  int _holds = 0;
  int _lockCount = 0;

  AppLockState get state => _state;

  bool get autoLock => _autoLock;

  /// Increments on every lock. The shell keys the calculator on this,
  /// so each lock builds a fresh calculator with a cleared display.
  int get lockCount => _lockCount;

  /// Reads the stored auto-lock preference. Defaults to on.
  Future<void> load() async {
    _autoLock = await _store.read(_autoLockKey) != 'false';
  }

  Future<void> setAutoLock(bool value) async {
    _autoLock = value;
    notifyListeners();
    await _store.write(_autoLockKey, '$value');
  }

  /// The calculator's unlock sequence was entered.
  void showPin() {
    if (_state != AppLockState.locked) return;

    _state = AppLockState.showPin;
    notifyListeners();
  }

  /// The PIN unwrapped the master key.
  ///
  /// [result] carries the wrong PINs entered before this one, which the
  /// key manager has just forgotten; the activity log keeps them.
  void unlocked([UnlockResult? result]) {
    _state = AppLockState.unlocked;
    notifyListeners();

    if (result != null) {
      unawaited(_audit?.onUnlocked(result));
    }
  }

  /// Drops the master key and returns to the calculator.
  ///
  /// Used by panic, so it must not wait on anything: the key is
  /// destroyed synchronously before listeners run. The activity log hears
  /// about it only afterwards, without being awaited, and with no key --
  /// so the event is kept pending until the next unlock.
  void lock({LockReason reason = LockReason.panic}) {
    _keyManager.lock();
    _holds = 0;
    _lockCount++;
    _state = AppLockState.locked;
    notifyListeners();

    unawaited(
      _audit?.record(
        reason == LockReason.panic
            ? AuditEventType.panic
            : AuditEventType.autoLocked,
      ),
    );
  }

  /// Defers auto-lock while a capture is in progress.
  ///
  /// Recording audio with the screen off is the main way this app is
  /// used, and the screen turning off pauses the app. Locking then
  /// would destroy the key the recording needs to be saved. Panic
  /// ignores holds.
  ///
  /// Every call must be matched by [releaseAutoLock].
  void holdAutoLock() => _holds++;

  /// Ends a [holdAutoLock]. If the app went to the background during
  /// the hold, the lock that was deferred happens now.
  void releaseAutoLock() {
    if (_holds == 0) return;

    _holds--;

    if (_holds == 0 && _inBackground) {
      _autoLockNow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `inactive` is deliberately not here: on Android it also fires
      // for permission dialogs and the notification shade, and locking
      // then would throw the user out of the camera while it asks for
      // permission. `paused` fires when the app is actually hidden.
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _inBackground = true;
        if (_holds == 0) _autoLockNow();
      case AppLifecycleState.resumed:
        _inBackground = false;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _autoLockNow() {
    // The PIN screen counts too: it should not be what someone sees
    // when they pick up the phone.
    if (_autoLock && _state != AppLockState.locked) {
      lock(reason: LockReason.background);
    }
  }
}
