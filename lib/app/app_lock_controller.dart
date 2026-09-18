import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/evidence/evidence_item.dart';
import '../services/crypto/key_manager.dart';
import '../services/crypto/secure_store.dart';
import '../services/storage/evidence_storage.dart';

enum AppLockState { needsSetup, calculator, pin, unlocked }

/// A capture that is recording right now. Registered with
/// [AppLockController] so a lock can stop it and keep the file, instead
/// of the recording dying with its screen.
abstract class CaptureSession {
  /// Stops recording and returns the staged file, or null if nothing
  /// was captured. After this the screen must not save the file itself.
  Future<(File, EvidenceType)?> stopAndHandOver();
}

/// Single owner of "is the app locked, and what is on screen".
///
/// Locking -- from panic, or from the app going to the background --
/// always runs the same sequence:
///   1. stop any running capture and take its file
///   2. start saving it with a private key copy
///   3. destroy the master key
///   4. close every pushed screen
///   5. show a fresh calculator
/// Steps 1-2 come first so that a panic never costs the survivor the
/// recording they were making.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController({
    required this.keyManager,
    required this.storage,
    required this._store,
    required String? unlockSequence,
  }) : _unlockSequence = unlockSequence,
       _state = unlockSequence == null
           ? AppLockState.needsSetup
           : AppLockState.calculator;

  final KeyManager keyManager;
  final EvidenceStorage storage;
  final SecureStore _store;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const String _autoLockKey = 'app.autoLock';

  /// Bounds how long a lock waits for a recorder to stop. A hung
  /// recorder must not keep the vault open.
  static const Duration handOverTimeout = Duration(seconds: 3);

  AppLockState _state;
  String? _unlockSequence;
  bool _autoLock = true;
  bool _locking = false;
  int _generation = 0;

  final Set<CaptureSession> _captures = {};

  /// Saves started by a lock, still running. Exposed for tests.
  final List<Future<void>> pendingSaves = [];

  AppLockState get state => _state;
  String? get unlockSequence => _unlockSequence;
  bool get autoLock => _autoLock;

  /// Changes on every lock, so the calculator is rebuilt from scratch
  /// and shows `0` rather than whatever was typed before.
  int get generation => _generation;

  // ---------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------

  /// Registers for lifecycle events and loads the auto-lock setting.
  Future<void> attach() async {
    WidgetsBinding.instance.addObserver(this);
    _autoLock = await _store.read(_autoLockKey) != 'false';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> setAutoLock(bool value) async {
    _autoLock = value;
    notifyListeners();
    await _store.write(_autoLockKey, '$value');
  }

  // ---------------------------------------------------------------
  // Transitions
  // ---------------------------------------------------------------

  void completeSetup(String unlockSequence) {
    _unlockSequence = unlockSequence;
    _state = AppLockState.calculator;
    notifyListeners();
  }

  void openPin() {
    _state = AppLockState.pin;
    notifyListeners();
  }

  /// Called once the PIN has unwrapped the master key.
  void onUnlocked() {
    _state = AppLockState.unlocked;
    notifyListeners();

    // Anything a crash or a killed save left behind.
    unawaited(
      storage.ingestPending().catchError((Object error) {
        debugPrint('Ingesting pending captures failed: $error');
        return 0;
      }),
    );
  }

  void registerCapture(CaptureSession session) => _captures.add(session);

  void unregisterCapture(CaptureSession session) => _captures.remove(session);

  /// Panic. Identical to a lock; named separately for readability at
  /// the call sites.
  Future<void> panic() => lock();

  Future<void> lock() async {
    if (_locking) {
      return;
    }

    _locking = true;

    try {
      await _handOverCaptures();

      keyManager.lock();

      navigatorKey.currentState?.popUntil((route) => route.isFirst);

      if (_state != AppLockState.needsSetup) {
        _state = AppLockState.calculator;
      }

      _generation++;
      notifyListeners();
    } finally {
      _locking = false;
    }
  }

  Future<void> _handOverCaptures() async {
    final sessions = List.of(_captures);
    _captures.clear();

    for (final session in sessions) {
      (File, EvidenceType)? capture;

      try {
        capture = await session.stopAndHandOver().timeout(handOverTimeout);
      } catch (error) {
        // The file, if any, is in the pending folder and will be
        // ingested on the next unlock.
        debugPrint('Capture hand-over failed: $error');
      }

      if (capture == null || !keyManager.isUnlocked) {
        continue;
      }

      // Copy the key BEFORE locking; the save then outlives the lock.
      final key = await storage.copyMasterKey();
      final (file, type) = capture;

      pendingSaves.add(
        storage
            .addEvidence(sourceFile: file, type: type, masterKey: key)
            .then<void>((_) {})
            .catchError((Object error) {
              debugPrint('Background save failed, kept as pending: $error');
            }),
      );
    }
  }

  // ---------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------

  /// Locks on `paused` and `hidden` only. `inactive` also fires for
  /// permission dialogs and the notification shade, where locking would
  /// throw the user out mid-task.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final backgrounded =
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden;

    final exposed =
        _state == AppLockState.unlocked || _state == AppLockState.pin;

    if (backgrounded && _autoLock && exposed) {
      unawaited(lock());
    }
  }
}
