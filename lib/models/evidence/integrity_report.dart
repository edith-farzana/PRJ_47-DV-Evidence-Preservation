/// The result of re-checking one piece of evidence against what was
/// recorded when it was captured.
///
/// Two independent checks are reported, because they fail for different
/// reasons and mean different things:
///
///  * **Ciphertext** -- the stored blob is hashed and compared with
///    `ciphertextSha256`. Catches storage corruption or a substituted
///    blob without needing the key.
///  * **Plaintext** -- the blob is decrypted and the recovered bytes are
///    hashed and compared with `plaintextSha256`. This is the
///    evidentiary check: it proves the evidence is what was captured.
///
/// Note what a *passing* plaintext check does and does not add. The
/// recorded hash is bound into the ciphertext as AAD, so decryption
/// itself already fails if either was altered -- a mismatch normally
/// surfaces as [failure], not as two different hashes. Re-hashing is
/// still worth doing: it is the check an examiner expects to see, and
/// it catches a fault between decryption and display.
class IntegrityReport {
  const IntegrityReport({
    required this.itemId,
    required this.blobExists,
    this.recordedPlaintextSha256,
    this.recalculatedPlaintextSha256,
    this.recordedCiphertextSha256,
    this.recalculatedCiphertextSha256,
    this.failure,
  });

  /// No crypto metadata: the record predates encryption and there is
  /// nothing to verify against.
  factory IntegrityReport.unverifiable(String itemId) {
    return IntegrityReport(
      itemId: itemId,
      blobExists: true,
      failure:
          'This record was created before evidence was encrypted, so it '
          'carries no hash to verify against.',
    );
  }

  final String itemId;

  /// False when the encrypted file is missing from the evidence
  /// directory, which is a finding in itself.
  final bool blobExists;

  final String? recordedPlaintextSha256;

  /// Null when decryption failed, in which case [failure] says why.
  final String? recalculatedPlaintextSha256;

  final String? recordedCiphertextSha256;
  final String? recalculatedCiphertextSha256;

  /// Why verification could not complete. Null on a clean pass.
  final String? failure;

  bool get plaintextMatches =>
      recordedPlaintextSha256 != null &&
      recordedPlaintextSha256 == recalculatedPlaintextSha256;

  bool get ciphertextMatches =>
      recordedCiphertextSha256 != null &&
      recordedCiphertextSha256 == recalculatedCiphertextSha256;

  /// True only when every check passed. Anything else -- a missing
  /// file, a failed decryption, a hash that moved -- is not a pass.
  bool get verified =>
      blobExists && failure == null && plaintextMatches && ciphertextMatches;
}
