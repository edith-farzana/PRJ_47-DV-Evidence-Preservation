import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_scope.dart';
import '../../models/evidence/evidence_item.dart';
import '../../services/export/court_exporter.dart';

const Color _background = Color(0xFF090B10);
const Color _card = Color(0xFF11151D);
const Color _border = Color(0xFF242934);
const Color _muted = Color(0xFF9297A3);
const Color _accent = Color(0xFF9B7BFF);
const Color _warn = Color(0xFFFFC857);
const Color _good = Color(0xFF67E8B1);

enum _Stage { choose, working, done }

/// Builds a bundle for a lawyer or court, then hands it to the share
/// sheet.
///
/// The bundle, and the password shown here, exist only while this screen
/// is open. Leaving it -- by Done, by Back, or by panic -- destroys the
/// bundle, and the password is never stored anywhere.
class ExportPage extends StatefulWidget {
  const ExportPage({super.key, required this.items});

  final List<EvidenceItem> items;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  late final Set<String> _selected = {for (final item in widget.items) item.id};

  bool _protect = true;
  _Stage _stage = _Stage.choose;
  ExportProgress? _progress;
  ExportResult? _result;
  String? _error;

  /// Read by the exporter between items, so a panic stops it.
  bool _closed = false;

  @override
  void dispose() {
    _closed = true;
    unawaited(_result?.discard());
    super.dispose();
  }

  List<EvidenceItem> get _chosen =>
      widget.items.where((item) => _selected.contains(item.id)).toList();

  Future<void> _create() async {
    final scope = AppScope.of(context);

    setState(() {
      _stage = _Stage.working;
      _progress = null;
      _error = null;
    });

    try {
      final exporter = CourtExporter(
        storage: scope.storage,
        sync: scope.sync,
        audit: scope.audit,
        cacheDirectory: await getTemporaryDirectory(),
      );

      final result = await exporter.export(
        _chosen,
        protect: _protect,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _closed,
      );

      if (!mounted) {
        await result.discard();
        return;
      }

      setState(() {
        _result = result;
        _stage = _Stage.done;
      });
    } on ExportCancelledException {
      // The screen is gone; the exporter has already cleaned up.
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = '$error';
        _stage = _Stage.choose;
      });
    }
  }

  Future<void> _share() async {
    final bundle = _result?.bundle;
    if (bundle == null) return;

    // Kept after sharing, in case she needs to send it to someone else
    // too. It is destroyed when she leaves this screen.
    await SharePlus.instance.share(
      ShareParams(files: [XFile(bundle.path, mimeType: 'application/zip')]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Export for a Lawyer'),
      ),
      body: switch (_stage) {
        _Stage.choose => _chooseView(),
        _Stage.working => _workingView(),
        _Stage.done => _doneView(_result!),
      },
    );
  }

  // ---------------------------------------------------------------
  // Choosing
  // ---------------------------------------------------------------

  Widget _chooseView() {
    final count = _selected.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const Text(
          'Creates one file holding the evidence you choose, a PDF record of '
          "each item's fingerprints and history, and instructions anyone "
          'can follow to check that nothing has been changed.',
          style: TextStyle(color: _muted, height: 1.5),
        ),

        const SizedBox(height: 16),

        const _Notice(
          icon: Icons.warning_amber_rounded,
          color: _warn,
          text:
              'The evidence in the bundle is decrypted. Once you share it, '
              "it is outside this app's protection. Only verified items are "
              'included.',
        ),

        const SizedBox(height: 16),

        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _protect ? _border : _warn),
          ),
          child: SwitchListTile(
            value: _protect,
            onChanged: (value) => setState(() => _protect = value),
            activeThumbColor: _accent,
            title: const Text(
              'Protect with a password',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _protect
                  ? 'Strongly encrypted. Opens with the free 7-Zip. You will '
                        'be shown the password once, to pass on separately.'
                  : 'Anyone who gets the file can open it — including anyone '
                        'who can read the email or chat you send it through. '
                        'Only turn this off if the person receiving it '
                        'cannot open protected files.',
              style: TextStyle(
                color: _protect ? _muted : _warn,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Text(
              '$count of ${widget.items.length} selected',
              style: const TextStyle(color: Colors.white),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (count == widget.items.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(widget.items.map((item) => item.id));
                }
              }),
              child: Text(
                count == widget.items.length ? 'Select none' : 'Select all',
              ),
            ),
          ],
        ),

        for (final item in widget.items)
          _ItemTile(
            item: item,
            selected: _selected.contains(item.id),
            onChanged: (value) => setState(() {
              value ? _selected.add(item.id) : _selected.remove(item.id);
            }),
          ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.error_outline,
            color: Colors.redAccent,
            text: 'The export did not finish: $_error',
          ),
        ],

        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: count == 0 ? null : _create,
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text('Create bundle ($count)'),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xFF1A1030),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Working
  // ---------------------------------------------------------------

  Widget _workingView() {
    final progress = _progress;
    final label = progress == null
        ? 'Preparing…'
        : progress.done >= progress.total
        ? 'Writing the bundle…'
        : 'Verifying ${progress.done + 1} of ${progress.total}…';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress == null || progress.total == 0
                  ? null
                  : progress.done / progress.total,
              color: _accent,
              backgroundColor: _border,
            ),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            const Text(
              'Each item is checked before it is included.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Done
  // ---------------------------------------------------------------

  Widget _doneView(ExportResult result) {
    final manifest = result.manifest;
    final password = result.password;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (result.bundle == null)
          const _Notice(
            icon: Icons.gpp_bad_outlined,
            color: Colors.redAccent,
            text:
                'Nothing could be exported. None of the selected items '
                'passed verification; the reasons are below.',
          )
        else
          _Notice(
            icon: Icons.check_circle_outline,
            color: _good,
            text:
                'Bundle ready: ${manifest.items.length} '
                '${manifest.items.length == 1 ? 'item' : 'items'}, each '
                'verified, with a PDF record of its fingerprints and history.',
          ),

        if (password != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Password',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  password,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Write it down, or tell the person you are sending it to by '
                  'phone. Never send it in the same message as the file. It '
                  'will not be shown again once you leave this screen.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],

        if (manifest.notExported.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Not included',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final item in manifest.notExported)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Notice(
                icon: Icons.remove_circle_outline,
                color: _warn,
                text: '${item.type}: ${item.reason}',
              ),
            ),
        ],

        const SizedBox(height: 20),

        if (result.bundle != null)
          FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.ios_share),
            label: const Text('Share bundle'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: const Color(0xFF1A1030),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
          ),

        const SizedBox(height: 10),

        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: _border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: const StadiumBorder(),
          ),
          child: const Text('Done'),
        ),

        const SizedBox(height: 10),

        const Text(
          'Leaving this screen deletes the bundle from this phone. Anyone you '
          'shared it with keeps their copy.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.selected,
    required this.onChanged,
  });

  final EvidenceItem item;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final local = item.capturedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) => onChanged(value ?? false),
        activeColor: _accent,
        secondary: Icon(switch (item.type) {
          EvidenceType.photo => Icons.image_outlined,
          EvidenceType.video => Icons.videocam_outlined,
          EvidenceType.audio => Icons.mic_none,
        }, color: _accent),
        title: Text(
          item.typeLabel,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          '${two(local.day)}/${two(local.month)}/${local.year}  '
          '${two(local.hour)}:${two(local.minute)} • ${item.fileSizeLabel}',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
