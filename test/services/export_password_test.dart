import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/services/export/export_password.dart';

void main() {
  // Five groups of four, from the alphabet without 0/O and 1/I/L.
  final shape = RegExp(r'^[2-9A-HJKMNP-Z]{4}(-[2-9A-HJKMNP-Z]{4}){4}$');

  test('has the documented shape', () {
    for (var i = 0; i < 200; i++) {
      expect(ExportPassword.generate(), matches(shape));
    }
  });

  // Read aloud over a phone or copied from paper by someone else: one
  // misread character locks them out.
  test('never uses characters that are easy to misread', () {
    final all = List.generate(500, (_) => ExportPassword.generate()).join();

    for (final confusable in ['0', 'O', '1', 'I', 'L']) {
      expect(all, isNot(contains(confusable)));
    }
  });

  test('carries about 99 bits', () {
    expect(ExportPassword.alphabet.length, 31);
    expect(ExportPassword.groups * ExportPassword.groupLength, 20);
  });

  test('successive passwords differ', () {
    final passwords = {
      for (var i = 0; i < 1000; i++) ExportPassword.generate(),
    };

    expect(passwords, hasLength(1000));
  });
}
