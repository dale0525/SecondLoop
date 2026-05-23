import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  testWidgets('narrow desktop AppShell exposes Tasks navigation',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AppShell(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app_shell_bottom_nav')),
        findsOneWidget,
      );
      expect(find.text('Tasks'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('narrow desktop AppShell preserves settings update badge',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      UpdateBadgePrefs.value.value = 'v1.2.3';
      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AppShell(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app_tab_settings_update_badge_bottom_nav')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      UpdateBadgePrefs.resetForTests();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
