import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/models/evidence/integrity_report.dart';
import 'package:secure_evidence_app/models/evidence/server_check.dart';
import 'package:secure_evidence_app/models/evidence/verification_verdict.dart';

/// Every row of the verdict table, because each one is a claim the app
/// makes to a survivor about her evidence.
void main() {
  final hash = 'a' * 64;

  const localPass = IntegrityReport(
    itemId: 'one',
    blobExists: true,
    recordedPlaintextSha256: 'p',
    recalculatedPlaintextSha256: 'p',
    recordedCiphertextSha256: 'c',
    recalculatedCiphertextSha256: 'c',
  );

  const localFail = IntegrityReport(
    itemId: 'one',
    blobExists: true,
    recordedPlaintextSha256: 'p',
    recordedCiphertextSha256: 'c',
    recalculatedCiphertextSha256: 'x',
    failure: 'Authentication failed while decrypting.',
  );

  final matches = ServerCheck.matches(serverPlaintextSha256: hash);
  const mismatch = ServerCheck.mismatch(fields: ['plaintextSha256']);
  const notOnServer = ServerCheck.notOnServer();
  const unavailable = ServerCheck.unavailable(
    'there is no internet connection.',
  );

  Verdict verdictOf(IntegrityReport local, ServerCheck server) =>
      VerificationVerdict(local: local, server: server).verdict;

  group('a failing local check', () {
    test('is never rescued by the server', () {
      for (final server in [matches, mismatch, notOnServer, unavailable]) {
        expect(
          verdictOf(localFail, server),
          Verdict.notVerified,
          reason: 'server ${server.status}',
        );
      }
    });

    test('explains itself with the local failure', () {
      final result = VerificationVerdict(local: localFail, server: matches);

      expect(result.explanation, contains('Authentication failed'));
    });
  });

  group('a passing local check', () {
    test('plus a matching server record is fully verified', () {
      final result = VerificationVerdict(local: localPass, server: matches);

      expect(result.verdict, Verdict.verified);
      expect(result.headline, 'INTEGRITY VERIFIED');
    });

    // The case the cross-check exists for: the phone's records agree
    // with each other because both were replaced.
    test('is overridden by a server that disagrees', () {
      final result = VerificationVerdict(local: localPass, server: mismatch);

      expect(result.verdict, Verdict.notVerified);
      expect(result.headline, 'INTEGRITY NOT VERIFIED');
      expect(result.explanation, contains('the evidence fingerprint'));
      expect(result.explanation, contains('cannot be changed'));
    });

    test('with no server record is verified on this phone only', () {
      final result = VerificationVerdict(local: localPass, server: notOnServer);

      expect(result.verdict, Verdict.verifiedOnThisPhone);
      expect(result.headline, 'VERIFIED ON THIS PHONE');
    });

    // Not reaching the server says nothing about the evidence, and must
    // never read like an accusation.
    test('with the server unreachable is verified on this phone only', () {
      final result = VerificationVerdict(local: localPass, server: unavailable);

      expect(result.verdict, Verdict.verifiedOnThisPhone);
      expect(result.explanation, contains('no internet connection'));
      expect(result.explanation, isNot(contains('has been altered')));
    });
  });

  test('several disagreeing fields read as a sentence', () {
    final result = VerificationVerdict(
      local: localPass,
      server: const ServerCheck.mismatch(
        fields: ['plaintextSha256', 'ciphertextSha256', 'capturedAt'],
      ),
    );

    expect(
      result.explanation,
      contains(
        'the evidence fingerprint, the stored-file fingerprint and the '
        'capture time',
      ),
    );
  });
}
