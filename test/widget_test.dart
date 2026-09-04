import 'package:flutter_test/flutter_test.dart';

import 'package:secure_evidence_app/app/app.dart';
import 'package:secure_evidence_app/features/calculator/presentation/calculator_page.dart';

void main() {
  testWidgets('Secure Evidence app opens calculator', (tester) async {
    await tester.pumpWidget(const SecureEvidenceApp());

    expect(find.byType(CalculatorPage), findsOneWidget);
  });
}
