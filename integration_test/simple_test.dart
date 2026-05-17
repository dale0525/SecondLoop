import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('integration harness starts without a Rust runtime', (
    WidgetTester tester,
  ) async {
    expect(tester.binding, isNotNull);
  });
}
