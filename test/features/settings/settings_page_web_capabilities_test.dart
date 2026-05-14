import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import '../../test_backend.dart';
import '../../test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsPage hides desktop-only controls for web capabilities',
      (tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        _buildApp(
          backend: TestAppBackend(),
          capabilities: AppPlatformCapabilities.webCloud(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings_start_with_system_switch')),
          findsNothing);
      expect(find.byKey(const ValueKey('settings_quick_capture_hotkey')),
          findsNothing);
      expect(find.text('Theme'), findsNothing);
      expect(
          find.byKey(const ValueKey('settings_theme_palette')), findsNothing);
      expect(find.text('Auto lock'), findsNothing);
      expect(find.text('Lock now'), findsNothing);
      expect(find.byKey(const ValueKey('settings_about')), findsNothing);
      expect(find.text('Language'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });

  testWidgets('SettingsPage keeps desktop controls for native capabilities',
      (tester) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        _buildApp(
          backend: TestAppBackend(),
          capabilities: AppPlatformCapabilities.native(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings_start_with_system_switch')),
          findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });
}

Widget _buildApp({
  required AppBackend backend,
  required AppPlatformCapabilities capabilities,
}) {
  return AppPlatformCapabilityScope(
    capabilities: capabilities,
    child: AppBackendScope(
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
    ),
  );
}
