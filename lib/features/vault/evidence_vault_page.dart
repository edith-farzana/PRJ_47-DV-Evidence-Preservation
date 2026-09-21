import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../models/evidence/evidence_item.dart';
import '../../services/storage/evidence_index.dart';
import '../evidence/detail/evidence_detail_page.dart';

class EvidenceVaultPage extends StatefulWidget {
  const EvidenceVaultPage({super.key});

  @override
  State<EvidenceVaultPage> createState() => _EvidenceVaultPageState();
}

class _EvidenceVaultPageState extends State<EvidenceVaultPage> {
  late Future<List<EvidenceItem>> _evidenceFuture;

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_loaded) {
      _loaded = true;
      _reload();
    }
  }

  void _reload() {
    _evidenceFuture = AppScope.of(context).storage.getEvidence();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _evidenceFuture;
  }

  IconData _iconFor(EvidenceType type) {
    switch (type) {
      case EvidenceType.photo:
        return Icons.image_outlined;

      case EvidenceType.video:
        return Icons.videocam_outlined;

      case EvidenceType.audio:
        return Icons.mic_none;
    }
  }

  String _date(EvidenceItem item) {
    final local = item.capturedAt.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');

    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B10),
        foregroundColor: Colors.white,
        title: const Text('My Evidence'),
      ),
      body: FutureBuilder<List<EvidenceItem>>(
        future: _evidenceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            // Never fall through to "No evidence yet": the evidence may
            // well still be on disk, and saying otherwise would be the
            // most damaging thing this screen could do.
            final tampered = snapshot.error is EvidenceIndexCorruptedException;

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tampered ? Icons.gpp_bad_outlined : Icons.error_outline,
                      color: Colors.redAccent,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tampered
                          ? 'The evidence list could not be verified'
                          : 'Could not load evidence',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tampered
                          ? 'It may have been altered or replaced. Your '
                                'encrypted evidence files have not been '
                                'deleted. Do not clear this app\'s data.'
                          : '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF9297A3)),
                    ),
                  ],
                ),
              ),
            );
          }

          final items = snapshot.data ?? [];

          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 130),
                  Icon(
                    Icons.folder_outlined,
                    color: Color(0xFF9B7BFF),
                    size: 70,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'No evidence yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 35),
                    child: Text(
                      'Captured photos, videos and audio '
                      'will appear here automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9297A3)),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];

                return _EvidenceCard(
                  item: item,
                  icon: _iconFor(item.type),
                  date: _date(item),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EvidenceDetailPage(item: item),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  final EvidenceItem item;
  final IconData icon;
  final String date;
  final VoidCallback onOpen;

  const _EvidenceCard({
    required this.item,
    required this.icon,
    required this.date,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242934)),
      ),
      // Material, not a bare Container: otherwise the card's colour is
      // painted over the tap ripple.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: const EdgeInsets.all(16), child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF9B7BFF).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFF9B7BFF), size: 27),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.typeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                item.originalFileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9297A3), fontSize: 12),
              ),

              const SizedBox(height: 4),

              Text(
                '$date • ${item.fileSizeLabel}',
                style: const TextStyle(color: Color(0xFF9297A3), fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        _ProtectionBadge(item: item),

        const Icon(Icons.chevron_right, color: Color(0xFF9297A3), size: 20),
      ],
    );
  }
}

/// ENCRYPTED plus the start of the evidentiary hash, or a warning for a
/// record without crypto metadata. Integrity *verification* (re-hashing
/// on demand) is P7; this reports what the record carries.
class _ProtectionBadge extends StatelessWidget {
  const _ProtectionBadge({required this.item});

  final EvidenceItem item;

  @override
  Widget build(BuildContext context) {
    final encrypted = item.isEncrypted;
    final color = encrypted ? const Color(0xFF67E8B1) : Colors.orangeAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(
          encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
          color: color,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          encrypted ? 'ENCRYPTED' : 'UNPROTECTED',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (encrypted) ...[
          const SizedBox(height: 2),
          Text(
            item.shortHash.substring(0, 8),
            style: const TextStyle(
              color: Color(0xFF9297A3),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}
