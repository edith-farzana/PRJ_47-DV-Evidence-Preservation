import 'integrity_report.dart';
import 'server_check.dart';

/// The overall answer to "has this evidence been altered?", from the
/// local check and the server check together.
enum Verdict {
  /// The phone's checks pass, and the independent server record agrees.
  /// The strongest thing the app can say.
  verified,

  /// The phone's checks pass, but the server could not be consulted, or
  /// holds no record. True as far as it goes -- and it says so, rather
  /// than claiming more.
  verifiedOnThisPhone,

  /// Something failed, or the server disagrees. Never softened.
  notVerified,
}

/// Joins [IntegrityReport] (the phone) with [ServerCheck] (the server).
///
/// A server that cannot be reached is not evidence of tampering and must
/// never look like it. A server that *disagrees* always is, and it
/// overrides a passing local check: the local records are exactly what
/// someone holding the phone and the PIN could have replaced.
class VerificationVerdict {
  const VerificationVerdict({required this.local, required this.server});

  final IntegrityReport local;
  final ServerCheck server;

  Verdict get verdict {
    if (!local.verified) return Verdict.notVerified;

    switch (server.status) {
      case ServerCheckStatus.mismatch:
        return Verdict.notVerified;
      case ServerCheckStatus.matches:
        return Verdict.verified;
      case ServerCheckStatus.notOnServer:
      case ServerCheckStatus.unavailable:
        return Verdict.verifiedOnThisPhone;
    }
  }

  String get headline {
    switch (verdict) {
      case Verdict.verified:
        return 'INTEGRITY VERIFIED';
      case Verdict.verifiedOnThisPhone:
        return 'VERIFIED ON THIS PHONE';
      case Verdict.notVerified:
        return 'INTEGRITY NOT VERIFIED';
    }
  }

  /// One or two sentences explaining the headline in plain words.
  String get explanation {
    if (!local.verified) {
      return local.failure ??
          'At least one check on this phone did not pass. Do not treat this '
              'item as unaltered.';
    }

    switch (server.status) {
      case ServerCheckStatus.matches:
        return 'The evidence decrypts to exactly what was captured, and it '
            'matches the independent record on the server — the one copy '
            'nobody can change.';
      case ServerCheckStatus.mismatch:
        return 'The record on the server does not match this phone '
            '(${_fieldNames(server.mismatchedFields)}). The server record '
            'cannot be changed, so this phone\'s copy or its record has been '
            'altered since capture.';
      case ServerCheckStatus.notOnServer:
        return 'The evidence is unaltered as far as this phone can tell. '
            '${server.reason}';
      case ServerCheckStatus.unavailable:
        return 'The evidence is unaltered as far as this phone can tell. '
            'The server could not be reached to confirm it: '
            '${server.reason}';
    }
  }

  static String _fieldNames(List<String> fields) {
    const names = {
      'plaintextSha256': 'the evidence fingerprint',
      'ciphertextSha256': 'the stored-file fingerprint',
      'capturedAt': 'the capture time',
    };

    final described = fields.map((field) => names[field] ?? field).toList();

    if (described.isEmpty) return 'unknown field';
    if (described.length == 1) return described.single;

    return '${described.sublist(0, described.length - 1).join(', ')} and '
        '${described.last}';
  }
}
