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
      'Todo linking uses local semantic first, then BYOK fallback when cloud embeddings unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': true,
    });

    final backend = _Backend(
      todos: const [
        Todo(
          id: 't1',
          title: 'Buy milk',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    final cloudAuth = _FakeCloudAuthController(idToken: null);
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.test',
              modelName: 'gpt-test',
            ),
            child: SubscriptionScope(
              controller: subscriptions,
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      backend.calls,
      <String>['searchSimilarTodoThreads', 'searchSimilarTodoThreadsBrok'],
    );
    expect(
      backend.calls,
      isNot(contains('searchSimilarTodoThreadsCloudGateway')),
    );
  });

  testWidgets('Todo linking falls back to local semantic when Pro not entitled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': true,
    });

    final backend = _Backend(
      todos: const [
        Todo(
          id: 't1',
          title: 'Buy milk',
          status: 'open',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
    final cloudAuth = _FakeCloudAuthController(idToken: null);
    final subscriptions =
        _FakeSubscriptionStatusController(SubscriptionStatus.notEntitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            gatewayConfig: const CloudGatewayConfig(
              baseUrl: 'https://gateway.test',
              modelName: 'gpt-test',
            ),
            child: SubscriptionScope(
              controller: subscriptions,
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(backend.calls, contains('searchSimilarTodoThreadsBrok'));
  });
}

final class _Backend extends TestAppBackend {
  _Backend({required List<Todo> todos})
      : _todos = List<Todo>.from(todos),
        super();

  final List<Todo> _todos;
  final List<String> calls = <String>[];

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    calls.add('searchSimilarTodoThreads');
    return const <TodoThreadMatch>[];
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    calls.add('searchSimilarTodoThreadsBrok');
    return const <TodoThreadMatch>[];
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
    calls.add('searchSimilarTodoThreadsCloudGateway');
    return const <TodoThreadMatch>[];
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final existing = _todos.firstWhere((t) => t.id == todoId);
    return Todo(
      id: existing.id,
      title: existing.title,
      dueAtMs: existing.dueAtMs,
      status: newStatus,
      sourceEntryId: sourceMessageId ?? existing.sourceEntryId,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: existing.updatedAtMs,
      reviewStage: existing.reviewStage,
      nextReviewAtMs: existing.nextReviewAtMs,
      lastReviewAtMs: existing.lastReviewAtMs,
    );
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
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

  @override
  Future<void> signOut() async {}
}

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}
