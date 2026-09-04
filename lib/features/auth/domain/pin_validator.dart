class PinValidator {
  const PinValidator();

  static const String secretPin = '2580';

  /// Returns null when the PIN format is valid.
  /// Returns an error message when the PIN format is invalid.
  String? validate(String pin) {
    if (pin.isEmpty) {
      return 'Please enter your PIN.';
    }

    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN must contain numbers only.';
    }

    if (pin.length != 4) {
      return 'PIN must be 4 digits.';
    }

    return null;
  }

  /// Checks whether the PIN has a valid 4-digit format.
  bool isValid(String pin) {
    return validate(pin) == null;
  }

  /// Checks whether the supplied PIN is the actual secret PIN.
  bool matchesSecret(String pin) {
    return pin == secretPin;
  }
}
