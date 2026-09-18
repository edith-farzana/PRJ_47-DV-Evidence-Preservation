/// Format checks only. Whether a PIN is *correct* is decided by
/// KeyManager.unlock(), which tries to unwrap the master key with it --
/// there is no stored PIN to compare against.
class PinValidator {
  const PinValidator();

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
}
