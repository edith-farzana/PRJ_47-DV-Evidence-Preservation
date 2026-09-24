import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../models/audit/audit_entry.dart';
import '../../../models/evidence/evidence_item.dart';
import '../../../models/evidence/integrity_report.dart';
import '../../../models/evidence/server_check.dart';
import '../../../models/evidence/verification_verdict.dart';

const Color _good = Color(0xFF67E8B1);
const Color _partial = Color(0xFFFFC857);
const Color _muted = Color(0xFF9297A3);

/// The full verification report for one piece of evidence.
///
/// Shows each fingerprint that was compared and the verdict for each
/// pair, so the result can be read rather than taken on trust. Re-running
/// is a button, not automatic: verification decrypts the whole file,
/// which for a long video is not free, and it contacts the server.
class IntegrityPage extends StatefulWidget {
  const IntegrityPage({
    super.key,
    required this.item,
    required this.report,
    required this.server,
  });

  final EvidenceItem item;

  /// The results the detail screen already produced, so opening this
  /// screen does not decrypt the file or contact the server again.
  final IntegrityReport report;
  final ServerCheck server;

  @override
  State<IntegrityPage> createState() => _IntegrityPageState();
}

class _IntegrityPageState extends State<IntegrityPage> {
  static const Color _background = Color(0xFF090B10);
  static const Color _accent = Color(0xFF9B7BFF);

  late IntegrityReport _report = widget.report;
  late ServerCheck _server = widget.server;

  bool _running = false;

  Future<void> _rerun() async {
    setState(() => _running = true);

    final scope = AppScope.of(context);

    try {
      final (report, server) = await (
        scope.storage.checkIntegrity(widget.item),
        scope.sync.checkServerRecord(widget.item),
      ).wait;

      if (!mounted) return;

      setState(() {
        _report = report;
        _server = server;
        _running = false;
      });

      unawaited(
        scope.audit.record(
          AuditEventType.verified,
          evidenceId: widget.item.id,
          detail: {
            'verdict': VerificationVerdict(
              local: report,
              server: server,
            ).verdict.name,
          },
        ),
      );
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
    final server = _server;

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

          _ServerCard(server: server),

          const SizedBox(height: 16),

          _Verdict(
            result: VerificationVerdict(local: report, server: server),
          ),

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
            'back and compares it with the fingerprint recorded at capture. '
            'It then checks that fingerprint against the record on the '
            'server, which nobody can change or delete — so a file replaced '
            'together with its record on this phone is still caught.',
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
      decoration: _cardDecoration,
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
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final BoxDecoration _cardDecoration = BoxDecoration(
  color: const Color(0xFF11151D),
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: const Color(0xFF242934)),
);

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

    final color = missing || !ok ? Colors.redAccent : _good;

    return _CardFrame(
      title: title,
      icon: icon,
      trailing: status == null
          ? null
          : Icon(
              ok ? Icons.check_circle : Icons.cancel,
              color: color,
              size: 20,
            ),
      child: Text(
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
    );
  }
}

/// The server's fingerprint, or why there is none.
///
/// Three looks, deliberately: green when it matches, red when it
/// disagrees, and grey when the server was not consulted. Grey is not a
/// softer red -- being offline says nothing about the evidence.
class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server});

  final ServerCheck server;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData mark) = switch (server.status) {
      ServerCheckStatus.matches => (_good, Icons.check_circle),
      ServerCheckStatus.mismatch => (Colors.redAccent, Icons.cancel),
      ServerCheckStatus.notOnServer ||
      ServerCheckStatus.unavailable => (_muted, Icons.remove_circle_outline),
    };

    final body = switch (server.status) {
      ServerCheckStatus.matches ||
      ServerCheckStatus.mismatch => server.serverPlaintextSha256 ?? '—',
      ServerCheckStatus.notOnServer => 'No server record yet',
      ServerCheckStatus.unavailable => 'Not checked — ${server.reason}',
    };

    return _CardFrame(
      title: 'Server record SHA-256',
      icon: Icons.cloud_outlined,
      trailing: Icon(mark, color: color, size: 20),
      child: Text(
        body,
        style: TextStyle(
          color: color,
          fontSize: 13,
          height: 1.5,
          fontFamily: server.reached ? 'monospace' : null,
        ),
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
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
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.result});

  final VerificationVerdict result;

  @override
  Widget build(BuildContext context) {
    final report = result.local;
    final server = result.server;

    final (Color color, IconData icon) = switch (result.verdict) {
      Verdict.verified => (_good, Icons.verified_user),
      Verdict.verifiedOnThisPhone => (_partial, Icons.phonelink_lock),
      Verdict.notVerified => (Colors.redAccent, Icons.gpp_bad),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: _cardDecoration,
      child: Column(
        children: [
          Icon(icon, color: color, size: 64),

          const SizedBox(height: 14),

          Text(
            result.headline,
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
            result.explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.5),
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
          const SizedBox(height: 12),
          _Comparison(
            label: 'Recorded ↔ Server',
            // Null when the server was not consulted: shown as NOT
            // CHECKED, never as a failure.
            passed: server.reached ? server.matches : null,
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.label, required this.passed});

  final String label;

  /// Null when this pair was not compared.
  final bool? passed;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String word) = switch (passed) {
      true => (_good, Icons.check_circle, 'MATCH'),
      false => (Colors.redAccent, Icons.cancel, 'NO MATCH'),
      null => (_muted, Icons.remove_circle_outline, 'NOT CHECKED'),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        Text(
          word,
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
