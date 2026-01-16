import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Secure storage works on macOS', (WidgetTester tester) async {
    if (!Platform.isMacOS) return;

    const storage = FlutterSecureStorage(
      mOptions: MacOsOptions(),
    );
    const key = 'secondloop_secure_storage_probe';

    await storage.delete(key: key);
    await storage.write(key: key, value: 'ok');
    final value = await storage.read(key: key);
    expect(value, 'ok');
    await storage.delete(key: key);
  });
}
