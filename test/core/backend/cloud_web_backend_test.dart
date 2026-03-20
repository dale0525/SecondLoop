import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/cloud_web_backend.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  group('CloudWebBackend', () {
    test('creates conversation and stores messages in memory', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      final inserted = await backend.insertMessage(
        key,
        conversation.id,
        role: 'user',
        content: 'hello from web',
      );

      final conversations = await backend.listConversations(key);
      final messages = await backend.listMessages(key, conversation.id);

      expect(conversations, hasLength(1));
      expect(conversations.single.title, 'Web Chat');
      expect(messages, hasLength(1));
      expect(messages.single.id, inserted.id);
      expect(messages.single.content, 'hello from web');
    });

    test('stores web attachments and serves bytes from memory', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final bytes = Uint8List.fromList('hello web'.codeUnits);
      const attachment = Attachment(
        sha256: 'sha-text',
        mimeType: 'text/plain',
        path: 'vault/sha-text.bin',
        byteLen: 9,
        createdAtMs: 0,
      );

      backend.rememberAttachment(attachment, bytes: bytes);

      final loadedAttachment = await backend.readAttachmentBySha256('sha-text');
      final loadedBytes =
          await backend.readAttachmentBytes(Uint8List(0), sha256: 'sha-text');

      expect(loadedAttachment?.sha256, 'sha-text');
      expect(String.fromCharCodes(loadedBytes), 'hello web');
    });

    test('getMessageById finds inserted messages in memory', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      final inserted = await backend.insertMessage(
        key,
        conversation.id,
        role: 'assistant',
        content: 'stored reply',
      );

      final loaded = await backend.getMessageById(key, inserted.id);

      expect(loaded, isNotNull);
      expect(loaded!.id, inserted.id);
      expect(loaded.content, 'stored reply');
    });

    test('setMessageDeleted can restore a previously deleted message',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      final inserted = await backend.insertMessage(
        key,
        conversation.id,
        role: 'user',
        content: 'restore me',
      );

      await backend.setMessageDeleted(key, inserted.id, true);
      expect(await backend.listMessages(key, conversation.id), isEmpty);

      await backend.setMessageDeleted(key, inserted.id, false);
      final restored = await backend.listMessages(key, conversation.id);

      expect(restored, hasLength(1));
      expect(restored.single.id, inserted.id);
      expect(restored.single.content, 'restore me');
    });

    test('runAiPromptCloudGateway delegates to chat client', () async {
      final client = _FakeCloudWebChatClient(responseText: 'cloud result');
      final backend = CloudWebBackend(chatClient: client);

      final result = await backend.runAiPromptCloudGateway(
        Uint8List(0),
        prompt: 'rank my tasks',
        gatewayBaseUrl: 'https://gateway.test',
        idToken: 'token-1',
        modelName: 'cloud',
      );

      expect(result, 'cloud result');
      expect(client.calls, hasLength(1));
      expect(client.calls.single.idToken, 'token-1');
      expect(client.calls.single.messages.single['content'], 'rank my tasks');
    });

    test('unsupported native-only methods throw controlled error', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );

      expect(
        () => backend.unlockWithPassword('secret'),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('not available in web'),
          ),
        ),
      );
    });

    test('stores todos in memory and lists them back', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      final created = await backend.upsertTodo(
        key,
        id: 'todo:web',
        title: 'Ship web task hub',
        dueAtMs: 123,
        status: 'open',
        reviewStage: 1,
        nextReviewAtMs: 456,
        manualImportanceNudgeScore: 1,
        manualUrgencyNudgeScore: -1,
      );

      final todos = await backend.listTodos(key);

      expect(todos, hasLength(1));
      expect(todos.single.id, created.id);
      expect(todos.single.title, 'Ship web task hub');
      expect(todos.single.dueAtMs, 123);
      expect(todos.single.reviewStage, 1);
      expect(todos.single.nextReviewAtMs, 456);
      expect(todos.single.manualImportanceNudgeScore, 1);
      expect(todos.single.manualUrgencyNudgeScore, -1);
    });

    test('transitionTodo patches todo fields atomically on web', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:web',
        title: 'Ship web task hub',
        dueAtMs: 123,
        status: 'open',
        reviewStage: 1,
        nextReviewAtMs: 456,
        manualImportanceNudgeScore: 1,
      );

      final updated = await backend.transitionTodo(
        key,
        todoId: 'todo:web',
        newStatus: 'in_progress',
        dueAtMs: 789,
        reviewStage: 2,
        nextReviewAtMs: 999,
        clearManualImportanceNudgeScore: true,
        manualUrgencyNudgeScore: 1,
      );

      expect(updated.status, 'in_progress');
      expect(updated.dueAtMs, 789);
      expect(updated.reviewStage, 2);
      expect(updated.nextReviewAtMs, 999);
      expect(updated.manualImportanceNudgeScore, 0);
      expect(updated.manualUrgencyNudgeScore, 1);
    });

    test('deleteTodo removes redo task from in-memory web store', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:web',
        title: 'Ship web task hub',
        status: 'open',
      );

      await backend.deleteTodo(key, todoId: 'todo:web');

      final todos = await backend.listTodos(key);

      expect(todos, isEmpty);
    });

    test('supports checklist CRUD and progress on web backend', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );

      final key = Uint8List(0);
      await backend.upsertTodo(
        key,
        id: 'todo:web',
        title: 'Ship web task hub',
        status: 'open',
      );

      final first = await backend.createTodoChecklistItem(
        key,
        todoId: 'todo:web',
        content: 'First item',
      );
      final second = await backend.createTodoChecklistItem(
        key,
        todoId: 'todo:web',
        content: 'Second item',
      );

      await backend.updateTodoChecklistItemContent(
        key,
        itemId: second.id,
        content: 'Second item updated',
      );
      await backend.setTodoChecklistItemDone(
        key,
        itemId: first.id,
        isDone: true,
      );
      await backend.reorderTodoChecklistItems(
        key,
        todoId: 'todo:web',
        orderedItemIds: <String>[second.id, first.id],
      );

      final items = await backend.listTodoChecklistItems(key, 'todo:web');
      final progress = await backend.listTodoChecklistProgress(key);

      expect(items, hasLength(2));
      expect(items.first.id, second.id);
      expect(items.first.content, 'Second item updated');
      expect(items.last.isDone, isTrue);
      expect(progress, hasLength(1));
      expect(progress.single.todoId, 'todo:web');
      expect(progress.single.totalCount, 2);
      expect(progress.single.doneCount, 1);

      await backend.deleteTodoChecklistItem(
        key,
        itemId: first.id,
      );

      expect(
          await backend.listTodoChecklistItems(key, 'todo:web'), hasLength(1));
    });

    test('task hub quick actions can transition todos on web backend',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);
      final todo = await backend.upsertTodo(
        key,
        id: 'todo:web',
        title: 'Ship web task hub',
        status: 'open',
      );
      final controller = TaskHubQuickActionsController(
        backend: backend,
        sessionKey: key,
        nowLocal: () => DateTime(2026, 3, 13, 10, 0),
      );

      final ticket = await controller.apply(todo, TaskHubQuickAction.tomorrow);

      expect(ticket, isNotNull);
      final updated = (await backend.listTodos(key)).single;
      expect(updated.status, 'open');
      expect(updated.dueAtMs, isNotNull);
    });
  });
}

final class _FakeCloudWebChatClient implements CloudWebChatClient {
  _FakeCloudWebChatClient({required this.responseText});

  final String responseText;
  final List<_ChatCall> calls = <_ChatCall>[];

  @override
  Future<String> sendMessages({
    required String idToken,
    required String gatewayBaseUrl,
    required String modelName,
    required List<Map<String, String>> messages,
  }) async {
    calls.add(
      _ChatCall(
        idToken: idToken,
        gatewayBaseUrl: gatewayBaseUrl,
        modelName: modelName,
        messages: messages,
      ),
    );
    return responseText;
  }
}

final class _ChatCall {
  const _ChatCall({
    required this.idToken,
    required this.gatewayBaseUrl,
    required this.modelName,
    required this.messages,
  });

  final String idToken;
  final String gatewayBaseUrl;
  final String modelName;
  final List<Map<String, String>> messages;
}
