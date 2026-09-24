import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../app/app_lock_controller.dart';
import '../../../app/app_scope.dart';
import '../../../models/audit/audit_entry.dart';
import '../../../models/evidence/evidence_item.dart';
import '../../../services/storage/secure_delete.dart';
import 'capture_temp.dart';

class AudioCapturePage extends StatefulWidget {
  const AudioCapturePage({super.key});

  @override
  State<AudioCapturePage> createState() => _AudioCapturePageState();
}

class _AudioCapturePageState extends State<AudioCapturePage> {
  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;
  bool _saving = false;

  DateTime? _startedAt;

  Timer? _timer;

  Duration _duration = Duration.zero;

  /// The plaintext recording, until it has been encrypted.
  File? _file;

  /// Set while this page is deferring auto-lock.
  AppLockController? _lockHold;

  @override
  void dispose() {
    _timer?.cancel();
    _releaseLockHold();

    // Leaving mid-recording (back, panic, auto-lock) discards it: the
    // plaintext must not outlive this screen. Mid-save, addEvidence
    // still owns the file; _stopRecording cleans it up if the save fails.
    final unsaved = _saving ? null : _file;
    _recorder.stop().whenComplete(() async {
      await _recorder.dispose();
      if (unsaved != null) await destroyPlaintext(unsaved);
    });

    super.dispose();
  }

  void _releaseLockHold() {
    _lockHold?.releaseAutoLock();
    _lockHold = null;
  }

  Future<void> _startRecording() async {
    if (_recording || _saving) return;

    final permission = await _recorder.hasPermission();

    if (!permission) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );

      return;
    }

    final file = await CaptureTemp.newFile('m4a');

    if (!mounted) return;

    // Keep the key while the screen is off, so the recording can still
    // be encrypted when it stops.
    _lockHold = AppScope.of(context).lockController..holdAutoLock();
    _file = file;

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: file.path,
    );

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
    if (!_recording || _saving) return;

    final storage = AppScope.of(context).storage;
    final audit = AppScope.of(context).audit;

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
        originalFileName: 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      // addEvidence destroyed the plaintext.
      _file = null;

      unawaited(
        audit.record(
          AuditEventType.captured,
          evidenceId: evidence.id,
          detail: {'type': evidence.type.name},
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${evidence.typeLabel} saved to My Evidence')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save audio evidence: $e')),
      );
    } finally {
      _releaseLockHold();

      // The page closed mid-save (panic) and the save then failed:
      // nothing is left to retry it.
      final unsaved = _file;
      if (!mounted && unsaved != null) {
        _file = null;
        destroyPlaintext(unsaved);
      }

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
