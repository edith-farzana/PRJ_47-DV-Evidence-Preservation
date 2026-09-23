import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../app/app_lock_controller.dart';
import '../../../app/app_scope.dart';
import '../../../models/evidence/evidence_item.dart';
import '../../../services/storage/evidence_storage.dart';
import '../../../services/storage/secure_delete.dart';
import 'capture_temp.dart';

/// Photo and video capture inside the app.
///
/// Replaces image_picker, which handed capture to the system camera
/// app: that app is free to keep its own copy in DCIM, which is where
/// someone holding the phone would look. The camera plugin writes only
/// to this app's private cache, and [CaptureTemp] takes it from there.
class InAppCameraPage extends StatefulWidget {
  const InAppCameraPage({super.key, required this.videoMode});

  final bool videoMode;

  @override
  State<InAppCameraPage> createState() => _InAppCameraPageState();
}

class _InAppCameraPageState extends State<InAppCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;

  bool _recording = false;
  bool _saving = false;

  Timer? _timer;
  Duration _duration = Duration.zero;

  /// The plaintext capture, until it has been encrypted.
  File? _unsaved;

  /// Set while this page is deferring auto-lock.
  AppLockController? _lockHold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _releaseLockHold();

    final controller = _controller;
    _controller = null;

    if (controller != null && _recording && !_saving) {
      // Leaving mid-recording (back, panic): the plugin has already
      // written plaintext to the cache, so finish it and destroy it.
      controller
          .stopVideoRecording()
          .then((file) => destroyPlaintext(File(file.path)))
          .catchError((_) {})
          .whenComplete(controller.dispose);
    } else {
      controller?.dispose();
    }

    // Mid-save, addEvidence still owns the file; _finishCapture cleans
    // it up if the save then fails.
    final unsaved = _unsaved;
    if (unsaved != null && !_saving) destroyPlaintext(unsaved);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.paused) {
      if (_recording) {
        // Keep what was recorded. The lock hold keeps the key until the
        // save is done, then the deferred auto-lock runs.
        _stopVideo();
      } else if (!_saving) {
        // Release the camera for other apps while in the background.
        final controller = _controller;
        setState(() => _controller = null);
        controller?.dispose();
      }
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera found on this device.');
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: widget.videoMode,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;

      setState(() => _error = _describe(e));
    }
  }

  String _describe(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera permission is required. '
            'You can allow it in the phone settings.';
      case 'AudioAccessDenied':
      case 'AudioAccessDeniedWithoutPrompt':
      case 'AudioAccessRestricted':
        return 'Microphone permission is required to record video.';
      default:
        return e.description ?? 'The camera could not be opened.';
    }
  }

  void _holdLock() {
    _lockHold ??= AppScope.of(context).lockController..holdAutoLock();
  }

  void _releaseLockHold() {
    _lockHold?.releaseAutoLock();
    _lockHold = null;
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || _saving) return;

    final storage = AppScope.of(context).storage;
    _holdLock();
    setState(() => _saving = true);

    try {
      final shot = await controller.takePicture();
      _unsaved = await CaptureTemp.adopt(shot.path);

      await _save(storage, EvidenceType.photo, 'jpg');
    } catch (e) {
      _showError(e);
    } finally {
      _finishCapture();
    }
  }

  Future<void> _startVideo() async {
    final controller = _controller;
    if (controller == null || _recording || _saving) return;

    _holdLock();

    try {
      await controller.startVideoRecording();
    } catch (e) {
      _releaseLockHold();
      _showError(e);
      return;
    }

    final startedAt = DateTime.now();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _duration = DateTime.now().difference(startedAt));
      }
    });

    if (mounted) {
      setState(() {
        _recording = true;
        _duration = Duration.zero;
      });
    }
  }

  Future<void> _stopVideo() async {
    final controller = _controller;
    if (controller == null || !_recording || _saving) return;

    final storage = AppScope.of(context).storage;
    _timer?.cancel();
    setState(() => _saving = true);

    try {
      final video = await controller.stopVideoRecording();
      _unsaved = await CaptureTemp.adopt(video.path);

      await _save(storage, EvidenceType.video, 'mp4');
    } catch (e) {
      _showError(e);
    } finally {
      _finishCapture();
    }
  }

  /// Encrypts [_unsaved]. On success the plaintext is gone and the page
  /// closes.
  Future<void> _save(
    EvidenceStorage storage,
    EvidenceType type,
    String extension,
  ) async {
    final evidence = await storage.addEvidence(
      sourceFile: _unsaved!,
      type: type,
      originalFileName:
          '${type.name}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );

    // addEvidence destroyed the plaintext.
    _unsaved = null;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${evidence.typeLabel} saved to My Evidence')),
    );

    Navigator.of(context).pop();
  }

  void _finishCapture() {
    if (mounted) {
      setState(() {
        _recording = false;
        _saving = false;
      });
    } else {
      _recording = false;
      _saving = false;

      // The page closed mid-save (panic) and the save then failed:
      // nothing is left to retry it.
      final unsaved = _unsaved;
      _unsaved = null;
      if (unsaved != null) destroyPlaintext(unsaved);
    }

    // Last: if the app went to the background meanwhile, this is where
    // the deferred auto-lock happens.
    _releaseLockHold();
  }

  void _showError(Object e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not save evidence: $e')));
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.videoMode ? 'Record Video' : 'Take Photo'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : controller == null || !controller.value.isInitialized
                  ? const CircularProgressIndicator()
                  : CameraPreview(controller),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: _controls(controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(CameraController? controller) {
    if (_saving) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Saving evidence...', style: TextStyle(color: Colors.white)),
        ],
      );
    }

    final ready = controller != null && controller.value.isInitialized;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recording)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _formatDuration(_duration),
              style: const TextStyle(color: Colors.redAccent, fontSize: 18),
            ),
          ),
        FloatingActionButton.large(
          backgroundColor: _recording ? Colors.redAccent : Colors.white,
          foregroundColor: Colors.black,
          onPressed: !ready
              ? null
              : widget.videoMode
              ? (_recording ? _stopVideo : _startVideo)
              : _takePhoto,
          child: Icon(
            widget.videoMode
                ? (_recording ? Icons.stop : Icons.videocam)
                : Icons.camera_alt,
          ),
        ),
      ],
    );
  }
}
