import 'package:flutter/material.dart';

import '../../models/evidence/evidence_item.dart';
import '../../services/storage/evidence_storage.dart';

class EvidenceVaultPage extends StatefulWidget {
  const EvidenceVaultPage({super.key});

  @override
  State<EvidenceVaultPage> createState() => _EvidenceVaultPageState();
}

class _EvidenceVaultPageState extends State<EvidenceVaultPage> {
  late Future<List<EvidenceItem>> _evidenceFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _evidenceFuture = EvidenceStorage.instance.getEvidence();
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load evidence.\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
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

  const _EvidenceCard({
    required this.item,
    required this.icon,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242934)),
      ),
      child: Row(
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
                  style: const TextStyle(
                    color: Color(0xFF9297A3),
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '$date • ${item.fileSizeLabel}',
                  style: const TextStyle(
                    color: Color(0xFF9297A3),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          const Column(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFF67E8B1), size: 20),
              SizedBox(height: 4),
              Text(
                'STORED',
                style: TextStyle(
                  color: Color(0xFF67E8B1),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
