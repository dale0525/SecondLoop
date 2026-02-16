import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/features/actions/todo/todo_thread_match.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Link to task shows local results and AI analyzing while cloud reranks',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 4200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(
        {'embeddings_data_consent_v1': true});

    final cloudDelayCompleter = Completer<void>();
    final backend = _SemanticLinkingBackend(
      cloudDelayCompleter: cloudDelayCompleter,
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'follow up on this',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't_local',
          title: 'Local task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        Todo(
          id: 't_cloud',
          title: 'Cloud task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      localMatches: const [
        TodoThreadMatch(todoId: 't_local', distance: 0.36),
      ],
      cloudMatches: const [
        TodoThreadMatch(todoId: 't_cloud', distance: 0.08),
      ],
    );

    await tester.pumpWidget(_wrapChatWithCloud(backend: backend));
    await tester.pumpAndSettle();

    await _openTodoLinkSheet(tester);

    final sheet = find.byKey(const ValueKey('todo_note_link_sheet'));
    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    final localTaskInSheet = find.descendant(
      of: sheet,
      matching: find.text('Local task'),
    );
    expect(localTaskInSheet, findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_note_link_ai_analyzing')),
      findsOneWidget,
    );

    Navigator.of(tester.element(sheet)).pop('t_local');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(backend.appendedTodoIds, <String>['t_local']);
    expect(backend.cloudCalls, 1);

    cloudDelayCompleter.complete();
    await tester.pumpAndSettle();

    expect(backend.appendedTodoIds, <String>['t_local']);
  });

  testWidgets(
      'Link to task skips cloud rerank when local confidence is very high',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 4200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(
        {'embeddings_data_consent_v1': true});

    final backend = _SemanticLinkingBackend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'follow up on this',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't_local',
          title: 'Very sure local task',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      localMatches: const [
        TodoThreadMatch(todoId: 't_local', distance: 0.05),
      ],
      cloudMatches: const [
        TodoThreadMatch(todoId: 't_local', distance: 0.01),
      ],
    );

    await tester.pumpWidget(_wrapChatWithCloud(backend: backend));
    await tester.pumpAndSettle();

    await _openTodoLinkSheet(tester);

    expect(find.byKey(const ValueKey('todo_note_link_sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_note_link_ai_analyzing')),
      findsNothing,
    );
    expect(backend.cloudCalls, 0);
  });
}

Future<void> _openTodoLinkSheet(WidgetTester tester) async {
  await tester.longPress(find.text('follow up on this'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('message_action_link_todo')));
  await tester.pump();
}

Widget _wrapChatWithCloud({required AppBackend backend}) {
  return wrapWithI18n(
    MaterialApp(
      home: CloudAuthScope(
        controller: _FakeCloudAuthController(idToken: 'token-for-test'),
        gatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://gateway.test',
          modelName: 'gpt-test',
        ),
        child: SubscriptionScope(
          controller:
              _FakeSubscriptionStatusController(SubscriptionStatus.entitled),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: AppBackendScope(
              backend: backend,
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
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
}

final class _SemanticLinkingBackend extends TestAppBackend {
  _SemanticLinkingBackend({
    required this.todos,
    required this.localMatches,
    required this.cloudMatches,
    this.cloudDelayCompleter,
    super.initialMessages,
  });

  final List<Todo> todos;
  final List<TodoThreadMatch> localMatches;
  final List<TodoThreadMatch> cloudMatches;
  final Completer<void>? cloudDelayCompleter;

  final List<String> appendedTodoIds = <String>[];
  int localCalls = 0;
  int cloudCalls = 0;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(todos);

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    localCalls += 1;
    return List<TodoThreadMatch>.from(localMatches);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsCloudGateway(
    Uint8List key,
    String query, {
    int topK = 10,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    cloudCalls += 1;
    if (cloudDelayCompleter != null) {
      await cloudDelayCompleter!.future;
    }
    return List<TodoThreadMatch>.from(cloudMatches);
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    appendedTodoIds.add(todoId);
    return TodoActivity(
      id: 'a1',
      todoId: todoId,
      activityType: 'note',
      content: content,
      sourceMessageId: sourceMessageId,
      createdAtMs: 0,
    );
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({required String? idToken}) : _idToken = idToken;

  final String? _idToken;

  @override
  String? get uid => 'uid-test';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => _idToken;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  Future<void> reload() async {}
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}
