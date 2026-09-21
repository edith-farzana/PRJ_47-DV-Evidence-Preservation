import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../models/evidence/evidence_item.dart';
import '../../../models/evidence/integrity_report.dart';

/// The full verification report for one piece of evidence.
///
/// Shows each hash that was compared and the verdict for each pair, so
/// the result can be read rather than taken on trust. Re-running is a
/// button, not automatic: verification decrypts the whole file, which
/// for a long video is not free.
class IntegrityPage extends StatefulWidget {
  const IntegrityPage({super.key, required this.item, required this.report});

  final EvidenceItem item;

  /// The report the detail screen already produced, so opening this
  /// screen does not decrypt the file a second time.
  final IntegrityReport report;

  @override
  State<IntegrityPage> createState() => _IntegrityPageState();
}

class _IntegrityPageState extends State<IntegrityPage> {
  static const Color _background = Color(0xFF090B10);
  static const Color _muted = Color(0xFF9297A3);
  static const Color _accent = Color(0xFF9B7BFF);

  late IntegrityReport _report = widget.report;

  bool _running = false;

  Future<void> _rerun() async {
    setState(() => _running = true);

    final storage = AppScope.of(context).storage;

    try {
      final report = await storage.checkIntegrity(widget.item);

      if (!mounted) return;

      setState(() {
        _report = report;
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => _running = false);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not verify: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final report = _report;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Integrity Verification'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(item: item),

          const SizedBox(height: 16),

          _HashCard(
            title: 'Recorded SHA-256',
            icon: Icons.bookmark_border,
            hash: report.recordedPlaintextSha256,
            status: null,
          ),

          const SizedBox(height: 16),

          _HashCard(
            title: 'Recalculated SHA-256',
            icon: Icons.refresh,
            hash: report.recalculatedPlaintextSha256,
            status: report.plaintextMatches,
            absentLabel: 'Could not be recalculated',
          ),

          const SizedBox(height: 16),

          _HashCard(
            title: 'Stored file SHA-256',
            icon: Icons.sd_storage_outlined,
            hash: report.recalculatedCiphertextSha256,
            status: report.ciphertextMatches,
            absentLabel: 'The encrypted file is missing',
          ),

          const SizedBox(height: 16),

          _Verdict(report: report),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _running ? null : _rerun,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(
                _running ? 'Verifying…' : 'Verify Evidence Integrity',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF1A1030),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const StadiumBorder(),
              ),
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'Verification decrypts the evidence again, re-hashes what comes '
            'back and compares it with the hash recorded at capture. The '
            'recorded hash is also bound into the encryption itself, so an '
            'altered file fails to decrypt at all.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242934)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF9B7BFF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(switch (item.type) {
              EvidenceType.photo => Icons.photo_camera_outlined,
              EvidenceType.video => Icons.videocam_outlined,
              EvidenceType.audio => Icons.mic_none,
            }, color: const Color(0xFF9B7BFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.originalFileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Evidence ID: ${item.id}',
                  style: const TextStyle(
                    color: Color(0xFF9297A3),
                    fontSize: 11,
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

class _HashCard extends StatelessWidget {
  const _HashCard({
    required this.title,
    required this.icon,
    required this.hash,
    required this.status,
    this.absentLabel,
  });

  final String title;
  final IconData icon;
  final String? hash;

  /// Null means "nothing to compare this against" -- the recorded hash
  /// is the reference, so it carries no tick of its own.
  final bool? status;

  final String? absentLabel;

  @override
  Widget build(BuildContext context) {
    final missing = hash == null;
    final ok = status ?? true;

    final color = missing || !ok ? Colors.redAccent : const Color(0xFF67E8B1);

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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (status != null)
                Icon(
                  ok ? Icons.check_circle : Icons.cancel,
                  color: color,
                  size: 20,
                ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            hash ?? (absentLabel ?? 'Not available'),
            style: TextStyle(
              color: missing
                  ? Colors.redAccent
                  : (status == null ? const Color(0xFFBFC4CF) : color),
              fontSize: 13,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.report});

  final IntegrityReport report;

  @override
  Widget build(BuildContext context) {
    final passed = report.verified;
    final color = passed ? const Color(0xFF67E8B1) : Colors.redAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242934)),
      ),
      child: Column(
        children: [
          Icon(
            passed ? Icons.verified_user : Icons.gpp_bad,
            color: color,
            size: 64,
          ),

          const SizedBox(height: 14),

          Text(
            passed ? 'INTEGRITY VERIFIED' : 'INTEGRITY NOT VERIFIED',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            passed
                ? 'The evidence decrypts to exactly what was captured, and '
                      'the stored file is unchanged.'
                : report.failure ??
                      'At least one check did not pass. Do not treat this '
                          'item as unaltered.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9297A3),
              fontSize: 13,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 22),

          _Comparison(
            label: 'Recorded ↔ Recalculated',
            passed: report.plaintextMatches,
          ),
          const SizedBox(height: 12),
          _Comparison(
            label: 'Stored file ↔ Recorded',
            passed: report.ciphertextMatches,
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final color = passed ? const Color(0xFF67E8B1) : Colors.redAccent;

    return Row(
      children: [
        Icon(
          passed ? Icons.check_circle : Icons.cancel,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        Text(
          passed ? 'MATCH' : 'NO MATCH',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
