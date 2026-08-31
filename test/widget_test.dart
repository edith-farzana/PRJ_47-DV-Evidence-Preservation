import 'package:flutter_test/flutter_test.dart';
import 'package:secure_evidence_app/app/app.dart';

void main() {
  testWidgets('Secure Evidence app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const SecureEvidenceApp());

    expect(find.text('Secure Evidence'), findsWidgets);
  });
}
