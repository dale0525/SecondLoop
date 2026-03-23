import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/navigation/inherited_scope_page_wrapper.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_ask_ai_settings_page.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/features/settings/media_annotation_settings_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'ai_settings_test_helpers.dart';
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

Future<void> _openScopedSettingsPage(
  WidgetTester tester, {
  required AppBackend backend,
  required Uint8List key,
}) async {
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
                                    final navigator = Navigator.of(rootContext);
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
}

Future<void> _openAiSettingsFromSettings(WidgetTester tester) async {
  final aiEntry = find.byKey(const ValueKey('settings_ai_source'));
  await tester.dragUntilVisible(
    aiEntry,
    find.byType(ListView),
    const Offset(0, -240),
  );
  await tester.pumpAndSettle();
  await tester.tap(aiEntry);
  await tester.pumpAndSettle();

  expect(find.byType(AiSettingsPage), findsOneWidget);
}

Future<void> _expectAiMediaSectionAvailable(WidgetTester tester) async {
  final listView = find.byType(ListView).first;
  final mediaSection =
      find.byKey(const ValueKey('ai_settings_section_media_understanding'));
  await tester.dragUntilVisible(
    mediaSection,
    listView,
    const Offset(0, -260),
  );
  await tester.pumpAndSettle();

  final embeddedRoot = find.byKey(MediaAnnotationSettingsPage.embeddedRootKey);
  await tester.dragUntilVisible(
    embeddedRoot,
    listView,
    const Offset(0, -260),
  );
  await tester.pumpAndSettle();

  expect(embeddedRoot, findsOneWidget);
}

void main() {
  testWidgets('pushPageWithCapturedInheritedScopes no-ops without context',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await pushPageWithCapturedInheritedScopes<void>(
      navigatorKey.currentState!,
      null,
      const SettingsPage(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
      'pushPageWithCapturedInheritedScopes no-ops with unmounted context',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    BuildContext? capturedScopedContext;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (rootContext) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key:
                      const ValueKey('open_scoped_shell_for_unmounted_context'),
                  onPressed: () {
                    Navigator.of(rootContext).push(
                      MaterialPageRoute(
                        builder: (_) => Builder(
                          builder: (scopedContext) {
                            capturedScopedContext = scopedContext;
                            return Scaffold(
                              body: Center(
                                child: ElevatedButton(
                                  key: const ValueKey('close_scoped_shell'),
                                  onPressed: () =>
                                      Navigator.of(scopedContext).pop(),
                                  child: const Text('Close shell'),
                                ),
                              ),
                            );
                          },
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

    await tester.tap(
      find.byKey(const ValueKey('open_scoped_shell_for_unmounted_context')),
    );
    await tester.pumpAndSettle();
    expect(capturedScopedContext, isNotNull);

    await tester.tap(find.byKey(const ValueKey('close_scoped_shell')));
    await tester.pumpAndSettle();

    await pushPageWithCapturedInheritedScopes<void>(
      navigatorKey.currentState!,
      capturedScopedContext,
      const SettingsPage(),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Open shell'), findsOneWidget);
  });

  testWidgets('SettingsPage preserves scopes when opened from root navigator',
      (tester) async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await _openScopedSettingsPage(
      tester,
      backend: backend,
      key: key,
    );
    await _openAiSettingsFromSettings(tester);
    await openAiAdvancedSettings(tester);
    await _expectAiMediaSectionAvailable(tester);
  });

  testWidgets(
      'Ask AI advanced replacement preserves scopes when settings starts at root',
      (tester) async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await _openScopedSettingsPage(
      tester,
      backend: backend,
      key: key,
    );
    await _openAiSettingsFromSettings(tester);

    final askAiEntry =
        find.byKey(const ValueKey('ai_settings_open_ask_ai_settings'));
    await tester.dragUntilVisible(
      askAiEntry,
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(askAiEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AiAskAiSettingsPage), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('ask_ai_settings_open_advanced')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai_settings_section_ask_ai')),
      findsOneWidget,
    );
    expect(find.byType(AiAskAiSettingsPage), findsNothing);

    await _expectAiMediaSectionAvailable(tester);
  });

  testWidgets('deferred root callback can reuse captured scoped context',
      (tester) async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 7));
    BuildContext? capturedScopedContext;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (rootContext) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_deferred_shell'),
                  onPressed: () {
                    Navigator.of(rootContext).push(
                      MaterialPageRoute(
                        builder: (_) => AppBackendScope(
                          backend: backend,
                          child: SessionScope(
                            sessionKey: key,
                            lock: () {},
                            child: Builder(
                              builder: (scopedContext) {
                                capturedScopedContext = scopedContext;
                                return Scaffold(
                                  body: Center(
                                    child: ElevatedButton(
                                      key: const ValueKey(
                                          'open_settings_deferred'),
                                      onPressed: () {
                                        pushPageWithInheritedScopes(
                                          Navigator.of(rootContext),
                                          capturedScopedContext ?? rootContext,
                                          const SettingsPage(),
                                        );
                                      },
                                      child: const Text('Open settings later'),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open deferred shell'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open_deferred_shell')));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('open_settings_deferred')),
    );

    await tester.tap(find.byKey(const ValueKey('open_settings_deferred')));
    await tester.pump();
    await _pumpUntilFound(tester, find.byType(SettingsPage));

    await _openAiSettingsFromSettings(tester);
    await openAiAdvancedSettings(tester);
    await _expectAiMediaSectionAvailable(tester);
  });

  testWidgets(
      'pushPageWithCapturedInheritedScopesOrFallback no-ops without captured context',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    pushPageWithCapturedInheritedScopesOrFallback<void>(
      navigatorKey.currentState!,
      null,
      const SettingsPage(),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}
