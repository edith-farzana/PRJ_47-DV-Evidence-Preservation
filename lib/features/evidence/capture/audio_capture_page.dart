import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../app/app_lock_controller.dart';
import '../../../app/app_scope.dart';
import '../../../app/panic_button.dart';
import '../../../models/evidence/evidence_item.dart';

class AudioCapturePage extends StatefulWidget {
  const AudioCapturePage({super.key});

  @override
  State<AudioCapturePage> createState() => _AudioCapturePageState();
}

class _AudioCapturePageState extends State<AudioCapturePage>
    implements CaptureSession {
  final AudioRecorder _recorder = AudioRecorder();

  late AppLockController _lock;

  bool _recording = false;
  bool _saving = false;

  /// Set when a lock has taken the recording. From then on this screen
  /// must not stop or save it itself.
  bool _handedOver = false;

  DateTime? _startedAt;

  Timer? _timer;

  Duration _duration = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lock = AppScope.of(context).lock;
  }

  @override
  void dispose() {
    _lock.unregisterCapture(this);
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  /// Called by a lock or panic while recording: stop, and give the file
  /// to the lock to save. The file is already in the pending folder, so
  /// even if that save is interrupted it is stored on the next unlock.
  @override
  Future<(File, EvidenceType)?> stopAndHandOver() async {
    if (!_recording || _saving || _handedOver) {
      return null;
    }

    _handedOver = true;
    _timer?.cancel();

    final path = await _recorder.stop();

    if (path == null || path.isEmpty) {
      return null;
    }

    return (File(path), EvidenceType.audio);
  }

  Future<void> _startRecording() async {
    if (_recording || _saving) return;

    final storage = AppScope.of(context).storage;

    final permission = await _recorder.hasPermission();

    if (!permission) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );

      return;
    }

    // Straight into the pending folder: if the app dies mid-recording,
    // whatever was captured is still stored on the next unlock.
    final file = await storage.newPendingFile(EvidenceType.audio, '.m4a');

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: file.path,
    );

    _lock.registerCapture(this);

    _startedAt = DateTime.now();

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) {
        return;
      }

      setState(() {
        _duration = DateTime.now().difference(_startedAt!);
      });
    });

    if (!mounted) return;

    setState(() {
      _recording = true;
      _duration = Duration.zero;
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording || _saving || _handedOver) return;

    final storage = AppScope.of(context).storage;

    // From here this screen owns the save; a lock no longer needs to
    // stop anything.
    _lock.unregisterCapture(this);

    setState(() {
      _saving = true;
    });

    _timer?.cancel();

    try {
      final path = await _recorder.stop();

      if (path == null || path.isEmpty) {
        throw Exception('Recorder did not return a file.');
      }

      final file = File(path);

      if (!await file.exists()) {
        throw Exception('Recorded audio file does not exist.');
      }

      final evidence = await storage.addEvidence(
        sourceFile: file,
        type: EvidenceType.audio,
        originalFileName: file.uri.pathSegments.last,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${evidence.typeLabel} saved to My Evidence')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        // The recording stays in the pending folder and is stored on
        // the next unlock, so say that rather than implying it is lost.
        SnackBar(
          content: Text(
            'Not saved yet ($e). The recording is kept and will be '
            'stored the next time you unlock.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
          _saving = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');

    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');

    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B10),
        foregroundColor: Colors.white,
        title: const Text('Capture Audio'),
        actions: const [PanicButton()],
      ),
      body: Center(
        child: _saving
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Saving audio evidence...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: _recording
                          ? Colors.redAccent.withValues(alpha: 0.15)
                          : const Color(0xFF9B7BFF).withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _recording ? Icons.mic : Icons.mic_none,
                      color: _recording
                          ? Colors.redAccent
                          : const Color(0xFF9B7BFF),
                      size: 55,
                    ),
                  ),

                  const SizedBox(height: 25),

                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    _recording ? 'Recording...' : 'Ready to record',
                    style: const TextStyle(
                      color: Color(0xFF9297A3),
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: 210,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _recording ? _stopRecording : _startRecording,
                      icon: Icon(
                        _recording ? Icons.stop : Icons.fiber_manual_record,
                      ),
                      label: Text(
                        _recording ? 'STOP & SAVE' : 'START RECORDING',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
