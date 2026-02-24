import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/ui/sl_surface.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'Desktop AppShell keeps rail and content visually grouped on very wide windows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    final railRect = tester.getRect(find.byType(NavigationRail));
    final pageSurfaceConstrainedRect = tester.getRect(
      find.descendant(
        of: find.byType(SlPageSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox && widget.constraints.maxWidth == 1120,
        ),
      ),
    );
    final visualGap = pageSurfaceConstrainedRect.left - railRect.right;

    expect(visualGap, lessThan(220));
  });
}
