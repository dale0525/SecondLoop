import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage renders note as Markdown', (tester) async {
    final backend = _Backend(
      activities: const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'note',
          content: '**bold**',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
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
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('TodoDetailPage renders status change as visual transition',
      (tester) async {
    final backend = _Backend(
      activities: const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'status_change',
          fromStatus: 'open',
          toStatus: 'done',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
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
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('todo_detail_status_change_transition')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_detail_status_change_from')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('todo_detail_status_change_to')),
      findsOneWidget,
    );
  });
}

final class _Backend extends AppBackend {
  _Backend({required List<TodoActivity> activities})
      : _activities = List<TodoActivity>.from(activities);

  final List<TodoActivity> _activities;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      const <Message>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(
          Uint8List key, String messageId, String content) async =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      List<TodoActivity>.from(_activities);

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>[];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async => '';

  @override
  Future<bool> setActiveEmbeddingModelName(
          Uint8List key, String modelName) async =>
      false;

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {}

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {}

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 2));

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      throw UnimplementedError();
}
