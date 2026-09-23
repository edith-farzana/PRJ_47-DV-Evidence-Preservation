/// Whether encrypted file copies can be uploaded to the cloud.
///
/// **Off, deliberately.** Firebase Storage is not enabled on the project:
/// it requires a billing account, and we chose not to add one yet.
///
/// What still works with this off, and it is most of the point:
/// every capture's metadata — its hashes, a timestamp, a size — still
/// goes to Firestore, where it cannot be changed or deleted by anyone.
/// Evidence is still provably unaltered, and its deletion still
/// provable. The only missing half is keeping a second copy of the file
/// itself, so a lost phone means a lost file.
///
/// The flag exists because `google-services.json` names a storage
/// bucket whether or not that bucket was ever created. Without this,
/// an upload would travel to Google, retry, and fail slowly with
/// something like `object-not-found` — leaving the item badged BACKUP
/// FAILED, which would tell a survivor her evidence is at risk when
/// nothing is wrong with it.
///
/// To turn on once Storage exists: build with
/// `--dart-define=CLOUD_BACKUP=true`, or change the default below.
/// Nothing else has to change.
const bool cloudFileBackupEnabled = bool.fromEnvironment(
  'CLOUD_BACKUP',
  defaultValue: false,
);
