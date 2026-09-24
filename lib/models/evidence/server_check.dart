/// How the server's record of one piece of evidence compares with the
/// phone's.
///
/// The server record is the one copy nobody can alter: the rules deny
/// update and delete to everyone, including the account that wrote it.
/// So it catches the case a local check cannot -- someone holding the
/// phone *and* the PIN, who replaces a file and its entry in the
/// encrypted list together.
enum ServerCheckStatus {
  /// Every compared field agrees with the server.
  matches,

  /// The server disagrees. Evidence of tampering, and shown as such.
  mismatch,

  /// No record under this device's account: never synced, or the app
  /// was reinstalled and signed in as someone new. Not a failure.
  notOnServer,

  /// Offline, not configured, or sign-in failed. The server was not
  /// reached, which says nothing either way about the evidence.
  unavailable,
}

/// The fields compared against the server, by their Firestore names.
///
/// `capturedAt` is included because *when* evidence existed is half of
/// what the server record proves; a moved date would otherwise go
/// unnoticed.
const List<String> serverCheckedFields = [
  'plaintextSha256',
  'ciphertextSha256',
  'capturedAt',
];

class ServerCheck {
  const ServerCheck._({
    required this.status,
    this.serverPlaintextSha256,
    this.mismatchedFields = const [],
    this.reason,
  });

  const ServerCheck.matches({String? serverPlaintextSha256})
    : this._(
        status: ServerCheckStatus.matches,
        serverPlaintextSha256: serverPlaintextSha256,
      );

  const ServerCheck.mismatch({
    required List<String> fields,
    String? serverPlaintextSha256,
  }) : this._(
         status: ServerCheckStatus.mismatch,
         mismatchedFields: fields,
         serverPlaintextSha256: serverPlaintextSha256,
       );

  const ServerCheck.notOnServer()
    : this._(
        status: ServerCheckStatus.notOnServer,
        reason:
            'There is no server record for this evidence yet. It may have '
            'been captured without a connection and not synced since.',
      );

  const ServerCheck.unavailable(String reason)
    : this._(status: ServerCheckStatus.unavailable, reason: reason);

  final ServerCheckStatus status;

  /// The evidentiary fingerprint the server holds, for display. Null
  /// when the server was not reached or holds no record.
  final String? serverPlaintextSha256;

  /// Which of [serverCheckedFields] disagreed. Empty unless [status] is
  /// [ServerCheckStatus.mismatch].
  final List<String> mismatchedFields;

  /// Why the server could not confirm anything, in words for the user.
  final String? reason;

  bool get matches => status == ServerCheckStatus.matches;

  bool get disagrees => status == ServerCheckStatus.mismatch;

  /// Whether the server actually weighed in, for or against.
  bool get reached =>
      status == ServerCheckStatus.matches ||
      status == ServerCheckStatus.mismatch;
}
