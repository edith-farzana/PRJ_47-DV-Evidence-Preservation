import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../app/app_scope.dart';
import '../../../models/evidence/backup_state.dart';
import '../../../models/evidence/evidence_item.dart';
import '../../../models/evidence/integrity_report.dart';
import '../../../services/storage/evidence_storage.dart';
import '../../../services/sync/evidence_sync.dart';
import '../../../services/sync/evidence_sync_client.dart';
import '../cloud_backup_notice.dart';
import 'integrity_page.dart';

/// Shows one piece of evidence: the media itself, what was recorded
/// about it, and whether it still verifies.
///
/// The file is decrypted into the preview directory when the screen
/// opens and destroyed when it closes -- including when a panic or an
/// auto-lock tears the screen down, because that pops this route and
/// [dispose] runs.
class EvidenceDetailPage extends StatefulWidget {
  const EvidenceDetailPage({super.key, required this.item});

  final EvidenceItem item;

  @override
  State<EvidenceDetailPage> createState() => _EvidenceDetailPageState();
}

class _EvidenceDetailPageState extends State<EvidenceDetailPage> {
  static const Color _background = Color(0xFF090B10);
  static const Color _accent = Color(0xFF9B7BFF);
  static const Color _muted = Color(0xFF9297A3);

  /// Held from didChangeDependencies: dispose must not reach for an
  /// InheritedWidget, and that is exactly when the preview is destroyed.
  EvidenceStorage? _storage;

  File? _preview;
  String? _error;
  bool _opening = true;

  IntegrityReport? _report;
  bool _verifying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_storage == null) {
      _storage = AppScope.of(context).storage;
      _open();
    }
  }

  @override
  void dispose() {
    final preview = _preview;

    if (preview != null) {
      // Not awaited: dispose cannot be async, and the file must go
      // whether or not anything is left to await it.
      _storage?.closePreview(preview);
    }

    super.dispose();
  }

  Future<void> _open() async {
    try {
      final preview = await _storage!.openPreview(widget.item);

      if (!mounted) {
        // The screen went away mid-decryption -- panic, most likely.
        await _storage!.closePreview(preview);
        return;
      }

      setState(() {
        _preview = preview;
        _opening = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = '$error';
        _opening = false;
      });
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);

    final IntegrityReport report;

    try {
      report = await _storage!.checkIntegrity(widget.item);
    } catch (error) {
      if (!mounted) return;

      setState(() => _verifying = false);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not verify: $error')));

      return;
    }

    if (!mounted) return;

    setState(() {
      _report = report;
      _verifying = false;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IntegrityPage(item: widget.item, report: report),
      ),
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} • '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Evidence Detail'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_report != null) ...[
            _VerdictBanner(report: _report!),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _verifying ? null : _verify,
              icon: _verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(_verifying ? 'Verifying…' : 'Verify Integrity'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF1A1030),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          _PreviewArea(
            item: item,
            preview: _preview,
            opening: _opening,
            error: _error,
          ),

          const SizedBox(height: 16),

          _Card(
            title: 'Evidence Details',
            icon: Icons.description_outlined,
            children: [
              _Row(label: 'Type', value: item.typeLabel),
              _Row(label: 'Original file', value: item.originalFileName),
              _Row(label: 'Captured', value: _date(item.capturedAt)),
              _Row(label: 'Stored size', value: item.fileSizeLabel),
              _Row(label: 'Evidence ID', value: item.id, monospace: true),
            ],
          ),

          const SizedBox(height: 16),

          _Card(
            title: 'Cryptographic Protection',
            icon: Icons.lock_outline,
            children: [
              _Row(
                label: 'Encryption',
                value: item.encryptionAlgorithm ?? 'Not encrypted',
                good: item.isEncrypted,
              ),
              _Row(
                label: 'Key version',
                value: item.keyVersion?.toString() ?? '—',
              ),
              _Row(
                label: 'SHA-256',
                value: item.plaintextSha256 ?? '—',
                monospace: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          _Card(
            title: 'Encrypted Local Storage',
            icon: Icons.folder_outlined,
            children: [
              _Row(label: 'File', value: item.filePath, monospace: true),
              const SizedBox(height: 8),
              const Text(
                'The evidence is stored as encrypted ciphertext, never as '
                'the original file. It is decrypted only while this screen '
                'is open, and the decrypted copy is destroyed when you '
                'leave.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _BackupCard(item: item),
        ],
      ),
    );
  }
}

/// The media itself.
class _PreviewArea extends StatelessWidget {
  const _PreviewArea({
    required this.item,
    required this.preview,
    required this.opening,
    required this.error,
  });

  final EvidenceItem item;
  final File? preview;
  final bool opening;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (opening) {
      return const _PreviewFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF9B7BFF)),
            SizedBox(height: 14),
            Text('Decrypting…', style: TextStyle(color: Color(0xFF9297A3))),
          ],
        ),
      );
    }

    final failure = error;

    if (failure != null || preview == null) {
      return _PreviewFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.gpp_bad_outlined,
              color: Colors.redAccent,
              size: 44,
            ),
            const SizedBox(height: 12),
            const Text(
              'This evidence could not be opened',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              failure ?? 'The decrypted file is not available.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9297A3), fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (item.type == EvidenceType.photo) {
      return _PreviewFrame(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.file(preview!, fit: BoxFit.contain),
          ),
        ),
      );
    }

    return _MediaPlayer(
      file: preview!,
      audioOnly: item.type == EvidenceType.audio,
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242934)),
      ),
      child: Center(child: child),
    );
  }
}

/// Video and audio playback, straight from the decrypted file.
///
/// One controller covers both: an audio file simply has no video track,
/// so it gets a fixed header instead of a picture.
class _MediaPlayer extends StatefulWidget {
  const _MediaPlayer({required this.file, required this.audioOnly});

  final File file;
  final bool audioOnly;

  @override
  State<_MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<_MediaPlayer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.file(widget.file);

    try {
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_tick);

      setState(() => _controller = controller);
    } catch (error) {
      await controller.dispose();

      if (!mounted) return;

      setState(() => _error = '$error');
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  String _clock(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_error != null) {
      return _PreviewFrame(
        child: Text(
          'This file could not be played: $_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9297A3), fontSize: 12),
        ),
      );
    }

    if (controller == null) {
      return const _PreviewFrame(
        child: CircularProgressIndicator(color: Color(0xFF9B7BFF)),
      );
    }

    final value = controller.value;

    return _PreviewFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.audioOnly)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Icon(Icons.graphic_eq, color: Color(0xFF9B7BFF), size: 56),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: value.aspectRatio == 0
                    ? 16 / 9
                    : value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),

          const SizedBox(height: 12),

          Row(
            children: [
              IconButton(
                onPressed: () {
                  value.isPlaying ? controller.pause() : controller.play();
                },
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: const Color(0xFF9B7BFF),
                  size: 44,
                ),
              ),

              Expanded(
                child: Slider(
                  value: value.position.inMilliseconds
                      .clamp(0, value.duration.inMilliseconds)
                      .toDouble(),
                  max: value.duration.inMilliseconds.toDouble().clamp(1, 1e9),
                  activeColor: const Color(0xFF9B7BFF),
                  inactiveColor: const Color(0xFF242934),
                  onChanged: (position) {
                    controller.seekTo(Duration(milliseconds: position.round()));
                  },
                ),
              ),

              Text(
                '${_clock(value.position)} / ${_clock(value.duration)}',
                style: const TextStyle(
                  color: Color(0xFF9297A3),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The per-item backup control.
///
/// The copy here is load-bearing. A survivor cannot make a real choice
/// about what leaves their phone unless they are told what each option
/// actually gives them -- including the part that is not finished yet:
/// a cloud copy can be reopened on *this* phone, and restoring it to a
/// new one needs the recovery key that arrives in P7.
class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.item});

  final EvidenceItem item;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  Future<void> _backUp(EvidenceSync sync) async {
    // The button stays, so the feature is visible and its absence is
    // explained -- rather than silently missing, or failing slowly
    // against a bucket that does not exist.
    if (!sync.cloudFileBackupAvailable) {
      await showCloudBackupNotice(context);
      return;
    }

    setState(() => _busy = true);

    try {
      await sync.backUp(widget.item);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Encrypted copy backed up')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_message(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    if (error is SyncUnavailableException) {
      return 'Cloud backup is not set up yet. Nothing has left this phone.';
    }

    if (error is SyncFailedException) {
      return 'Backup did not finish: ${error.message}';
    }

    return 'Backup did not finish: $error';
  }

  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).sync;

    return AnimatedBuilder(
      animation: sync,
      builder: (context, _) {
        final state = sync.stateOf(widget.item.id);
        final backedUp = state == BackupState.backedUp;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF11151D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF242934)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    backedUp
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: backedUp
                        ? const Color(0xFF67E8B1)
                        : const Color(0xFF9297A3),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      backedUp ? 'Backed up' : 'On this phone only',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                backedUp
                    ? 'An encrypted copy is stored in the cloud, and the '
                          'record of it cannot be changed or deleted by '
                          'anyone — including you. It can be opened again on '
                          'this phone. Restoring it to a different phone '
                          'needs a recovery key, which is not built yet.'
                    : 'This evidence exists only here. A record of its '
                          'fingerprint is still sent, so it can always be '
                          'proved this file existed and was not altered — but '
                          'the file itself is lost if this phone is.',
                style: const TextStyle(
                  color: Color(0xFF9297A3),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),

              if (!backedUp) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _backUp(sync),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup_outlined, size: 18),
                    label: Text(
                      _busy
                          ? 'Backing up…'
                          : state == BackupState.failed
                          ? 'Try backup again'
                          : 'Back up this evidence',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9B7BFF),
                      side: const BorderSide(color: Color(0xFF9B7BFF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.report});

  final IntegrityReport report;

  @override
  Widget build(BuildContext context) {
    final passed = report.verified;
    final color = passed ? const Color(0xFF67E8B1) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? Icons.verified_outlined : Icons.gpp_bad_outlined,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passed ? 'Evidence Verified' : 'Verification Failed',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  passed
                      ? 'AES-256-GCM authentication and SHA-256 integrity '
                            'verification successful.'
                      : report.failure ??
                            'The recorded and recalculated hashes do not '
                                'match.',
                  style: const TextStyle(
                    color: Color(0xFF9297A3),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242934)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.monospace = false,
    this.good = false,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9297A3), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: good ? const Color(0xFF67E8B1) : Colors.white,
                fontSize: 13,
                height: 1.4,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
