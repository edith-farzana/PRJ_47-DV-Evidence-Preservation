import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../models/evidence/backup_state.dart';
import '../../models/evidence/evidence_item.dart';
import '../../services/storage/evidence_index.dart';
import '../evidence/cloud_backup_notice.dart';
import '../evidence/detail/evidence_detail_page.dart';

class EvidenceVaultPage extends StatefulWidget {
  const EvidenceVaultPage({super.key});

  @override
  State<EvidenceVaultPage> createState() => _EvidenceVaultPageState();
}

class _EvidenceVaultPageState extends State<EvidenceVaultPage> {
  late Future<List<EvidenceItem>> _evidenceFuture;

  List<EvidenceItem> _items = const [];

  bool _loaded = false;
  bool _backingUpAll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_loaded) {
      _loaded = true;
      _reload();

      // The receipts on the server are the authority for what has a
      // cloud copy, so local state is rebuilt from them once per visit.
      unawaited(AppScope.of(context).sync.reconcile());
    }
  }

  void _reload() {
    final scope = AppScope.of(context);

    final future = scope.storage.getEvidence();

    _evidenceFuture = future;

    unawaited(
      future
          .then((items) async {
            if (mounted) setState(() => _items = items);

            // Catch-up for anything captured while offline. Metadata
            // goes up for every item; the media does not.
            await scope.sync.syncPendingMetadata(items);
          })
          // A load failure is already shown by the FutureBuilder.
          .catchError((Object _) {}),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _evidenceFuture;
  }

  Future<void> _backUpAll() async {
    final sync = AppScope.of(context).sync;
    final messenger = ScaffoldMessenger.of(context);

    if (!sync.cloudFileBackupAvailable) {
      await showCloudBackupNotice(context, multiple: true);
      return;
    }

    final pending = sync.notBackedUp(_items);

    if (pending == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Everything is already backed up')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF11151D),
        title: const Text(
          'Back up everything?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'An encrypted copy of $pending '
          '${pending == 1 ? 'item' : 'items'} will be uploaded. Nobody, '
          'including us, can decrypt them without your PIN.\n\n'
          'A backed-up item can be opened again on this phone. Moving it '
          'to a different phone needs a recovery key, which is not built '
          'yet.',
          style: const TextStyle(color: Color(0xFF9297A3), height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Back up'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _backingUpAll = true);

    final uploaded = await sync.backUpAll(_items);

    if (!mounted) return;

    setState(() => _backingUpAll = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          uploaded == pending
              ? 'Backed up $uploaded of $pending'
              : 'Backed up $uploaded of $pending. The rest are still on '
                    'this phone only — try again when you have signal.',
        ),
      ),
    );
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
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Back up all',
              onPressed: _backingUpAll ? null : _backUpAll,
              icon: _backingUpAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
            ),
        ],
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

          final sync = AppScope.of(context).sync;

          return RefreshIndicator(
            onRefresh: _refresh,
            // Rebuilds the list as uploads change state, so a card never
            // keeps saying "this phone only" after a backup finished.
            child: AnimatedBuilder(
              animation: sync,
              builder: (context, _) => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];

                  return _EvidenceCard(
                    item: item,
                    icon: _iconFor(item.type),
                    date: _date(item),
                    backupState: sync.stateOf(item.id),
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EvidenceDetailPage(item: item),
                      ),
                    ),
                  );
                },
              ),
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
  final BackupState backupState;
  final VoidCallback onOpen;

  const _EvidenceCard({
    required this.item,
    required this.icon,
    required this.date,
    required this.backupState,
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

              const SizedBox(height: 6),

              _BackupChip(state: backupState),
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

/// Where this item's media lives: this phone, or also the cloud.
///
/// Shown on every card because "is my evidence safe if he takes my
/// phone" is the question the vault exists to answer, and the answer
/// differs per item by design.
class _BackupChip extends StatelessWidget {
  const _BackupChip({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (state) {
      BackupState.backedUp => (Icons.cloud_done_outlined, Color(0xFF67E8B1)),
      BackupState.uploading => (Icons.cloud_sync_outlined, Color(0xFF9B7BFF)),
      BackupState.failed => (Icons.cloud_off_outlined, Colors.orangeAccent),
      BackupState.localOnly => (
        Icons.phone_android_outlined,
        Color(0xFF9297A3),
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          state.label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
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
