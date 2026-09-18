import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/features/auth/domain/unlock_sequence.dart';

void main() {
  group('UnlockSequence', () {
    test('maps keyboard operators to calculator keys', () {
      expect(UnlockSequence.normalize('7*3/1'), '7×3÷1');
      expect(UnlockSequence.normalize('7x3'), '7×3');
    });

    test('strips spaces and a trailing =', () {
      expect(UnlockSequence.normalize(' 7 * 3 - 1 = '), '7×3-1');
    });

    test('stored form ends in = to match the calculator key log', () {
      expect(UnlockSequence.toStored('7×3-1'), '7×3-1=');
    });

    test('accepts a sequence with an operator', () {
      expect(UnlockSequence.validate('7×3-1'), isNull);
    });

    test('rejects a plain number, which people type by accident', () {
      expect(UnlockSequence.validate('12345'), isNotNull);
    });

    test('rejects sequences that are too short', () {
      expect(UnlockSequence.validate('1+2'), isNotNull);
    });

    test('rejects sequences the calculator cannot hold', () {
      expect(UnlockSequence.validate('1+${'1' * 31}'), isNotNull);
    });

    test('rejects characters that are not calculator keys', () {
      expect(UnlockSequence.validate('12+ab'), isNotNull);
    });
  });
}
