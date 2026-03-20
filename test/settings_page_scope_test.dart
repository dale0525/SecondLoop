import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/navigation/inherited_scope_page_wrapper.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets('SettingsPage preserves scopes when opened from root navigator',
      (tester) async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (rootContext) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_scoped_shell'),
                  onPressed: () {
                    Navigator.of(rootContext).push(
                      MaterialPageRoute(
                        builder: (_) => AppBackendScope(
                          backend: backend,
                          child: SessionScope(
                            sessionKey: key,
                            lock: () {},
                            child: Builder(
                              builder: (scopedContext) => Scaffold(
                                body: Center(
                                  child: ElevatedButton(
                                    key: const ValueKey('open_settings_page'),
                                    onPressed: () {
                                      final navigator =
                                          Navigator.of(rootContext);
                                      pushPageWithInheritedScopes(
                                        navigator,
                                        scopedContext,
                                        const SettingsPage(),
                                      );
                                    },
                                    child: const Text('Open settings'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open shell'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open_scoped_shell')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('open_settings_page')),
    );

    await tester.tap(find.byKey(const ValueKey('open_settings_page')));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(SettingsPage));

    final aiSourceTile = find.byKey(const ValueKey('settings_ai_source'));
    await tester.ensureVisible(aiSourceTile);
    await tester.pump();
    await tester.tap(aiSourceTile);
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(AiSettingsPage));
  });
}
