import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../models/evidence/evidence_item.dart';

class CameraCapturePage extends StatefulWidget {
  final bool videoMode;

  const CameraCapturePage({super.key, required this.videoMode});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;

  Future<void> _capture() async {
    if (_busy) return;

    final storage = AppScope.of(context).storage;

    setState(() {
      _busy = true;
    });

    try {
      final XFile? captured;

      if (widget.videoMode) {
        captured = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 30),
        );
      } else {
        captured = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 95,
        );
      }

      if (captured == null) {
        return;
      }

      final file = File(captured.path);

      if (!await file.exists()) {
        throw Exception('Captured file could not be found.');
      }

      final type = widget.videoMode ? EvidenceType.video : EvidenceType.photo;

      final evidence = await storage.addEvidence(
        sourceFile: file,
        type: type,
        originalFileName: captured.name,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${evidence.typeLabel} saved to My Evidence')),
      );

      // Return after successful permanent storage.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save evidence: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _capture();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B10),
        foregroundColor: Colors.white,
        title: Text(widget.videoMode ? 'Record Video' : 'Take Photo'),
      ),
      body: Center(
        child: _busy
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Saving evidence...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : ElevatedButton.icon(
                onPressed: _capture,
                icon: Icon(
                  widget.videoMode ? Icons.videocam : Icons.camera_alt,
                ),
                label: Text(widget.videoMode ? 'Record Video' : 'Take Photo'),
              ),
      ),
    );
  }
}
