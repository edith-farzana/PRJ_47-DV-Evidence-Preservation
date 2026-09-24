import 'dart:math';

/// Generates the password for a protected export bundle.
///
/// It has to be strong on its own. The ZIP format's AES encryption
/// derives its key with only 1,000 PBKDF2 iterations -- fixed by the
/// format, not ours to raise -- so a short or guessable password would
/// be the weak point of the whole bundle. 20 characters from this
/// 31-letter alphabet is about 99 bits: far beyond guessing, whatever the
/// iteration count.
///
/// The alphabet leaves out 0/O and 1/I/L, because this password is read
/// aloud over a phone or copied from paper by someone else, and one
/// misread character locks them out.
class ExportPassword {
  ExportPassword._();

  static const String alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  static const int groups = 5;
  static const int groupLength = 4;

  static final Random _random = Random.secure();

  /// e.g. `K7QF-M2XP-9HTD-R4WN-B8JC`. The hyphens are part of the
  /// password, so it is typed exactly as shown.
  static String generate() {
    return List.generate(
      groups,
      (_) => List.generate(
        groupLength,
        (_) => alphabet[_random.nextInt(alphabet.length)],
      ).join(),
    ).join('-');
  }
}
