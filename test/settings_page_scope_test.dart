import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/navigation/inherited_scope_page_wrapper.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/settings_page.dart';

import 'noop_sync_runner.dart';
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
  testWidgets('pushed settings pages preserve the source theme',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData.dark(),
          home: Theme(
            data: ThemeData.light(),
            child: Builder(
              builder: (scopedContext) => Scaffold(
                body: ElevatedButton(
                  key: const ValueKey('open_themed_page'),
                  onPressed: () {
                    pushPageWithInheritedScopes(
                      navigatorKey.currentState!,
                      scopedContext,
                      Builder(
                        builder: (context) => Scaffold(
                          body: Text(Theme.of(context).brightness.name),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open themed page'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open_themed_page')));
    await tester.pumpAndSettle();

    expect(find.text('light'), findsOneWidget);
    expect(find.text('dark'), findsNothing);
  });

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

    expect(find.byKey(const ValueKey('settings_runtime_mode')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_ai_source')), findsNothing);
  });

  testWidgets(
      'pushPageWithCapturedInheritedScopesOrFallback falls back to root push without captured context',
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
      const Scaffold(body: Text('Fallback page')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fallback page'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets(
      'captured inherited scope snapshot preserves sync engine after source shell unmounts',
      (tester) async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 9));
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    InheritedScopeCapture? capturedScopes;
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (rootContext) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_captured_scope_shell'),
                  onPressed: () {
                    Navigator.of(rootContext).push(
                      MaterialPageRoute(
                        builder: (_) => AppBackendScope(
                          backend: backend,
                          child: SessionScope(
                            sessionKey: key,
                            lock: () {},
                            child: SyncEngineScope(
                              engine: engine,
                              child: Builder(
                                builder: (scopedContext) {
                                  capturedScopes = captureInheritedScopes(
                                    scopedContext,
                                  );
                                  return Scaffold(
                                    body: Center(
                                      child: ElevatedButton(
                                        key: const ValueKey(
                                          'open_settings_from_captured_snapshot',
                                        ),
                                        onPressed: () {
                                          pushPageWithCapturedInheritedScopesOrFallback<
                                              void>(
                                            Navigator.of(rootContext),
                                            null,
                                            const SettingsPage(),
                                            capturedScopes: capturedScopes,
                                          );
                                        },
                                        child: const Text('Open settings'),
                                      ),
                                    ),
                                  );
                                },
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

    await tester.tap(find.byKey(const ValueKey('open_captured_scope_shell')));
    await tester.pumpAndSettle();
    expect(capturedScopes, isNotNull);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open shell'), findsOneWidget);

    pushPageWithCapturedInheritedScopesOrFallback<void>(
      navigatorKey.currentState!,
      null,
      const SettingsPage(),
      capturedScopes: capturedScopes,
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Push'), findsNothing);
  });
}
