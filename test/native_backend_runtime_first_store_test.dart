import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('native backend default session, messages, and todos use Dart store',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-store-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-store-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    expect(sessionKey, hasLength(32));
    expect(await backend.isMasterPasswordSet(), isTrue);

    final conversation = await backend.getOrCreateLoopHomeConversation(
      sessionKey,
    );
    expect(conversation.id, 'loop_home');

    final userMessage = await backend.insertMessage(
      sessionKey,
      conversation.id,
      role: 'user',
      content: 'hello runtime',
    );
    final assistantMessage = await backend.insertAssistantMessageWithCitations(
      sessionKey,
      conversation.id,
      content: 'hello back',
      citationsJson: '{"direct_sources":[]}',
    );

    final messages = await backend.listMessages(sessionKey, conversation.id);
    expect(messages.map((message) => message.id), [
      userMessage.id,
      assistantMessage.id,
    ]);
    expect(
      (await backend.getMessageById(sessionKey, assistantMessage.id))
          ?.citationsJson,
      '{"direct_sources":[]}',
    );

    final todo = await backend.upsertTodo(
      sessionKey,
      id: 'task-1',
      title: 'Write weekly report',
      dueAtMs: 1780156800000,
      status: 'open',
      sourceEntryId: userMessage.id,
    );
    expect(todo.title, 'Write weekly report');

    final transitioned = await backend.transitionTodo(
      sessionKey,
      todoId: todo.id,
      newStatus: 'done',
      clearDueAtMs: true,
    );
    expect(transitioned.status, 'done');
    expect(transitioned.dueAtMs, isNull);

    final listed = await backend.listTodos(sessionKey);
    expect(listed.single.id, 'task-1');
    expect(
        platformIntToInt(listed.single.updatedAtMs),
        greaterThanOrEqualTo(
          platformIntToInt(listed.single.createdAtMs),
        ));
  });

  test('native backend default semantic todo create does not call runtime job',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-semantic-todo-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-semantic-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    final todo = await backend.upsertTodoFromSemanticCreate(
      sessionKey,
      id: 'research-task',
      title: 'Research current LLM options',
      status: 'open',
      followupTaskTypeHint: 'research',
    );

    expect(todo.id, 'research-task');
    expect(await backend.getTodoById(sessionKey, todo.id), todo);
  });

  test('native backend default checklist items and suggestions use Dart store',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-checklist-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-checklist-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    await backend.upsertTodo(
      sessionKey,
      id: 'task-with-checklist',
      title: 'Prepare release',
      status: 'open',
    );

    final first = await backend.createTodoChecklistItem(
      sessionKey,
      todoId: 'task-with-checklist',
      content: 'Draft release notes',
    );
    final second = await backend.createTodoChecklistItem(
      sessionKey,
      todoId: 'task-with-checklist',
      content: 'Run smoke tests',
    );

    final updated = await backend.updateTodoChecklistItemContent(
      sessionKey,
      itemId: first.id,
      content: 'Draft final release notes',
    );
    expect(updated.content, 'Draft final release notes');

    final done = await backend.setTodoChecklistItemDone(
      sessionKey,
      itemId: first.id,
      isDone: true,
    );
    expect(done.isDone, isTrue);

    await backend.reorderTodoChecklistItems(
      sessionKey,
      todoId: 'task-with-checklist',
      orderedItemIds: [second.id, first.id],
    );
    expect(
      (await backend.listTodoChecklistItems(
        sessionKey,
        'task-with-checklist',
      ))
          .map((item) => item.id),
      [second.id, first.id],
    );

    expect(
      await backend.listTodoChecklistProgress(sessionKey),
      const [
        TodoChecklistProgress(
          todoId: 'task-with-checklist',
          doneCount: 1,
          totalCount: 2,
        ),
      ],
    );

    final suggestions = await backend.upsertGeneratedTodoChecklistSuggestions(
      sessionKey,
      todoId: 'task-with-checklist',
      suggestions: const ['Notify stakeholders', 'Archive notes'],
      source: 'runtime',
      generationKey: 'checklist-gen-1',
    );
    expect(suggestions.map((suggestion) => suggestion.state), [
      'pending',
      'pending',
    ]);

    final applied = await backend.applyTodoChecklistSuggestions(
      sessionKey,
      todoId: 'task-with-checklist',
      suggestionIds: [suggestions.first.id],
    );
    expect(applied.single.content, 'Notify stakeholders');
    expect(
      (await backend.listTodoChecklistSuggestions(
        sessionKey,
        'task-with-checklist',
      ))
          .first
          .state,
      'applied',
    );

    await backend.dismissTodoChecklistSuggestions(
      sessionKey,
      todoId: 'task-with-checklist',
      suggestionIds: [suggestions.last.id],
    );
    expect(
      (await backend.listTodoChecklistSuggestions(
        sessionKey,
        'task-with-checklist',
      ))
          .last
          .state,
      'dismissed',
    );

    await backend.deleteTodoChecklistItem(sessionKey, itemId: second.id);
    expect(
      (await backend.listTodoChecklistItems(
        sessionKey,
        'task-with-checklist',
      ))
          .map((item) => item.content),
      ['Draft final release notes', 'Notify stakeholders'],
    );
  });

  test('native backend default follow-up suggestions use Dart store', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-followups-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-followups-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    await backend.upsertTodo(
      sessionKey,
      id: 'task-with-followups',
      title: 'Research model pricing',
      status: 'open',
    );

    final suggestions = await backend.upsertGeneratedTodoFollowupSuggestions(
      sessionKey,
      todoId: 'task-with-followups',
      suggestions: const [
        TodoFollowupSuggestionDraftInput(
          content: 'Check current public pricing pages.',
          generationMode: 'web_search',
          citationsJson: '{"direct_sources":[]}',
        ),
        TodoFollowupSuggestionDraftInput(
          content: 'Compare rate limits.',
          generationMode: 'model_knowledge',
        ),
      ],
      source: 'runtime',
      generationKey: 'followup-gen-1',
    );
    expect(suggestions.map((suggestion) => suggestion.state), [
      'pending',
      'pending',
    ]);

    final activities = await backend.applyTodoFollowupSuggestions(
      sessionKey,
      todoId: 'task-with-followups',
      suggestionIds: [suggestions.first.id],
    );
    expect(activities.single.activityType, 'followup_information');
    expect(activities.single.content, 'Check current public pricing pages.');

    final listedAfterApply = await backend.listTodoFollowupSuggestions(
      sessionKey,
      'task-with-followups',
    );
    expect(listedAfterApply.first.state, 'applied');
    expect(listedAfterApply.first.appliedActivityId, activities.single.id);

    await backend.dismissTodoFollowupSuggestions(
      sessionKey,
      todoId: 'task-with-followups',
      suggestionIds: [suggestions.last.id],
    );
    expect(
      (await backend.listTodoFollowupSuggestions(
        sessionKey,
        'task-with-followups',
      ))
          .last
          .state,
      'dismissed',
    );

    final acceptedClaim =
        await backend.upsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
      sessionKey,
      todoId: 'task-with-followups',
      jobStartedAtMs: 123,
      suggestions: const [
        TodoFollowupSuggestionDraftInput(
          content: 'Check vendor changelogs.',
          generationMode: 'web_search',
        ),
      ],
      source: 'runtime',
      generationKey: 'followup-gen-2',
    );
    expect(acceptedClaim, isTrue);
    expect(
      (await backend.listTodoFollowupSuggestions(
        sessionKey,
        'task-with-followups',
      ))
          .last
          .content,
      'Check vendor changelogs.',
    );
  });

  test('native backend default todo scopes and activities use Dart store',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-todo-actions-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-todo-actions-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    await backend.upsertTodo(
      sessionKey,
      id: 'task-with-activity',
      title: 'Prepare launch notes',
      status: 'open',
    );

    await backend.updateTodoDueWithScope(
      sessionKey,
      todoId: 'task-with-activity',
      dueAtMs: 1780156800000,
      scope: TodoRecurrenceEditScope.thisOnly,
    );
    expect(
      (await backend.getTodoById(sessionKey, 'task-with-activity'))?.dueAtMs,
      1780156800000,
    );

    await backend.updateTodoStatusWithScope(
      sessionKey,
      todoId: 'task-with-activity',
      newStatus: 'done',
      sourceMessageId: 'message-1',
      scope: TodoRecurrenceEditScope.wholeSeries,
    );
    expect(
      (await backend.getTodoById(sessionKey, 'task-with-activity'))?.status,
      'done',
    );

    await backend.upsertTodoRecurrence(
      sessionKey,
      todoId: 'task-with-activity',
      seriesId: 'series-1',
      ruleJson: '{"freq":"weekly"}',
    );
    expect(
      await backend.getTodoRecurrenceRuleJson(
        sessionKey,
        todoId: 'task-with-activity',
      ),
      '{"freq":"weekly"}',
    );
    await backend.updateTodoRecurrenceRuleWithScope(
      sessionKey,
      todoId: 'task-with-activity',
      ruleJson: '{"freq":"monthly"}',
      scope: TodoRecurrenceEditScope.thisAndFuture,
    );
    expect(
      await backend.getTodoRecurrenceRuleJson(
        sessionKey,
        todoId: 'task-with-activity',
      ),
      '{"freq":"monthly"}',
    );

    final activity = await backend.appendTodoNote(
      sessionKey,
      todoId: 'task-with-activity',
      content: 'Waiting on QA sign-off.',
      sourceMessageId: 'message-2',
    );
    expect(activity.activityType, 'note');
    expect(activity.content, 'Waiting on QA sign-off.');

    await backend.upsertTodo(
      sessionKey,
      id: 'task-target',
      title: 'Target task',
      status: 'open',
    );
    final moved = await backend.moveTodoActivity(
      sessionKey,
      activityId: activity.id,
      toTodoId: 'task-target',
    );
    expect(moved.todoId, 'task-target');

    expect(
      (await backend.listTodoActivities(sessionKey, 'task-target'))
          .map((item) => item.id),
      [activity.id],
    );
    expect(
      (await backend.listTodoActivitiesInRange(
        sessionKey,
        startAtMsInclusive: 0,
        endAtMsExclusive: DateTime.now().millisecondsSinceEpoch + 1000,
      ))
          .map((item) => item.id),
      contains(activity.id),
    );

    await backend.linkAttachmentToTodoActivity(
      sessionKey,
      activityId: activity.id,
      attachmentSha256: 'sha-activity-1',
    );
    expect(
      (await backend.listTodoActivityAttachments(sessionKey, activity.id))
          .single
          .sha256,
      'sha-activity-1',
    );

    await backend.deleteTodo(sessionKey, todoId: 'task-target');
    expect(await backend.getTodoById(sessionKey, 'task-target'), isNull);
    expect(
      await backend.listTodoActivities(sessionKey, 'task-target'),
      isEmpty,
    );
  });

  test('native backend default attachment IO uses Dart store', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-attachments-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-attachments-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    final conversation =
        await backend.getOrCreateLoopHomeConversation(sessionKey);
    final message = await backend.insertMessage(
      sessionKey,
      conversation.id,
      role: 'user',
      content: 'see attachment',
    );

    final attachment = await backend.insertAttachment(
      sessionKey,
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'image/png',
    );
    expect(attachment.sha256, isNotEmpty);
    expect(
      await backend.readAttachmentBytes(
        sessionKey,
        sha256: attachment.sha256,
      ),
      [1, 2, 3, 4],
    );
    expect(
      (await backend.readAttachmentBySha256(attachment.sha256))?.mimeType,
      'image/png',
    );

    await backend.linkAttachmentToMessage(
      sessionKey,
      message.id,
      attachmentSha256: attachment.sha256,
    );
    expect(
      (await backend.listMessageAttachments(sessionKey, message.id))
          .map((item) => item.sha256),
      [attachment.sha256],
    );
    expect(
      (await backend.listRecentAttachments(sessionKey)).single.sha256,
      attachment.sha256,
    );

    await backend.upsertAttachmentExifMetadata(
      sessionKey,
      sha256: attachment.sha256,
      capturedAtMs: 1780156800000,
      latitude: 1.25,
      longitude: 2.5,
    );
    final exif = await backend.readAttachmentExifMetadata(
      sessionKey,
      sha256: attachment.sha256,
    );
    expect(exif?.capturedAtMs, platformIntFromInt(1780156800000));
    expect(exif?.latitude, 1.25);

    await backend.markAttachmentAnnotationOkJson(
      sessionKey,
      attachmentSha256: attachment.sha256,
      lang: 'en',
      modelName: 'manual',
      payloadJson: '{"caption_long":"A tiny image"}',
      nowMs: 1780156800001,
    );
    expect(
      await backend.readAttachmentAnnotationPayloadJson(
        sessionKey,
        sha256: attachment.sha256,
      ),
      '{"caption_long":"A tiny image"}',
    );
    expect(
      await backend.readAttachmentAnnotationCaptionLong(
        sessionKey,
        sha256: attachment.sha256,
      ),
      'A tiny image',
    );

    await backend.editMessage(sessionKey, message.id, 'updated');
    expect(
      (await backend.getMessageById(sessionKey, message.id))?.content,
      'updated',
    );
    await backend.purgeMessageAttachments(sessionKey, message.id);
    expect(
        await backend.listMessageAttachments(sessionKey, message.id), isEmpty);
    await backend.clearLocalAttachmentCache(sessionKey);
    await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
    expect(await backend.listRecentAttachments(sessionKey), isEmpty);
  });

  test('native backend default event and profile methods use Dart store',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop-native-runtime-first-profiles-',
    );
    addTearDown(() async {
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    });

    final backend = NativeAppBackend(
      appDirProvider: () async => appDir.path,
      storageScope: 'runtime-first-profiles-${appDir.path.hashCode}',
    );

    final sessionKey = await backend.ensureSessionKey();
    final event = await backend.upsertEvent(
      sessionKey,
      id: 'event-1',
      title: 'Launch review',
      startAtMs: 1780156800000,
      endAtMs: 1780160400000,
      tz: 'Asia/Shanghai',
    );
    expect(event.title, 'Launch review');
    expect((await backend.listEvents(sessionKey)).single.id, 'event-1');
    expect((await backend.getEventById(sessionKey, 'event-1'))?.tz,
        'Asia/Shanghai');

    expect(await backend.processPendingMessageEmbeddings(sessionKey), 0);
    expect(await backend.processPendingTodoThreadEmbeddings(sessionKey), 0);
    expect(
      await backend.processPendingTodoThreadEmbeddingsCloudGateway(
        sessionKey,
        gatewayBaseUrl: 'https://runtime.example',
        idToken: 'token',
        modelName: 'embedding-model',
      ),
      0,
    );
    expect(await backend.processPendingTodoThreadEmbeddingsBrok(sessionKey), 0);
    expect(await backend.searchSimilarMessages(sessionKey, 'launch'), isEmpty);
    expect(
      await backend.searchSimilarTodoThreads(sessionKey, 'launch'),
      isEmpty,
    );
    expect(await backend.rebuildMessageEmbeddings(sessionKey), 0);
    expect(await backend.releaseLocalEmbeddingModelIfIdle(sessionKey), isFalse);

    expect(await backend.listEmbeddingModelNames(sessionKey), isEmpty);
    expect(await backend.getActiveEmbeddingModelName(sessionKey), '');
    expect(
      await backend.setActiveEmbeddingModelName(sessionKey, 'embed-small'),
      isTrue,
    );
    expect(
        await backend.getActiveEmbeddingModelName(sessionKey), 'embed-small');

    final embeddingProfile = await backend.createEmbeddingProfile(
      sessionKey,
      name: 'Embeddings',
      providerType: 'openai-compatible',
      baseUrl: 'https://api.example',
      apiKey: 'secret',
      modelName: 'text-embedding',
    );
    expect(embeddingProfile.isActive, isTrue);
    await backend.setActiveEmbeddingProfile(sessionKey, embeddingProfile.id);
    expect((await backend.listEmbeddingProfiles(sessionKey)).single.id,
        embeddingProfile.id);
    await backend.deleteEmbeddingProfile(sessionKey, embeddingProfile.id);
    expect(await backend.listEmbeddingProfiles(sessionKey), isEmpty);

    final llmProfile = await backend.createLlmProfile(
      sessionKey,
      name: 'Chat',
      providerType: 'openai-compatible',
      baseUrl: 'https://api.example',
      apiKey: 'secret',
      modelName: 'chat-model',
    );
    expect(llmProfile.isActive, isTrue);
    await backend.setActiveLlmProfile(sessionKey, llmProfile.id);
    expect(
        (await backend.listLlmProfiles(sessionKey)).single.id, llmProfile.id);
    expect(
      await backend.sumLlmUsageDailyByPurpose(
        sessionKey,
        llmProfile.id,
        startDay: '2026-05-01',
        endDay: '2026-05-31',
      ),
      isEmpty,
    );
    await backend.deleteLlmProfile(sessionKey, llmProfile.id);
    expect(await backend.listLlmProfiles(sessionKey), isEmpty);
  });

  test('native backend runtime-first primitives do not call rust_core', () {
    final nativeBackend =
        File('lib/core/backend/native_backend.dart').readAsStringSync();
    final nativeTodos =
        File('lib/core/backend/native_backend_todos.dart').readAsStringSync();
    final nativeAttachments =
        File('lib/core/backend/native_backend_attachment_io.dart')
            .readAsStringSync();
    final nativeAttachmentJobs =
        File('lib/core/backend/native_backend_attachment_annotation_jobs.dart')
            .readAsStringSync();
    final nativeTodoFollowups =
        File('lib/core/backend/native_backend_todo_followups.dart')
            .readAsStringSync();
    final nativeEmbeddings =
        File('lib/core/backend/native_backend_embeddings.dart')
            .readAsStringSync();

    for (final token in [
      'rust_core.authIsInitialized',
      'rust_core.authInitMasterPassword',
      'rust_core.authInitMasterPasswordWithExistingKey',
      'rust_core.authUnlockWithPassword',
      'rust_core.authValidateKey',
      'rust_core.dbCreateConversation',
      'rust_core.dbGetMessageById',
      'rust_core.dbGetOrCreateLoopHomeConversation',
      'rust_core.dbInsertMessage',
      'rust_core.dbListConversations',
      'rust_core.dbListMessages',
      'rust_core.dbListMessagesPage',
    ]) {
      expect(nativeBackend, isNot(contains(token)), reason: token);
    }

    for (final token in [
      'rust_core.dbListTodos',
      'rust_core.dbGetTodoById',
      'rust_core.dbUpsertTodo;',
      'rust_core.dbUpsertTodoWithAutoFollowupJob',
      'rust_core.dbEnqueueTodoFollowupGenerationJob',
      'rust_core.dbListTodosCreatedInRange',
      'rust_core.dbSetTodoStatus',
      'rust_core.dbTransitionTodo',
      'rust_core.dbUpdateTodoStatusWithScope',
      'rust_core.dbUpdateTodoDueWithScope',
      'rust_core.dbUpsertTodoRecurrence',
      'rust_core.dbGetTodoRecurrenceRuleJson',
      'rust_core.dbUpdateTodoRecurrenceRuleWithScope',
      'rust_core.dbDeleteTodoAndAssociatedMessages',
      'rust_core.dbAppendTodoNote',
      'rust_core.dbMoveTodoActivity',
      'rust_core.dbListTodoActivities',
      'rust_core.dbListTodoActivitiesInRange',
      'rust_core.dbLinkAttachmentToTodoActivity',
      'rust_core.dbListTodoActivityAttachments',
    ]) {
      expect(nativeTodos, isNot(contains(token)), reason: token);
      expect(nativeBackend, isNot(contains(token)), reason: token);
      expect(nativeTodoFollowups, isNot(contains(token)), reason: token);
    }

    for (final token in [
      'rust_core.dbCreateTodoChecklistItem',
      'rust_core.dbListTodoChecklistItems',
      'rust_core.dbUpdateTodoChecklistItemContent',
      'rust_core.dbSetTodoChecklistItemDone',
      'rust_core.dbDeleteTodoChecklistItem',
      'rust_core.dbReorderTodoChecklistItems',
      'rust_core.dbListTodoChecklistProgress',
      'rust_core.dbListTodoChecklistSuggestions',
      'rust_core.dbUpsertGeneratedTodoChecklistSuggestions',
      'rust_core.dbApplyTodoChecklistSuggestions',
      'rust_core.dbDismissTodoChecklistSuggestions',
      'rust_core.dbDismissAllTodoChecklistSuggestions',
    ]) {
      expect(nativeBackend, isNot(contains(token)), reason: token);
    }

    for (final token in [
      'rust_core.dbListTodoFollowupSuggestions',
      'rust_core.dbUpsertGeneratedTodoFollowupSuggestions',
      'rust_core.dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim',
      'rust_core.dbApplyTodoFollowupSuggestions',
      'rust_core.dbDismissTodoFollowupSuggestions',
      'rust_core.dbDismissAllTodoFollowupSuggestions',
    ]) {
      expect(nativeBackend, isNot(contains(token)), reason: token);
    }

    for (final token in [
      'rust_core.dbInsertAttachment',
      'rust_core.dbUpsertAttachmentDerivation',
      'rust_core.dbListRecentAttachments',
      'rust_core.dbLinkAttachmentToMessage',
      'rust_core.dbListMessageAttachments',
      'rust_core.dbReadAttachmentBytes',
      'rust_core.dbUpsertAttachmentExifMetadata',
      'rust_core.dbReadAttachmentExifMetadata',
      'rust_core.dbReadAttachmentPlaceDisplayName',
      'rust_core.dbReadAttachmentAnnotationCaptionLong',
      'rust_content_extract.dbReadAttachmentAnnotationPayloadJson',
      'rust_core.dbEditMessage',
      'rust_core.dbSetMessageDeleted',
      'rust_core.dbPurgeMessageAttachments',
      'rust_core.dbResetVaultDataPreservingLlmProfiles',
      'rust_core.dbClearLocalAttachmentCache',
      'rust_attachments.dbReadAttachmentBySha256',
    ]) {
      expect(nativeAttachments, isNot(contains(token)), reason: token);
      expect(nativeBackend, isNot(contains(token)), reason: token);
    }

    for (final token in [
      'rust_core.dbEnqueueAttachmentPlace',
      'rust_core.dbEnqueueAttachmentAnnotation',
      'rust_core.dbListDueAttachmentPlaces',
      'rust_core.dbListDueAttachmentAnnotations',
      'rust_content_extract.dbListDueImageAttachmentAnnotations',
      'rust_content_extract.dbListDueUrlManifestAttachmentAnnotations',
      'rust_content_extract.dbProcessPendingDocumentExtractions',
      'rust_core.dbMarkAttachmentPlaceFailed',
      'rust_core.dbMarkAttachmentAnnotationFailed',
      'rust_core.dbMarkAttachmentPlaceOkJson',
      'rust_core.dbMarkAttachmentAnnotationOkJson',
    ]) {
      expect(nativeAttachmentJobs, isNot(contains(token)), reason: token);
    }

    for (final token in [
      'rust_core.dbListEvents',
      'rust_core.dbGetEventById',
      'rust_core.dbUpsertEvent',
      'rust_core.dbProcessPendingMessageEmbeddings',
      'rust_embedding_lifecycle.dbReleaseLocalEmbeddingModelIfIdle',
      'rust_core.dbProcessPendingTodoThreadEmbeddings',
      'rust_core.dbProcessPendingTodoThreadEmbeddingsCloudGateway',
      'rust_core.dbProcessPendingTodoThreadEmbeddingsBrok',
      'rust_core.dbSearchSimilarMessages',
      'rust_core.dbSearchSimilarMessagesCloudGateway',
      'rust_core.dbSearchSimilarMessagesBrok',
      'rust_core.dbSearchSimilarTodoThreads',
      'rust_core.dbSearchSimilarTodoThreadsCloudGateway',
      'rust_core.dbSearchSimilarTodoThreadsBrok',
      'rust_core.dbRebuildMessageEmbeddings',
      'rust_core.dbListEmbeddingModelNames',
      'rust_core.dbGetActiveEmbeddingModelName',
      'rust_core.dbSetActiveEmbeddingModelName',
      'rust_core.dbListEmbeddingProfiles',
      'rust_core.dbCreateEmbeddingProfile',
      'rust_core.dbSetActiveEmbeddingProfile',
      'rust_core.dbDeleteEmbeddingProfile',
      'rust_core.dbListLlmProfiles',
      'rust_core.dbCreateLlmProfile',
      'rust_core.dbSetActiveLlmProfile',
      'rust_core.dbDeleteLlmProfile',
      'rust_core.dbSumLlmUsageDailyByPurpose',
    ]) {
      expect(nativeEmbeddings, isNot(contains(token)), reason: token);
      expect(nativeBackend, isNot(contains(token)), reason: token);
    }
  });
}
