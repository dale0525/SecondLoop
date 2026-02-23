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
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Manual Download shows progress while background sync keeps '
      'chat content visible', (tester) async {
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
      _wrap(
        backend: backend,
        engine: engine,
        child: SyncSettingsPage(configStore: store),
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

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.dragUntilVisible(
      downloadButton,
      find.byType(ListView),
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

    const conversation = Conversation(
      id: 'loop_home',
      title: 'Loop',
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        engine: engine,
        child: const ChatPage(conversation: conversation),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('chat_sync_marker_000', findRichText: true), findsOne);

    backend.prepareDelayedMessagesRefresh();
    engine.notifyExternalChange();
    await tester.pump();

    expect(find.text('chat_sync_marker_000', findRichText: true), findsOne);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    backend.completeDelayedMessagesRefresh();
    await tester.pumpAndSettle();

    expect(find.text('chat_sync_marker_000', findRichText: true), findsOne);
  });
}

Widget _wrap({
  required AppBackend backend,
  required SyncEngine engine,
  required Widget child,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: engine,
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
}

final class _NoopRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _Backend extends TestAppBackend {
  _Backend({required this.manualPullCompleter})
      : _messages = <Message>[
          const Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: 'chat_sync_marker_000',
            createdAtMs: 0,
            isMemory: true,
          ),
        ],
        super(
          initialMessages: const [
            Message(
              id: 'm1',
              conversationId: 'loop_home',
              role: 'user',
              content: 'chat_sync_marker_000',
              createdAtMs: 0,
              isMemory: true,
            ),
          ],
        );

  final Completer<int> manualPullCompleter;
  final List<Message> _messages;

  Completer<List<Message>>? _delayedMessages;
  int _listMessagesCalls = 0;
  int pullCalls = 0;

  void prepareDelayedMessagesRefresh() {
    _delayedMessages = Completer<List<Message>>();
  }

  void completeDelayedMessagesRefresh() {
    final pending = _delayedMessages;
    if (pending == null || pending.isCompleted) return;
    pending.complete(List<Message>.from(_messages));
  }

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) {
    _listMessagesCalls += 1;
    final pending = _delayedMessages;
    if (_listMessagesCalls > 1 && pending != null && !pending.isCompleted) {
      return pending.future;
    }
    return Future<List<Message>>.value(List<Message>.from(_messages));
  }

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
