import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../app/app_lock_controller.dart';
import '../../../app/app_scope.dart';
import '../../../app/panic_button.dart';
import '../../../models/evidence/evidence_item.dart';

/// Photo and video capture inside the app.
///
/// Replaces image_picker, which handed off to the system camera app --
/// and the system camera can keep a copy in DCIM, exactly where someone
/// going through the phone would look. Here the plugin writes to the
/// app's own cache, the file is moved straight into the pending folder
/// and then encrypted.
class InAppCameraPage extends StatefulWidget {
  const InAppCameraPage({super.key, required this.videoMode});

  final bool videoMode;

  @override
  State<InAppCameraPage> createState() => _InAppCameraPageState();
}

class _InAppCameraPageState extends State<InAppCameraPage>
    with WidgetsBindingObserver
    implements CaptureSession {
  static const Duration maxVideoLength = Duration(minutes: 30);

  late AppLockController _lock;

  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;

  String? _error;
  bool _busy = false;
  bool _recording = false;
  bool _handedOver = false;

  DateTime? _startedAt;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lock = AppScope.of(context).lock;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.unregisterCapture(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// The plugin must release the camera when the app loses focus. A
  /// video being recorded is left alone: if the app is really going to
  /// the background, the lock hands it over and saves it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && !_recording) {
      final controller = _controller;
      _controller = null;
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }

      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }

      final controller = CameraController(
        _cameras[_cameraIndex],
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
    } on CameraException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.code == 'CameraAccessDenied'
            ? 'Camera permission is required.'
            : 'Camera unavailable: ${error.description ?? error.code}';
      });
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording || _busy) return;

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.setDescription(_cameras[_cameraIndex]);
    setState(() {});
  }

  // ---------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------

  Future<void> _onShutter() async {
    if (widget.videoMode) {
      _recording ? await _stopVideo() : await _startVideo();
    } else {
      await _takePhoto();
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || _busy) return;

    final storage = _lock.storage;

    setState(() => _busy = true);

    try {
      final shot = await controller.takePicture();
      final staged = await storage.stage(File(shot.path), EvidenceType.photo);

      await _save(staged, EvidenceType.photo);
    } catch (error) {
      _reportFailure(error);
    }
  }

  Future<void> _startVideo() async {
    final controller = _controller;
    if (controller == null || _busy) return;

    try {
      await controller.startVideoRecording();
    } on CameraException catch (error) {
      _reportFailure(error.description ?? error.code);
      return;
    }

    _lock.registerCapture(this);

    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;

      final elapsed = DateTime.now().difference(_startedAt!);
      setState(() => _elapsed = elapsed);

      if (elapsed >= maxVideoLength) {
        _stopVideo();
      }
    });

    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _stopVideo() async {
    final controller = _controller;
    if (controller == null || !_recording || _busy || _handedOver) return;

    final storage = _lock.storage;

    // This screen now owns the save.
    _lock.unregisterCapture(this);
    _timer?.cancel();

    setState(() => _busy = true);

    try {
      final video = await controller.stopVideoRecording();
      _recording = false;

      final staged = await storage.stage(File(video.path), EvidenceType.video);

      await _save(staged, EvidenceType.video);
    } catch (error) {
      _recording = false;
      _reportFailure(error);
    }
  }

  /// Called by a lock or panic while a video is recording.
  @override
  Future<(File, EvidenceType)?> stopAndHandOver() async {
    final controller = _controller;

    if (controller == null || !_recording || _busy || _handedOver) {
      return null;
    }

    _handedOver = true;
    _timer?.cancel();

    final storage = _lock.storage;
    final video = await controller.stopVideoRecording();
    _recording = false;

    final staged = await storage.stage(File(video.path), EvidenceType.video);

    return (staged, EvidenceType.video);
  }

  Future<void> _save(File staged, EvidenceType type) async {
    final storage = _lock.storage;

    final evidence = await storage.addEvidence(
      sourceFile: staged,
      type: type,
      originalFileName: staged.uri.pathSegments.last,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${evidence.typeLabel} saved to My Evidence')),
    );

    Navigator.of(context).pop();
  }

  void _reportFailure(Object error) {
    if (!mounted) return;

    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Not saved yet ($error). If it was captured, it is kept and '
          'will be stored the next time you unlock.',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
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
        actions: const [PanicButton()],
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
                        style: const TextStyle(color: Colors.white70),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 64,
                    child: _recording
                        ? Text(
                            _format(_elapsed),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          )
                        : null,
                  ),
                  _ShutterButton(
                    recording: _recording,
                    busy: _busy,
                    video: widget.videoMode,
                    onPressed: controller == null ? null : _onShutter,
                  ),
                  SizedBox(
                    width: 64,
                    child: IconButton(
                      onPressed: _cameras.length < 2 || _recording || _busy
                          ? null
                          : _flipCamera,
                      icon: const Icon(
                        Icons.flip_camera_android,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.recording,
    required this.busy,
    required this.video,
    required this.onPressed,
  });

  final bool recording;
  final bool busy;
  final bool video;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(6),
        child: busy
            ? const CircularProgressIndicator(color: Colors.white)
            : AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: video ? Colors.redAccent : Colors.white,
                  shape: recording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: recording ? BorderRadius.circular(8) : null,
                ),
              ),
      ),
    );
  }
}
