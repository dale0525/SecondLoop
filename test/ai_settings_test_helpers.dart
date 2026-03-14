import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openAiAdvancedSettings(WidgetTester tester) async {
  final advancedSettings =
      find.byKey(const ValueKey('ai_settings_home_advanced_settings'));
  await tester.dragUntilVisible(
    advancedSettings,
    find.byType(ListView).first,
    const Offset(0, -220),
  );
  await tester.pumpAndSettle();
  await tester.tap(advancedSettings);
  await tester.pumpAndSettle();
}
