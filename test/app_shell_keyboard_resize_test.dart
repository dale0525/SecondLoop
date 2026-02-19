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
      'AppShell mobile scaffold disables extra keyboard resize adjustments',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
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

    final appShellScaffoldFinder = find.ancestor(
      of: find.byType(SlPageSurface).first,
      matching: find.byType(Scaffold),
    );
    final appShellScaffold = tester.widget<Scaffold>(
      appShellScaffoldFinder.first,
    );

    expect(appShellScaffold.resizeToAvoidBottomInset, isFalse);
  });
}
