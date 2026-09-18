/// The calculator key sequence that opens the PIN screen.
///
/// The user types it on a normal keyboard during setup, so `*` and `/`
/// are accepted and mapped to the calculator's `×` and `÷` keys. The
/// stored form is exactly what the calculator records as keys are
/// pressed, ending in `=`.
class UnlockSequence {
  const UnlockSequence._();

  static const int minLength = 4;

  /// The calculator keeps only the last 32 key presses.
  static const int maxLength = 31;

  static final RegExp _allowed = RegExp(r'^[0-9.+\-×÷]+$');
  static final RegExp _operator = RegExp(r'[+\-×÷]');

  /// Maps keyboard input to calculator keys and strips a trailing `=`.
  static String normalize(String input) {
    var sequence = input
        .replaceAll(' ', '')
        .replaceAll('*', '×')
        .replaceAll('x', '×')
        .replaceAll('X', '×')
        .replaceAll('/', '÷');

    while (sequence.endsWith('=')) {
      sequence = sequence.substring(0, sequence.length - 1);
    }

    return sequence;
  }

  /// Returns an error message, or null when [normalized] is usable.
  static String? validate(String normalized) {
    if (normalized.isEmpty) {
      return 'Enter a sequence.';
    }

    if (!_allowed.hasMatch(normalized)) {
      return 'Use only digits, a decimal point and + - × ÷.';
    }

    if (normalized.length < minLength) {
      return 'Use at least $minLength keys.';
    }

    if (normalized.length > maxLength) {
      return 'Use at most $maxLength keys.';
    }

    // Without an operator, "1234 =" is something people type while
    // actually using a calculator, and would open the PIN screen by
    // accident in front of whoever is watching.
    if (!_operator.hasMatch(normalized)) {
      return 'Include at least one of + - × ÷.';
    }

    return null;
  }

  /// The form stored and compared against the calculator's key log.
  static String toStored(String normalized) => '$normalized=';
}
