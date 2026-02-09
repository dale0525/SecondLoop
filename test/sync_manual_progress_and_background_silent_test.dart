import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Manual Download shows progress, while background sync on '
      'Todo detail stays silent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final pullCompleter = Completer<int>();
    final backend = _Backend(manualPullCompleter: pullCompleter);
    final engine = SyncEngine(
      syncRunner: _NoopRunner(),
      loadConfig: () async => null,
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: Scaffold(body: SyncSettingsPage(configStore: store)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    final settingsList = find.byType(ListView);
    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.dragUntilVisible(
      downloadButton,
      settingsList,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(downloadButton).onPressed, isNotNull);

    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pump();

    expect(backend.pullCalls, 1);

    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);

    pullCompleter.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: const TodoDetailPage(
                  initialTodo: Todo(
                    id: 't1',
                    title: 'Task',
                    status: 'open',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todoList = find.byType(ListView);
    await tester.drag(todoList, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('item 000', findRichText: true), findsNothing);

    backend.prepareDelayedRefresh();
    engine.notifyExternalChange();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('item 000', findRichText: true), findsNothing);

    backend.completeDelayedRefresh();
    await tester.pumpAndSettle();
    expect(find.text('item 000', findRichText: true), findsNothing);
  });
}

final class _NoopRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _Backend extends TestAppBackend {
  _Backend({required this.manualPullCompleter});

  final Completer<int> manualPullCompleter;
  int pullCalls = 0;

  final List<TodoActivity> _activities = List<TodoActivity>.generate(
    80,
    (index) => TodoActivity(
      id: 'a$index',
      todoId: 't1',
      activityType: 'note',
      content: 'item ${index.toString().padLeft(3, '0')}',
      createdAtMs: index,
    ),
  );

  Completer<List<TodoActivity>>? _delayedRefresh;
  int _listCalls = 0;

  void prepareDelayedRefresh() {
    _delayedRefresh = Completer<List<TodoActivity>>();
  }

  void completeDelayedRefresh() {
    final pending = _delayedRefresh;
    if (pending == null || pending.isCompleted) return;
    pending.complete(List<TodoActivity>.from(_activities));
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) {
    _listCalls += 1;
    final pending = _delayedRefresh;
    if (_listCalls > 1 && pending != null && !pending.isCompleted) {
      return pending.future;
    }
    return Future<List<TodoActivity>>.value(
        List<TodoActivity>.from(_activities));
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    pullCalls += 1;
    return manualPullCompleter.future;
  }
}
