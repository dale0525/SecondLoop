import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('native settings shows migration archive entry',
      (WidgetTester tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_buildTestApp(TestAppBackend()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings_migration_archive')),
          findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });
}

Widget _buildTestApp(AppBackend backend) {
  return AppBackendScope(
    backend: backend,
    child: SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: SettingsPage(),
          ),
        ),
      ),
    ),
  );
}
