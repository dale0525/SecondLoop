import 'dart:convert';
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

    test('shared task priority assessments delegate to configured web closures',
        () async {
      final fetchedScopes = <String>[];
      final upsertedPayloads = <Map<String, Object?>>[];
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        fetchTaskPriorityAssessments: ({
          required idToken,
          required cacheScopeKey,
        }) async {
          fetchedScopes.add(cacheScopeKey);
          return <String, Object?>{
            'scope': cacheScopeKey,
            'entries': <Object?>[
              <String, Object?>{
                'todo_id': 'focus',
                'semantic_adjustment': 12,
                'reason': 'shared',
                'confidence': 'high',
                'request_signature': 'sig-1',
                'computed_at_ms': 1710000000000,
              },
            ],
          };
        },
        upsertTaskPriorityAssessments: ({
          required idToken,
          required payload,
        }) async {
          upsertedPayloads.add(payload);
        },
      );

      final fetched = await backend.fetchTaskPriorityAiAssessmentsCloudGateway(
        Uint8List(0),
        gatewayBaseUrl: 'https://gateway.test',
        idToken: 'token-1',
        cacheScopeKey: 'scope-1',
      );
      await backend.upsertTaskPriorityAiAssessmentsCloudGateway(
        Uint8List(0),
        gatewayBaseUrl: 'https://gateway.test',
        idToken: 'token-1',
        cacheScopeKey: 'scope-1',
        payloadJson: jsonEncode(<String, Object?>{
          'scope': 'scope-1',
          'entries': <Object?>[],
        }),
      );

      expect(fetchedScopes, <String>['scope-1']);
      expect(jsonDecode(fetched)['scope'], 'scope-1');
      expect(upsertedPayloads.single['scope'], 'scope-1');
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

    test('listTodos matches native due-date ordering', () async {
      var nowMs = 1000;
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => nowMs,
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:no-due',
        title: 'No due task',
        status: 'open',
      );
      nowMs = 1001;
      await backend.upsertTodo(
        key,
        id: 'todo:late',
        title: 'Later due task',
        dueAtMs: 5000,
        status: 'open',
      );
      nowMs = 1002;
      await backend.upsertTodo(
        key,
        id: 'todo:early-a',
        title: 'Early due task A',
        dueAtMs: 2000,
        status: 'open',
      );
      nowMs = 1003;
      await backend.upsertTodo(
        key,
        id: 'todo:early-b',
        title: 'Early due task B',
        dueAtMs: 2000,
        status: 'open',
      );

      final todos = await backend.listTodos(key);

      expect(
        todos.map((todo) => todo.id),
        const <String>[
          'todo:early-a',
          'todo:early-b',
          'todo:late',
          'todo:no-due',
        ],
      );
    });

    test('upsertTodo preserves existing manual nudge scores when omitted',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:web-nudges',
        title: 'Ship web task hub',
        status: 'open',
        manualImportanceNudgeScore: 1,
        manualUrgencyNudgeScore: -1,
      );

      final updated = await backend.upsertTodo(
        key,
        id: 'todo:web-nudges',
        title: 'Ship web task hub v2',
        status: 'open',
      );

      expect(updated.title, 'Ship web task hub v2');
      expect(updated.manualImportanceNudgeScore, 1);
      expect(updated.manualUrgencyNudgeScore, -1);
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

    test('supports todo activity note, move, and range listing on web backend',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => 1000,
      );
      final key = Uint8List(0);
      await backend.upsertTodo(
        key,
        id: 'todo:web-a',
        title: 'Task A',
        status: 'open',
      );
      await backend.upsertTodo(
        key,
        id: 'todo:web-b',
        title: 'Task B',
        status: 'open',
      );

      final activity = await backend.appendTodoNote(
        key,
        todoId: 'todo:web-a',
        content: 'Initial note',
        sourceMessageId: 'message-1',
      );

      final listedA = await backend.listTodoActivities(key, 'todo:web-a');
      expect(listedA, hasLength(1));
      expect(listedA.single.content, 'Initial note');
      expect(listedA.single.sourceMessageId, 'message-1');

      final moved = await backend.moveTodoActivity(
        key,
        activityId: activity.id,
        toTodoId: 'todo:web-b',
      );

      expect(moved.todoId, 'todo:web-b');
      expect(await backend.listTodoActivities(key, 'todo:web-a'), isEmpty);
      expect(await backend.listTodoActivities(key, 'todo:web-b'), hasLength(1));

      final ranged = await backend.listTodoActivitiesInRange(
        key,
        startAtMsInclusive: 900,
        endAtMsExclusive: 1100,
      );
      expect(ranged, hasLength(1));
      expect(ranged.single.id, activity.id);
    });

    test('appendTodoNote creates a backing message in the source conversation',
        () async {
      var nowMs = 1000;
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => nowMs,
      );
      final key = Uint8List(0);

      final conversation = await backend.createConversation(key, 'Web Chat');
      nowMs = 1001;
      final sourceMessage = await backend.insertMessage(
        key,
        conversation.id,
        role: 'user',
        content: 'Original task message',
      );
      nowMs = 1002;
      await backend.upsertTodo(
        key,
        id: 'todo:web-linked',
        title: 'Linked task',
        status: 'open',
        sourceEntryId: sourceMessage.id,
      );

      final activity = await backend.appendTodoNote(
        key,
        todoId: 'todo:web-linked',
        content: 'Follow-up note',
      );

      expect(activity.sourceMessageId, isNotNull);
      final createdMessage =
          await backend.getMessageById(key, activity.sourceMessageId!);
      expect(createdMessage, isNotNull);
      expect(createdMessage!.conversationId, conversation.id);
      expect(createdMessage.content, 'Follow-up note');
      expect(activity.createdAtMs, createdMessage.createdAtMs);
    });

    test(
        'appendTodoNote falls back to loop home when source conversation is missing',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => 2000,
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:web-loop-home',
        title: 'Loop home task',
        status: 'open',
      );

      final activity = await backend.appendTodoNote(
        key,
        todoId: 'todo:web-loop-home',
        content: 'Inbox follow-up',
      );

      final createdMessage =
          await backend.getMessageById(key, activity.sourceMessageId!);
      expect(createdMessage, isNotNull);
      expect(createdMessage!.conversationId, 'loop-home');
      expect(
        (await backend.listConversations(key)).any((c) => c.id == 'loop-home'),
        isTrue,
      );
    });

    test('moveTodoActivity allows orphan targets for detach parity', () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => 3000,
      );
      final key = Uint8List(0);
      await backend.upsertTodo(
        key,
        id: 'todo:web-a',
        title: 'Task A',
        status: 'open',
      );

      final activity = await backend.appendTodoNote(
        key,
        todoId: 'todo:web-a',
        content: 'Detached note',
        sourceMessageId: 'message-1',
      );

      final moved = await backend.moveTodoActivity(
        key,
        activityId: activity.id,
        toTodoId: 'todo:_detached_message_link:message-1',
      );

      expect(moved.todoId, 'todo:_detached_message_link:message-1');
      expect(await backend.listTodoActivities(key, 'todo:web-a'), isEmpty);
      expect(
        await backend.listTodoActivities(
          key,
          'todo:_detached_message_link:message-1',
        ),
        hasLength(1),
      );
    });

    test('records status change activities on web backend', () async {
      var nowMs = 1000;
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => nowMs,
      );
      final key = Uint8List(0);
      await backend.upsertTodo(
        key,
        id: 'todo:status',
        title: 'Status task',
        status: 'open',
      );

      nowMs = 1100;
      await backend.setTodoStatus(
        key,
        todoId: 'todo:status',
        newStatus: 'in_progress',
      );
      nowMs = 1200;
      await backend.setTodoStatus(
        key,
        todoId: 'todo:status',
        newStatus: 'done',
      );

      final activities = await backend.listTodoActivitiesInRange(
        key,
        startAtMsInclusive: 1000,
        endAtMsExclusive: 1300,
      );

      expect(activities, hasLength(2));
      expect(activities.first.activityType, 'status_change');
      expect(activities.first.fromStatus, 'open');
      expect(activities.first.toStatus, 'in_progress');
      expect(activities.last.fromStatus, 'in_progress');
      expect(activities.last.toStatus, 'done');
    });

    test('setTodoStatus mirrors native review and schedule side effects',
        () async {
      var nowMs = 1000;
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => nowMs,
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:inbox-status',
        title: 'Inbox task',
        status: 'inbox',
        reviewStage: 2,
        nextReviewAtMs: 7777,
        lastReviewAtMs: 8888,
        manualImportanceNudgeScore: 1,
        manualUrgencyNudgeScore: -1,
      );
      nowMs = 1100;

      final leftInbox = await backend.setTodoStatus(
        key,
        todoId: 'todo:inbox-status',
        newStatus: 'done',
      );

      expect(leftInbox.reviewStage, isNull);
      expect(leftInbox.nextReviewAtMs, isNull);
      expect(leftInbox.lastReviewAtMs, 1100);
      expect(leftInbox.manualImportanceNudgeScore, 1);
      expect(leftInbox.manualUrgencyNudgeScore, -1);

      await backend.upsertTodo(
        key,
        id: 'todo:auto-schedule',
        title: 'Open task',
        status: 'open',
        dueAtMs: null,
      );
      nowMs = 1200;

      final autoScheduled = await backend.setTodoStatus(
        key,
        todoId: 'todo:auto-schedule',
        newStatus: 'in_progress',
      );

      expect(autoScheduled.dueAtMs, 1200);
      expect(autoScheduled.lastReviewAtMs, 1200);
    });

    test(
        'supports activity attachments and checklist suggestions on web backend',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => 1000,
      );
      final key = Uint8List(0);
      await backend.upsertTodo(
        key,
        id: 'todo:web',
        title: 'Task with extras',
        status: 'open',
      );

      const attachment = Attachment(
        sha256: 'sha-activity',
        mimeType: 'image/png',
        path: 'vault/sha-activity.png',
        byteLen: 12,
        createdAtMs: 999,
      );
      backend.rememberAttachment(attachment);

      final activity = await backend.appendTodoNote(
        key,
        todoId: 'todo:web',
        content: 'Note with attachment',
      );
      await backend.linkAttachmentToTodoActivity(
        key,
        activityId: activity.id,
        attachmentSha256: attachment.sha256,
      );

      final linkedAttachments =
          await backend.listTodoActivityAttachments(key, activity.id);
      expect(linkedAttachments, const <Attachment>[attachment]);

      final generated = await backend.upsertGeneratedTodoChecklistSuggestions(
        key,
        todoId: 'todo:web',
        suggestions: const <String>['Draft outline', 'Review draft'],
        source: 'cloud',
        generationKey: 'gen-1',
      );
      expect(generated, hasLength(2));
      expect(generated.first.state, 'pending');

      final applied = await backend.applyTodoChecklistSuggestions(
        key,
        todoId: 'todo:web',
        suggestionIds: <String>[generated.first.id],
      );
      expect(applied, hasLength(1));
      expect(applied.single.content, 'Draft outline');

      await backend.dismissTodoChecklistSuggestions(
        key,
        todoId: 'todo:web',
        suggestionIds: <String>[generated.last.id],
      );

      final suggestions =
          await backend.listTodoChecklistSuggestions(key, 'todo:web');
      final appliedSuggestion =
          suggestions.firstWhere((item) => item.id == generated.first.id);
      final dismissedSuggestion =
          suggestions.firstWhere((item) => item.id == generated.last.id);
      expect(appliedSuggestion.state, 'applied');
      expect(appliedSuggestion.appliedChecklistItemId, applied.single.id);
      expect(dismissedSuggestion.state, 'dismissed');
      expect(dismissedSuggestion.dismissedAtMs, isNotNull);

      await backend.upsertGeneratedTodoChecklistSuggestions(
        key,
        todoId: 'todo:web',
        suggestions: const <String>['Ship it'],
        source: 'cloud',
        generationKey: 'gen-2',
      );
      await backend.dismissAllTodoChecklistSuggestions(
        key,
        todoId: 'todo:web',
      );
      final afterDismissAll =
          await backend.listTodoChecklistSuggestions(key, 'todo:web');
      expect(
        afterDismissAll.where((item) => item.state == 'pending'),
        isEmpty,
      );
    });

    test(
        'supports created-range queries, scoped updates, and recurrence on web backend',
        () async {
      var nowMs = 1000;
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => nowMs,
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:early',
        title: 'Early task',
        status: 'open',
      );
      nowMs = 2000;
      await backend.upsertTodo(
        key,
        id: 'todo:late',
        title: 'Late task',
        status: 'open',
      );

      final ranged = await backend.listTodosCreatedInRange(
        key,
        startAtMsInclusive: 1500,
        endAtMsExclusive: 2500,
      );
      expect(ranged.map((todo) => todo.id), const <String>['todo:late']);

      final statusUpdated = await backend.updateTodoStatusWithScope(
        key,
        todoId: 'todo:late',
        newStatus: 'done',
        scope: TodoRecurrenceEditScope.thisOnly,
      );
      expect(statusUpdated.status, 'done');

      final dueUpdated = await backend.updateTodoDueWithScope(
        key,
        todoId: 'todo:late',
        dueAtMs: 3000,
        scope: TodoRecurrenceEditScope.thisOnly,
      );
      expect(dueUpdated.dueAtMs, 3000);

      await backend.upsertTodoRecurrence(
        key,
        todoId: 'todo:late',
        seriesId: 'series-1',
        ruleJson: '{"freq":"weekly"}',
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:late'),
        '{"freq":"weekly"}',
      );

      await backend.updateTodoRecurrenceRuleWithScope(
        key,
        todoId: 'todo:late',
        ruleJson: '{"freq":"daily"}',
        scope: TodoRecurrenceEditScope.wholeSeries,
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:late'),
        '{"freq":"daily"}',
      );
    });

    test('scoped due and status updates mirror native recurrence semantics',
        () async {
      var nowMs = 1000;
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
        nowMs: () => nowMs,
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:series-a',
        title: 'Scoped task A',
        dueAtMs: 1000,
        status: 'open',
      );
      nowMs = 1001;
      await backend.upsertTodo(
        key,
        id: 'todo:series-b',
        title: 'Scoped task B',
        dueAtMs: 2000,
        status: 'open',
      );
      nowMs = 1002;
      await backend.upsertTodo(
        key,
        id: 'todo:series-c',
        title: 'Scoped task C',
        dueAtMs: 3000,
        status: 'open',
      );

      await backend.upsertTodoRecurrence(
        key,
        todoId: 'todo:series-a',
        seriesId: 'series-1',
        ruleJson: '{"freq":"weekly"}',
      );
      await backend.upsertTodoRecurrence(
        key,
        todoId: 'todo:series-b',
        seriesId: 'series-1',
        ruleJson: '{"freq":"weekly"}',
      );
      await backend.upsertTodoRecurrence(
        key,
        todoId: 'todo:series-c',
        seriesId: 'series-1',
        ruleJson: '{"freq":"weekly"}',
      );

      final dueUpdated = await backend.updateTodoDueWithScope(
        key,
        todoId: 'todo:series-b',
        dueAtMs: 2500,
        scope: TodoRecurrenceEditScope.thisAndFuture,
      );
      expect(dueUpdated.dueAtMs, 2500);

      nowMs = 1003;
      final statusUpdated = await backend.updateTodoStatusWithScope(
        key,
        todoId: 'todo:series-b',
        newStatus: 'in_progress',
        scope: TodoRecurrenceEditScope.wholeSeries,
      );
      expect(statusUpdated.status, 'in_progress');

      final todos = await backend.listTodos(key);
      final byId = <String, Todo>{for (final todo in todos) todo.id: todo};
      expect(byId['todo:series-a']!.dueAtMs, 1000);
      expect(byId['todo:series-a']!.status, 'open');
      expect(byId['todo:series-b']!.dueAtMs, 2500);
      expect(byId['todo:series-b']!.status, 'in_progress');
      expect(byId['todo:series-c']!.dueAtMs, 3500);
      expect(byId['todo:series-c']!.status, 'in_progress');
    });

    test('scoped recurrence rule updates honor wholeSeries and thisAndFuture',
        () async {
      final backend = CloudWebBackend(
        chatClient: _FakeCloudWebChatClient(responseText: 'ok'),
      );
      final key = Uint8List(0);

      await backend.upsertTodo(
        key,
        id: 'todo:rule-a',
        title: 'Rule task A',
        dueAtMs: 1000,
        status: 'open',
      );
      await backend.upsertTodo(
        key,
        id: 'todo:rule-b',
        title: 'Rule task B',
        dueAtMs: 2000,
        status: 'open',
      );
      await backend.upsertTodo(
        key,
        id: 'todo:rule-c',
        title: 'Rule task C',
        dueAtMs: 3000,
        status: 'open',
      );

      for (final todoId in const <String>[
        'todo:rule-a',
        'todo:rule-b',
        'todo:rule-c',
      ]) {
        await backend.upsertTodoRecurrence(
          key,
          todoId: todoId,
          seriesId: 'series-rules',
          ruleJson: '{"freq":"weekly"}',
        );
      }

      await backend.updateTodoRecurrenceRuleWithScope(
        key,
        todoId: 'todo:rule-b',
        ruleJson: '{"freq":"daily"}',
        scope: TodoRecurrenceEditScope.wholeSeries,
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:rule-a'),
        '{"freq":"daily"}',
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:rule-c'),
        '{"freq":"daily"}',
      );

      await backend.updateTodoRecurrenceRuleWithScope(
        key,
        todoId: 'todo:rule-b',
        ruleJson: '{"freq":"monthly"}',
        scope: TodoRecurrenceEditScope.thisAndFuture,
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:rule-a'),
        '{"freq":"daily"}',
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:rule-b'),
        '{"freq":"monthly"}',
      );
      expect(
        await backend.getTodoRecurrenceRuleJson(key, todoId: 'todo:rule-c'),
        '{"freq":"monthly"}',
      );
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
