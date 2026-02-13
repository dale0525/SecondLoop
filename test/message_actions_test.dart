import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/src/rust/db.dart';

import 'message_actions_test_helpers.dart';
import 'noop_sync_runner.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Long press message -> delete removes it', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('message_action_delete')));
    await tester.pumpAndSettle();
    await confirmChatMessageDelete(tester);

    expect(find.text('hello'), findsNothing);
    expect(backend.deletedMessageIds, contains('m1'));
  });

  testWidgets('Deleting a todo-linked message deletes the todo',
      (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_delete')));
    await tester.pumpAndSettle();
    await confirmChatTodoDelete(tester);

    expect(find.text('hello'), findsNothing);
    expect(backend.deletedTodoIds, contains('t1'));
  });

  testWidgets('Long press message -> edit updates content', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_edit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('edit_message_save')),
        matching: find.byIcon(Icons.save_rounded),
      ),
      findsOneWidget,
    );
    await tester.enterText(
        find.byKey(const ValueKey('edit_message_content')), 'updated');
    await tester.tap(find.byKey(const ValueKey('edit_message_save')));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsNothing);
    expect(find.text('updated'), findsOneWidget);
    expect(backend.editedMessageIds, contains('m1'));
  });

  testWidgets('Hover message shows menu button and opens actions',
      (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_edit_m1')), findsNothing);
    expect(find.byKey(const ValueKey('message_delete_m1')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('hello')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_edit_m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_delete_m1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message_delete_m1')));
    await tester.pumpAndSettle();
    await confirmChatMessageDelete(tester);

    expect(find.text('hello'), findsNothing);
    expect(backend.deletedMessageIds, contains('m1'));
  });

  testWidgets('Hover message does not overflow on narrow width',
      (tester) async {
    tester.view
      ..physicalSize = const Size(640, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('hello')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('message_edit_m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_delete_m1')), findsOneWidget);
  });

  testWidgets('Right click message opens menu and copies text', (tester) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final pos = tester.getCenter(find.text('hello'));
    final gesture = await tester.startGesture(
      pos,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_context_copy')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message_context_copy')));
    await tester.pumpAndSettle();

    expect(clipboardText, 'hello');
  });

  testWidgets('Right click message menu can convert to todo (desktop)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final pos = tester.getCenter(find.text('hello'));
    final gesture = await tester.startGesture(
      pos,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_context_convert_todo')),
        findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('message_context_convert_todo')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('message_convert_todo_due_picker_m1')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(backend.upsertedTodos.map((t) => t.id), contains('todo:m1'));
    final created = backend.upsertedTodos.firstWhere((t) => t.id == 'todo:m1');
    expect(created.dueAtMs, isNotNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Long press message menu can convert to todo', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_action_convert_todo')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message_action_convert_todo')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('message_convert_todo_due_picker_m1')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(backend.upsertedTodos.map((t) => t.id), contains('todo:m1'));
    final created = backend.upsertedTodos.firstWhere((t) => t.id == 'todo:m1');
    expect(created.dueAtMs, isNotNull);
  });

  testWidgets('Converting message to todo notifies sync engine',
      (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );
    final engine = SyncEngine(
      syncRunner: NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var changes = 0;
    engine.changes.addListener(() => changes += 1);

    await tester
        .pumpWidget(wrapChatForTests(backend: backend, syncEngine: engine));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('message_action_convert_todo')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('message_convert_todo_due_picker_m1')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(backend.upsertedTodos.map((t) => t.id), contains('todo:m1'));
    expect(changes, 1);
  });

  testWidgets('Photo placeholder message hides convert-to-todo action',
      (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'Photo',
          createdAtMs: 1,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('message_bubble_m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_action_convert_todo')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('message_action_link_todo')), findsOneWidget);
  });

  testWidgets('Photo placeholder message hides convert-to-todo context menu',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'Photo',
          createdAtMs: 1,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    final pos =
        tester.getCenter(find.byKey(const ValueKey('message_bubble_m1')));
    final gesture = await tester.startGesture(
      pos,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_context_copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_context_convert_todo')),
        findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Message already linked to todo shows Jump to todo',
      (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_action_convert_todo')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('message_action_open_todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_action_convert_to_info')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('message_action_link_todo')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('message_action_open_todo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_detail_header')), findsOneWidget);
  });

  testWidgets('Can convert linked todo back to info', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('message_action_convert_to_info')));
    await tester.pumpAndSettle();

    expect(find.text('Convert to note?'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final updated = backend.upsertedTodos.firstWhere((t) => t.id == 't1');
    expect(updated.status, 'dismissed');
    expect(updated.sourceEntryId, isNull);

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_action_convert_todo')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('message_action_open_todo')), findsNothing);
  });

  testWidgets('Linked note message shows Link to another task', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm2',
          conversationId: 'main_stream',
          role: 'user',
          content: 'note',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
      todos: const [
        Todo(
          id: 't1',
          title: 'Task',
          status: 'open',
          sourceEntryId: 'm1',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
      activities: const [
        TodoActivity(
          id: 'a1',
          todoId: 't1',
          activityType: 'note',
          sourceMessageId: 'm2',
          createdAtMs: 0,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('note'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_action_convert_todo')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('message_action_open_todo')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('message_action_link_todo')), findsOneWidget);
    expect(find.text('Link to another task'), findsOneWidget);
  });

  testWidgets('AI messages are not editable', (tester) async {
    final backend = MessageActionsBackend(
      messages: [
        const Message(
          id: 'm2',
          conversationId: 'main_stream',
          role: 'assistant',
          content: 'ai',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(wrapChatForTests(backend: backend));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('ai'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_action_edit')), findsNothing);
    expect(find.byKey(const ValueKey('message_action_delete')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message_action_delete')));
    await tester.pumpAndSettle();
    await confirmChatMessageDelete(tester);
    expect(find.text('ai'), findsNothing);
    expect(backend.deletedMessageIds, contains('m2'));
  });
}

class MessageActionsBackend extends AppBackend {
  MessageActionsBackend({
    required List<Message> messages,
    List<Todo>? todos,
    List<TodoActivity>? activities,
  })  : _messages = List<Message>.from(messages),
        _todos = List<Todo>.from(todos ?? const <Todo>[]),
        _activities =
            List<TodoActivity>.from(activities ?? const <TodoActivity>[]);

  final List<Message> _messages;
  final List<Todo> _todos;
  final List<TodoActivity> _activities;

  final List<String> editedMessageIds = [];
  final List<String> deletedMessageIds = [];
  final List<String> deletedTodoIds = [];
  final List<Todo> upsertedTodos = [];

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
      List<Message>.from(_messages);

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
      Uint8List key, String messageId, String content) async {
    editedMessageIds.add(messageId);
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].id == messageId) {
        _messages[i] = Message(
          id: _messages[i].id,
          conversationId: _messages[i].conversationId,
          role: _messages[i].role,
          content: content,
          createdAtMs: _messages[i].createdAtMs,
          isMemory: _messages[i].isMemory,
        );
        break;
      }
    }
  }

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {
    deletedMessageIds.add(messageId);
    _messages.removeWhere((m) => m.id == messageId);
  }

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    deletedTodoIds.add(todoId);

    final todoIndex = _todos.indexWhere((t) => t.id == todoId);
    final sourceEntryId = todoIndex >= 0 ? _todos[todoIndex].sourceEntryId : '';
    _todos.removeWhere((t) => t.id == todoId);
    _activities.removeWhere((a) => a.todoId == todoId);

    _messages.removeWhere((m) => m.id == sourceEntryId);
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<List<Todo>> listTodos(Uint8List key) async => List<Todo>.from(_todos);

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    final todo = Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: 0,
      updatedAtMs: 0,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );
    _todos.removeWhere((t) => t.id == id);
    _todos.add(todo);
    upsertedTodos.add(todo);
    return todo;
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async =>
      List<TodoActivity>.from(_activities);

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
      const <String>['secondloop-default-embed-v0'];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(modelName != 'secondloop-default-embed-v0');

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
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;
}
