import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';
import 'package:secondloop/core/quick_capture/quick_capture_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/quick_capture/quick_capture_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('quick capture compact panel follows dark theme', (tester) async {
    SharedPreferences.setMockInitialValues({
      'welcome_guide_seen_v1': true,
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(560, 72));

    final controller = QuickCaptureController();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      wrapWithI18n(
        AppBackendScope(
          backend: TestAppBackend(),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: QuickCaptureScope(
              controller: controller,
              child: MaterialApp(
                theme: AppTheme.dark(),
                navigatorKey: navigatorKey,
                home: QuickCaptureOverlay(
                  navigatorKey: navigatorKey,
                  child: const Scaffold(body: SizedBox.shrink()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.show();
    await tester.pumpAndSettle();

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('quick_capture_panel')),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(decoration.color, AppShellPalette.darkPanel);
    expect(decoration.border, isA<Border>());
    expect(
      (decoration.border! as Border).top.color,
      AppShellPalette.darkLine,
    );

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('quick_capture_input')),
    );
    expect(input.style?.color, AppShellPalette.darkInk);
    expect(input.decoration?.hintStyle?.color,
        AppShellPalette.darkMuted.withOpacity(0.78));
  });
}
