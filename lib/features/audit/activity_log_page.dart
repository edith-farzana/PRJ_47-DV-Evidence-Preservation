import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../models/audit/audit_entry.dart';
import '../../services/audit/audit_log.dart';

const Color _background = Color(0xFF090B10);
const Color _card = Color(0xFF11151D);
const Color _border = Color(0xFF242934);
const Color _muted = Color(0xFF9297A3);
const Color _good = Color(0xFF67E8B1);
const Color _accent = Color(0xFF9B7BFF);
const Color _warn = Color(0xFFFFC857);

/// Everything the app has recorded, newest first, under a verdict on
/// whether the record itself is intact.
///
/// The verdict comes first because it is the point: a history is only
/// worth reading if it can be shown that nothing was removed from it.
class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  Future<(ChainReport, List<AuditEntry>)>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= _read(AppScope.of(context).audit);
  }

  static Future<(ChainReport, List<AuditEntry>)> _read(AuditLog audit) async {
    final report = await audit.verify();

    List<AuditEntry> entries;

    try {
      entries = await audit.entries();
    } on AuditLogCorruptedException {
      // The report already says why. There is nothing trustworthy to list.
      entries = const [];
    }

    return (report, entries.reversed.toList());
  }

  void _reload() {
    setState(() => _load = _read(AppScope.of(context).audit));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('Activity Log'),
        actions: [
          IconButton(
            tooltip: 'Verify again',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<(ChainReport, List<AuditEntry>)>(
        future: _load,
        builder: (context, snapshot) {
          final data = snapshot.data;

          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final (report, entries) = data;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _StatusCard(report: report),
              const SizedBox(height: 16),
              if (entries.isEmpty && report.intact)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text(
                    'Nothing recorded yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted),
                  ),
                ),
              for (final entry in entries)
                _EntryTile(
                  entry: entry,
                  broken: report.brokenAtSeq == entry.seq,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.report});

  final ChainReport report;

  @override
  Widget build(BuildContext context) {
    final intact = report.intact;
    final color = intact ? _good : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            intact ? Icons.verified_user_outlined : Icons.gpp_bad_outlined,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  intact
                      ? 'Log intact · ${report.entryCount} '
                            '${report.entryCount == 1 ? 'entry' : 'entries'}'
                      : 'This log has been tampered with',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  intact
                      ? 'Every entry links to the one before it, and nothing '
                            'has been removed, changed or cut off the end.'
                      : '${report.problem} Entries from that point on cannot '
                            'be trusted.',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.45,
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

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.broken});

  final AuditEntry entry;

  /// The first entry that failed verification.
  final bool broken;

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year}  '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

  String? _detail() {
    final parts = <String>[
      if (entry.evidenceId != null) 'Evidence ${_short(entry.evidenceId!)}',
      if (entry.detail['type'] != null) '${entry.detail['type']}',
      if (entry.detail['verdict'] != null)
        switch (entry.detail['verdict']) {
          'verified' => 'verified',
          'verifiedOnThisPhone' => 'verified on this phone',
          _ => 'NOT verified',
        },
      if (entry.detail['items'] is List)
        '${(entry.detail['items'] as List).length} item'
            '${(entry.detail['items'] as List).length == 1 ? '' : 's'}'
            '${entry.detail['protected'] == true ? ', password-protected' : ', NOT password-protected'}',
      if ((entry.detail['priorFailedAttempts'] as int? ?? 0) > 0)
        'after ${entry.detail['priorFailedAttempts']} wrong PIN'
            '${entry.detail['priorFailedAttempts'] == 1 ? '' : 's'}',
    ];

    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final type = entry.eventType;

    final (IconData icon, Color color) = switch (type) {
      AuditEventType.unlocked => (Icons.lock_open_outlined, _good),
      AuditEventType.unlockFailed => (Icons.no_encryption_outlined, _warn),
      AuditEventType.panic => (Icons.front_hand_outlined, _accent),
      AuditEventType.autoLocked => (Icons.lock_outline, _muted),
      AuditEventType.captured => (Icons.add_a_photo_outlined, _accent),
      AuditEventType.viewed => (Icons.visibility_outlined, _muted),
      AuditEventType.verified => (Icons.verified_outlined, _good),
      AuditEventType.recordedOnServer => (Icons.cloud_done_outlined, _good),
      AuditEventType.pinChanged => (Icons.password_outlined, _accent),
      AuditEventType.exported => (Icons.ios_share, _warn),
      null => (Icons.help_outline, _muted),
    };

    final detail = _detail();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: broken ? Colors.redAccent : _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type?.label ?? entry.type,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _time(entry.time),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '#${entry.seq}',
            style: TextStyle(
              color: broken ? Colors.redAccent : _muted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
