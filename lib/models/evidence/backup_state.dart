/// Where one piece of evidence has got to on its way to the cloud.
///
/// This is local bookkeeping, never uploaded. The authority for "does a
/// cloud copy exist" is the create-only receipt in Firestore, which
/// survives a reinstall; this is the cache that saves reading it.
enum BackupState {
  /// On this phone only. The default, and deliberately so: media does
  /// not leave the device unless the survivor asks for it.
  localOnly,

  /// An upload is running.
  uploading,

  /// The encrypted blob is in Storage and a receipt was written.
  backedUp,

  /// An upload was attempted and did not finish. The evidence is
  /// untouched on this phone; only the copy failed.
  failed,
}

extension BackupStateLabel on BackupState {
  String get label {
    switch (this) {
      case BackupState.localOnly:
        return 'THIS PHONE ONLY';
      case BackupState.uploading:
        return 'BACKING UP…';
      case BackupState.backedUp:
        return 'BACKED UP';
      case BackupState.failed:
        return 'BACKUP FAILED';
    }
  }
}

/// What is known locally about one item's sync state.
class BackupRecord {
  const BackupRecord({
    this.state = BackupState.localOnly,
    this.metadataSynced = false,
  });

  /// The blob.
  final BackupState state;

  /// Whether the metadata record (hashes and wrapped key) reached
  /// Firestore. Tracked separately because metadata goes up for *every*
  /// item, backed up or not -- that is what makes a later deletion
  /// provable.
  final bool metadataSynced;

  BackupRecord copyWith({BackupState? state, bool? metadataSynced}) {
    return BackupRecord(
      state: state ?? this.state,
      metadataSynced: metadataSynced ?? this.metadataSynced,
    );
  }

  Map<String, Object?> toJson() => {
    'state': state.name,
    'metadataSynced': metadataSynced,
  };

  factory BackupRecord.fromJson(Map<String, dynamic> json) {
    return BackupRecord(
      state: BackupState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => BackupState.localOnly,
      ),
      metadataSynced: json['metadataSynced'] as bool? ?? false,
    );
  }
}
