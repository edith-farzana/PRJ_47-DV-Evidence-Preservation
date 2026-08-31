import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/features/auth/domain/pin_validator.dart';

void main() {
  const validator = PinValidator();

  group('PinValidator', () {
    test('accepts a valid 4-digit PIN', () {
      expect(validator.isValid('1234'), isTrue);
    });

    test('rejects PIN shorter than 4 digits', () {
      expect(validator.isValid('123'), isFalse);
    });

    test('rejects PIN longer than 4 digits', () {
      expect(validator.isValid('12345'), isFalse);
    });

    test('rejects non-numeric PIN', () {
      expect(validator.isValid('12ab'), isFalse);
    });

    test('returns an error for an empty PIN', () {
      expect(
        validator.validate(''),
        'Please enter your PIN.',
      );
    });

    test('returns an error for non-numeric PIN', () {
      expect(
        validator.validate('12ab'),
        'PIN must contain numbers only.',
      );
    });

    test('returns an error for incorrect PIN length', () {
      expect(
        validator.validate('123'),
        'PIN must be 4 digits.',
      );
    });

    test('returns null for a valid PIN', () {
      expect(validator.validate('1234'), isNull);
    });
  });
}