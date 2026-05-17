import 'dart:typed_data';
import '../../models/app_models.dart';
import '../../models/semantic_parse_models.dart';
import '../../models/platform_int.dart';

final Map<String, _DartRuntimeVaultState> _vaultStates =
    <String, _DartRuntimeVaultState>{};

_DartRuntimeVaultState _stateFor(String appDir) {
  return _vaultStates.putIfAbsent(appDir, _DartRuntimeVaultState.new);
}

final class _DartRuntimeVaultState {
  String? password;
  Uint8List? key;
  int nextConversationSeq = 1;
  int nextMessageSeq = 1;
  final Map<String, Conversation> conversations = <String, Conversation>{};
  final Map<String, List<Message>> messagesByConversation =
      <String, List<Message>>{};
  final Map<String, Todo> todos = <String, Todo>{};
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

Uint8List _newSessionKey(String appDir, String password) {
  final seed = '$appDir\n$password';
  return Uint8List.fromList(List<int>.generate(32, (index) {
    final code = seed.codeUnitAt(index % seed.length);
    return (code + index * 31) & 0xff;
  }));
}

void _validateKey(_DartRuntimeVaultState state, List<int> key) {
  final expected = state.key;
  if (expected == null) {
    throw StateError('dart_runtime_vault_not_initialized');
  }
  if (expected.length != key.length) {
    throw StateError('invalid_vault_key');
  }
  for (var i = 0; i < expected.length; i += 1) {
    if (expected[i] != key[i]) {
      throw StateError('invalid_vault_key');
    }
  }
}

Future<bool> authIsInitialized({required String appDir}) async {
  return _stateFor(appDir).key != null;
}

Future<Uint8List> authInitMasterPassword({
  required String appDir,
  required String password,
}) async {
  final state = _stateFor(appDir);
  final key = _newSessionKey(appDir, password);
  state
    ..password = password
    ..key = key;
  return Uint8List.fromList(key);
}

Future<Uint8List> authInitMasterPasswordWithExistingKey({
  required String appDir,
  required String password,
  required List<int> key,
}) async {
  final state = _stateFor(appDir);
  final sessionKey = Uint8List.fromList(key);
  state
    ..password = password
    ..key = sessionKey;
  return Uint8List.fromList(sessionKey);
}

Future<Uint8List> authUnlockWithPassword({
  required String appDir,
  required String password,
}) async {
  final state = _stateFor(appDir);
  if (state.password != password || state.key == null) {
    throw StateError('invalid_master_password');
  }
  return Uint8List.fromList(state.key!);
}

Future<void> authValidateKey({
  required String appDir,
  required List<int> key,
}) async {
  _validateKey(_stateFor(appDir), key);
}

Future<List<Conversation>> dbListConversations({
  required String appDir,
  required List<int> key,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  return state.conversations.values.toList(growable: false)
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
}

Future<Conversation> dbCreateConversation({
  required String appDir,
  required List<int> key,
  required String title,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  final now = _nowMs();
  final conversation = Conversation(
    id: 'conversation_${state.nextConversationSeq++}',
    title: title,
    createdAtMs: now,
    updatedAtMs: now,
  );
  state.conversations[conversation.id] = conversation;
  state.messagesByConversation.putIfAbsent(conversation.id, () => <Message>[]);
  return conversation;
}

Future<Conversation> dbGetOrCreateLoopHomeConversation({
  required String appDir,
  required List<int> key,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  const id = 'loop_home';
  final existing = state.conversations[id];
  if (existing != null) return existing;
  final now = _nowMs();
  final conversation = Conversation(
    id: id,
    title: 'Loop',
    createdAtMs: now,
    updatedAtMs: now,
  );
  state.conversations[id] = conversation;
  state.messagesByConversation.putIfAbsent(id, () => <Message>[]);
  return conversation;
}

Future<List<Message>> dbListMessages({
  required String appDir,
  required List<int> key,
  required String conversationId,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  return List<Message>.from(
    state.messagesByConversation[conversationId] ?? const <Message>[],
  );
}

Future<List<Message>> dbListMessagesPage({
  required String appDir,
  required List<int> key,
  required String conversationId,
  PlatformInt64? beforeCreatedAtMs,
  String? beforeId,
  required int limit,
}) async {
  final messages = (await dbListMessages(
    appDir: appDir,
    key: key,
    conversationId: conversationId,
  ))
    ..sort((a, b) {
      final byTime = b.createdAtMs.compareTo(a.createdAtMs);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  if (beforeCreatedAtMs == null || beforeId == null) {
    return messages.take(limit).toList(growable: false);
  }
  final cursor = messages.indexWhere((message) => message.id == beforeId);
  if (cursor < 0) return const <Message>[];
  return messages.skip(cursor + 1).take(limit).toList(growable: false);
}

Future<Message?> dbGetMessageById({
  required String appDir,
  required List<int> key,
  required String messageId,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  for (final messages in state.messagesByConversation.values) {
    for (final message in messages) {
      if (message.id == messageId) return message;
    }
  }
  return null;
}

Future<Message> dbInsertMessage({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String role,
  required String content,
  String? citationsJson,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  final now = _nowMs();
  state.conversations.putIfAbsent(
    conversationId,
    () => Conversation(
      id: conversationId,
      title: conversationId == 'loop_home' ? 'Loop' : 'Conversation',
      createdAtMs: now,
      updatedAtMs: now,
    ),
  );
  final message = Message(
    id: 'message_${state.nextMessageSeq++}',
    conversationId: conversationId,
    role: role,
    content: content,
    createdAtMs: now,
    isMemory: false,
    citationsJson: citationsJson,
  );
  state.messagesByConversation
      .putIfAbsent(conversationId, () => <Message>[])
      .add(message);
  return message;
}

Future<Todo> dbUpsertTodo({
  required String appDir,
  required List<int> key,
  required String id,
  required String title,
  PlatformInt64? dueAtMs,
  required String status,
  String? sourceEntryId,
  PlatformInt64? reviewStage,
  PlatformInt64? nextReviewAtMs,
  PlatformInt64? lastReviewAtMs,
  PlatformInt64? manualImportanceNudgeScore,
  PlatformInt64? manualUrgencyNudgeScore,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  final now = _nowMs();
  final existing = state.todos[id];
  final todo = Todo(
    id: id,
    title: title,
    dueAtMs: dueAtMs,
    status: status,
    sourceEntryId: sourceEntryId,
    createdAtMs: existing?.createdAtMs ?? now,
    updatedAtMs: now,
    reviewStage: reviewStage,
    nextReviewAtMs: nextReviewAtMs,
    lastReviewAtMs: lastReviewAtMs,
    manualImportanceNudgeScore: manualImportanceNudgeScore,
    manualUrgencyNudgeScore: manualUrgencyNudgeScore,
  );
  state.todos[id] = todo;
  return todo;
}

Future<List<Todo>> dbListTodos({
  required String appDir,
  required List<int> key,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  return state.todos.values.toList(growable: false)
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
}

Future<Todo?> dbGetTodoById({
  required String appDir,
  required List<int> key,
  required String todoId,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  return state.todos[todoId];
}

Future<TodoFollowupGenerationJob?> dbGetTodoFollowupGenerationJob(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbGetTodoFollowupGenerationJob');

Future<List<Todo>> dbListTodosCreatedInRange({
  required String appDir,
  required List<int> key,
  required PlatformInt64 startAtMsInclusive,
  required PlatformInt64 endAtMsExclusive,
}) async {
  final todos = await dbListTodos(appDir: appDir, key: key);
  return todos
      .where((todo) =>
          todo.createdAtMs >= startAtMsInclusive &&
          todo.createdAtMs < endAtMsExclusive)
      .toList(growable: false);
}

Future<Todo> dbSetTodoStatus({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String newStatus,
  String? sourceMessageId,
}) async {
  return dbTransitionTodo(
    appDir: appDir,
    key: key,
    todoId: todoId,
    newStatus: newStatus,
    clearDueAtMs: false,
    clearReviewStage: false,
    clearNextReviewAtMs: false,
    clearLastReviewAtMs: false,
    clearManualImportanceNudgeScore: false,
    clearManualUrgencyNudgeScore: false,
    sourceMessageId: sourceMessageId,
  );
}

Future<Todo> dbTransitionTodo({
  required String appDir,
  required List<int> key,
  required String todoId,
  String? newStatus,
  PlatformInt64? dueAtMs,
  required bool clearDueAtMs,
  PlatformInt64? reviewStage,
  required bool clearReviewStage,
  PlatformInt64? nextReviewAtMs,
  required bool clearNextReviewAtMs,
  PlatformInt64? lastReviewAtMs,
  required bool clearLastReviewAtMs,
  PlatformInt64? manualImportanceNudgeScore,
  required bool clearManualImportanceNudgeScore,
  PlatformInt64? manualUrgencyNudgeScore,
  required bool clearManualUrgencyNudgeScore,
  String? sourceMessageId,
}) async {
  final state = _stateFor(appDir);
  _validateKey(state, key);
  final existing = state.todos[todoId];
  if (existing == null) {
    throw StateError('todo_not_found:$todoId');
  }
  final now = _nowMs();
  final todo = Todo(
    id: existing.id,
    title: existing.title,
    dueAtMs: clearDueAtMs ? null : (dueAtMs ?? existing.dueAtMs),
    status: newStatus ?? existing.status,
    sourceEntryId: existing.sourceEntryId,
    createdAtMs: existing.createdAtMs,
    updatedAtMs: now,
    reviewStage:
        clearReviewStage ? null : (reviewStage ?? existing.reviewStage),
    nextReviewAtMs: clearNextReviewAtMs
        ? null
        : (nextReviewAtMs ?? existing.nextReviewAtMs),
    lastReviewAtMs: clearLastReviewAtMs
        ? null
        : (lastReviewAtMs ?? existing.lastReviewAtMs),
    manualImportanceNudgeScore: clearManualImportanceNudgeScore
        ? null
        : (manualImportanceNudgeScore ?? existing.manualImportanceNudgeScore),
    manualUrgencyNudgeScore: clearManualUrgencyNudgeScore
        ? null
        : (manualUrgencyNudgeScore ?? existing.manualUrgencyNudgeScore),
  );
  state.todos[todoId] = todo;
  return todo;
}

Future<Todo> dbUpdateTodoDueWithScope(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 dueAtMs,
        required String scope}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpdateTodoDueWithScope');

Future<Todo> dbUpdateTodoStatusWithScope(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required String newStatus,
        String? sourceMessageId,
        required String scope}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpdateTodoStatusWithScope');

Future<void> dbUpdateTodoRecurrenceRuleWithScope(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required String ruleJson,
        required String scope}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpdateTodoRecurrenceRuleWithScope');

Future<void> dbUpsertTodoRecurrence(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required String seriesId,
        required String ruleJson}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertTodoRecurrence');

Future<String?> dbGetTodoRecurrenceRuleJson(
        {required String appDir, required String todoId}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetTodoRecurrenceRuleJson');

Future<BigInt> dbDeleteTodoAndAssociatedMessages(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbDeleteTodoAndAssociatedMessages');

Future<TodoActivity> dbAppendTodoNote(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required String content,
        String? sourceMessageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbAppendTodoNote');

Future<TodoActivity> dbMoveTodoActivity(
        {required String appDir,
        required List<int> key,
        required String activityId,
        required String toTodoId}) =>
    throw UnsupportedError('rust_runtime_removed:dbMoveTodoActivity');

Future<TodoChecklistItem> dbCreateTodoChecklistItem(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required String content}) =>
    throw UnsupportedError('rust_runtime_removed:dbCreateTodoChecklistItem');

Future<List<TodoChecklistItem>> dbListTodoChecklistItems(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListTodoChecklistItems');

Future<TodoChecklistItem> dbUpdateTodoChecklistItemContent(
        {required String appDir,
        required List<int> key,
        required String itemId,
        required String content}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpdateTodoChecklistItemContent');

Future<TodoChecklistItem> dbSetTodoChecklistItemDone(
        {required String appDir,
        required List<int> key,
        required String itemId,
        required bool isDone}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetTodoChecklistItemDone');

Future<void> dbDeleteTodoChecklistItem(
        {required String appDir,
        required List<int> key,
        required String itemId}) =>
    throw UnsupportedError('rust_runtime_removed:dbDeleteTodoChecklistItem');

Future<void> dbReorderTodoChecklistItems(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> orderedItemIds}) =>
    throw UnsupportedError('rust_runtime_removed:dbReorderTodoChecklistItems');

Future<List<TodoChecklistProgress>> dbListTodoChecklistProgress(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbListTodoChecklistProgress');

Future<List<TodoChecklistSuggestion>> dbListTodoChecklistSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListTodoChecklistSuggestions');

Future<List<TodoChecklistSuggestion>> dbUpsertGeneratedTodoChecklistSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestions,
        required String source,
        String? generationKey}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertGeneratedTodoChecklistSuggestions');

Future<List<TodoChecklistItem>> dbApplyTodoChecklistSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbApplyTodoChecklistSuggestions');

Future<void> dbDismissTodoChecklistSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbDismissTodoChecklistSuggestions');

Future<void> dbDismissAllTodoChecklistSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbDismissAllTodoChecklistSuggestions');

Future<List<TodoFollowupSuggestion>> dbListTodoFollowupSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListTodoFollowupSuggestions');

Future<List<TodoFollowupSuggestion>> dbUpsertGeneratedTodoFollowupSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<TodoFollowupSuggestionDraftInput> suggestions,
        required String source,
        String? generationKey}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertGeneratedTodoFollowupSuggestions');

Future<bool> dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 jobStartedAtMs,
        required List<TodoFollowupSuggestionDraftInput> suggestions,
        required String source,
        String? generationKey}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim');

Future<Todo> dbUpsertTodoWithAutoFollowupJob(
        {required String appDir,
        required List<int> key,
        required String id,
        required String title,
        PlatformInt64? dueAtMs,
        required String status,
        String? sourceEntryId,
        PlatformInt64? reviewStage,
        PlatformInt64? nextReviewAtMs,
        PlatformInt64? lastReviewAtMs,
        String? taskTypeHint,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertTodoWithAutoFollowupJob');

Future<List<TodoActivity>> dbApplyTodoFollowupSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbApplyTodoFollowupSuggestions');

Future<void> dbDismissTodoFollowupSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required List<String> suggestionIds}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbDismissTodoFollowupSuggestions');

Future<void> dbDismissAllTodoFollowupSuggestions(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbDismissAllTodoFollowupSuggestions');

Future<void> dbEnqueueTodoFollowupGenerationJob(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required String triggerKind,
        required bool manualOverrideFollowup,
        String? taskTypeHint,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbEnqueueTodoFollowupGenerationJob');

Future<List<TodoFollowupGenerationJob>> dbListDueTodoFollowupGenerationJobs(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListDueTodoFollowupGenerationJobs');

Future<void> dbMarkTodoFollowupGenerationJobRunning(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkTodoFollowupGenerationJobRunning');

Future<void> dbMarkTodoFollowupGenerationJobFailed(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 attempts,
        required PlatformInt64 nextRetryAtMs,
        required String lastError,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkTodoFollowupGenerationJobFailed');

Future<void> dbMarkTodoFollowupGenerationJobSucceeded(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkTodoFollowupGenerationJobSucceeded');

Future<void> dbMarkTodoFollowupGenerationJobSkipped(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkTodoFollowupGenerationJobSkipped');

Future<void> dbMarkTodoFollowupGenerationJobCanceled(
        {required String appDir,
        required List<int> key,
        required String todoId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkTodoFollowupGenerationJobCanceled');

Future<List<TodoActivity>> dbListTodoActivities(
        {required String appDir,
        required List<int> key,
        required String todoId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListTodoActivities');

Future<List<TodoActivity>> dbListTodoActivitiesInRange(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 startAtMsInclusive,
        required PlatformInt64 endAtMsExclusive}) =>
    throw UnsupportedError('rust_runtime_removed:dbListTodoActivitiesInRange');

Future<void> dbLinkAttachmentToTodoActivity(
        {required String appDir,
        required List<int> key,
        required String activityId,
        required String attachmentSha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbLinkAttachmentToTodoActivity');

Future<List<Attachment>> dbListTodoActivityAttachments(
        {required String appDir,
        required List<int> key,
        required String activityId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListTodoActivityAttachments');

Future<Event> dbUpsertEvent(
        {required String appDir,
        required List<int> key,
        required String id,
        required String title,
        required PlatformInt64 startAtMs,
        required PlatformInt64 endAtMs,
        required String tz,
        String? sourceEntryId}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertEvent');

Future<List<Event>> dbListEvents(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbListEvents');

Future<Event?> dbGetEventById(
        {required String appDir,
        required List<int> key,
        required String eventId}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetEventById');

Future<void> dbEditMessage(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required String content}) =>
    throw UnsupportedError('rust_runtime_removed:dbEditMessage');

Future<void> dbSetMessageDeleted(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required bool isDeleted}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetMessageDeleted');

Future<BigInt> dbPurgeMessageAttachments(
        {required String appDir,
        required List<int> key,
        required String messageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbPurgeMessageAttachments');

Future<void> dbClearLocalAttachmentCache(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbClearLocalAttachmentCache');

Future<Attachment> dbInsertAttachment(
        {required String appDir,
        required List<int> key,
        required List<int> bytes,
        required String mimeType}) =>
    throw UnsupportedError('rust_runtime_removed:dbInsertAttachment');

Future<void> dbUpsertAttachmentDerivation(
        {required String appDir,
        required List<int> key,
        required String rootSha256,
        required String childSha256,
        required String role,
        required PlatformInt64 createdAtMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertAttachmentDerivation');

Future<void> dbLinkAttachmentToMessage(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required String attachmentSha256}) =>
    throw UnsupportedError('rust_runtime_removed:dbLinkAttachmentToMessage');

Future<List<Attachment>> dbListMessageAttachments(
        {required String appDir,
        required List<int> key,
        required String messageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListMessageAttachments');

Future<List<Attachment>> dbListRecentAttachments(
        {required String appDir, required List<int> key, required int limit}) =>
    throw UnsupportedError('rust_runtime_removed:dbListRecentAttachments');

Future<Uint8List> dbReadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required String sha256}) =>
    throw UnsupportedError('rust_runtime_removed:dbReadAttachmentBytes');

Future<void> dbUpsertAttachmentExifMetadata(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        PlatformInt64? capturedAtMs,
        double? latitude,
        double? longitude}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertAttachmentExifMetadata');

Future<AttachmentExifMetadata?> dbReadAttachmentExifMetadata(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256}) =>
    throw UnsupportedError('rust_runtime_removed:dbReadAttachmentExifMetadata');

Future<String?> dbReadAttachmentPlaceDisplayName(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbReadAttachmentPlaceDisplayName');

Future<String?> dbReadAttachmentAnnotationCaptionLong(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbReadAttachmentAnnotationCaptionLong');

Future<void> dbEnqueueAttachmentPlace(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String lang,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbEnqueueAttachmentPlace');

Future<void> dbEnqueueAttachmentAnnotation(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String lang,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbEnqueueAttachmentAnnotation');

Future<List<AttachmentPlaceJob>> dbListDueAttachmentPlaces(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError('rust_runtime_removed:dbListDueAttachmentPlaces');

Future<List<AttachmentAnnotationJob>> dbListDueAttachmentAnnotations(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListDueAttachmentAnnotations');

Future<void> dbMarkAttachmentPlaceFailed(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required PlatformInt64 attempts,
        required PlatformInt64 nextRetryAtMs,
        required String lastError,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbMarkAttachmentPlaceFailed');

Future<void> dbMarkAttachmentAnnotationFailed(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required PlatformInt64 attempts,
        required PlatformInt64 nextRetryAtMs,
        required String lastError,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkAttachmentAnnotationFailed');

Future<void> dbMarkAttachmentPlaceOkJson(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String lang,
        required String payloadJson,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbMarkAttachmentPlaceOkJson');

Future<void> dbMarkAttachmentAnnotationOkJson(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String lang,
        required String modelName,
        required String payloadJson,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkAttachmentAnnotationOkJson');

Future<void> dbEnqueueSemanticParseJob(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbEnqueueSemanticParseJob');

Future<List<SemanticParseJob>> dbListDueSemanticParseJobs(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError('rust_runtime_removed:dbListDueSemanticParseJobs');

Future<List<SemanticParseJob>> dbListSemanticParseJobsByMessageIds(
        {required String appDir,
        required List<int> key,
        required List<String> messageIds}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListSemanticParseJobsByMessageIds');

Future<void> dbMarkSemanticParseJobRunning(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkSemanticParseJobRunning');

Future<PlatformInt64> dbClaimSemanticParseJobRunning(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbClaimSemanticParseJobRunning');

Future<void> dbMarkSemanticParseJobFailed(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 attempts,
        required PlatformInt64 nextRetryAtMs,
        required String lastError,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbMarkSemanticParseJobFailed');

Future<bool> dbMarkSemanticParseJobFailedIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required PlatformInt64 attempts,
        required PlatformInt64 nextRetryAtMs,
        required String lastError,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkSemanticParseJobFailedIfCurrentAttempt');

Future<void> dbMarkSemanticParseJobRetry(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbMarkSemanticParseJobRetry');

Future<void> dbMarkSemanticParseJobSucceeded(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required String appliedActionKind,
        String? appliedTodoId,
        String? appliedTodoTitle,
        String? appliedPrevTodoStatus,
        List<String>? suggestedTags,
        double? suggestedTagConfidence,
        String? tagSuggestionState,
        List<String>? appliedTagIds,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkSemanticParseJobSucceeded');

Future<bool> dbMarkSemanticParseJobSucceededIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String appliedActionKind,
        String? appliedTodoId,
        String? appliedTodoTitle,
        String? appliedPrevTodoStatus,
        List<String>? suggestedTags,
        double? suggestedTagConfidence,
        String? tagSuggestionState,
        List<String>? appliedTagIds,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkSemanticParseJobSucceededIfCurrentAttempt');

Future<void> dbMarkSemanticParseJobCanceled(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkSemanticParseJobCanceled');

Future<PlatformInt64> dbRequeueRunningSemanticParseJobs(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbRequeueRunningSemanticParseJobs');

Future<bool> dbMarkSemanticParseJobCanceledIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkSemanticParseJobCanceledIfCurrentAttempt');

Future<List<String>?> dbCompleteSemanticParseNoActionIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        List<String>? pendingSuggestedTags,
        List<String>? autoApplySuggestedTags,
        double? suggestedTagConfidence,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbCompleteSemanticParseNoActionIfCurrentAttempt');

Future<bool> dbCompleteSemanticParseCreateIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        required String title,
        PlatformInt64? dueAtMs,
        required String status,
        PlatformInt64? reviewStage,
        PlatformInt64? nextReviewAtMs,
        PlatformInt64? lastReviewAtMs,
        String? taskTypeHint,
        String? recurrenceRuleJson,
        required List<String> checklistSuggestions,
        required String checklistSource,
        String? checklistGenerationKey,
        List<String>? pendingSuggestedTags,
        List<String>? autoApplySuggestedTags,
        double? suggestedTagConfidence,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbCompleteSemanticParseCreateIfCurrentAttempt');

Future<bool> dbCompleteSemanticParseFollowupIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        String? todoTitle,
        required String newStatus,
        List<String>? pendingSuggestedTags,
        List<String>? autoApplySuggestedTags,
        double? suggestedTagConfidence,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbCompleteSemanticParseFollowupIfCurrentAttempt');

Future<bool> dbCompleteSemanticParseTodoCommandIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        String? todoTitle,
        required String appliedActionKind,
        String? newTitle,
        String? newStatus,
        PlatformInt64? dueAtMs,
        PlatformInt64? manualImportanceNudgeScore,
        PlatformInt64? manualUrgencyNudgeScore,
        List<String>? pendingSuggestedTags,
        List<String>? autoApplySuggestedTags,
        double? suggestedTagConfidence,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbCompleteSemanticParseTodoCommandIfCurrentAttempt');

Future<List<String>> dbApplySemanticParseTagsIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required List<String> suggestedTags}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbApplySemanticParseTagsIfCurrentAttempt');

Future<String?> dbUpsertTodoFromSemanticParseIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        required String title,
        PlatformInt64? dueAtMs,
        required String status,
        PlatformInt64? reviewStage,
        PlatformInt64? nextReviewAtMs,
        PlatformInt64? lastReviewAtMs,
        String? taskTypeHint,
        String? recurrenceRuleJson,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertTodoFromSemanticParseIfCurrentAttempt');

Future<bool> dbUpsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        required List<String> suggestions,
        required String source,
        String? generationKey}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbUpsertGeneratedTodoChecklistSuggestionsIfCurrentAttempt');

Future<String?> dbSetTodoStatusFromSemanticParseIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        required String newStatus}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbSetTodoStatusFromSemanticParseIfCurrentAttempt');

Future<void> dbMarkSemanticParseJobUndone(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbMarkSemanticParseJobUndone');

Future<String> geoReverseCloudGateway(
        {required String gatewayBaseUrl,
        required String firebaseIdToken,
        required double lat,
        required double lon,
        required String lang}) =>
    throw UnsupportedError('rust_runtime_removed:geoReverseCloudGateway');

Future<String> mediaAnnotationCloudGateway(
        {required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName,
        required String lang,
        required String mimeType,
        required List<int> imageBytes}) =>
    throw UnsupportedError('rust_runtime_removed:mediaAnnotationCloudGateway');

Future<AttachmentVariant> dbUpsertAttachmentVariant(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String variant,
        required List<int> bytes,
        required String mimeType}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertAttachmentVariant');

Future<Uint8List> dbReadAttachmentVariantBytes(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String variant}) =>
    throw UnsupportedError('rust_runtime_removed:dbReadAttachmentVariantBytes');

Future<void> dbEnqueueCloudMediaBackup(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required String desiredVariant,
        required PlatformInt64 nowMs,
        String? scopeId}) =>
    throw UnsupportedError('rust_runtime_removed:dbEnqueueCloudMediaBackup');

Future<BigInt> dbBackfillCloudMediaBackupImages(
        {required String appDir,
        required List<int> key,
        required String desiredVariant,
        required PlatformInt64 nowMs,
        String? scopeId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbBackfillCloudMediaBackupImages');

Future<List<CloudMediaBackup>> dbListDueCloudMediaBackups(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit,
        String? scopeId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListDueCloudMediaBackups');

Future<void> dbMarkCloudMediaBackupFailed(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required PlatformInt64 attempts,
        required PlatformInt64 nextRetryAtMs,
        required String lastError,
        required PlatformInt64 nowMs,
        String? scopeId}) =>
    throw UnsupportedError('rust_runtime_removed:dbMarkCloudMediaBackupFailed');

Future<void> dbMarkCloudMediaBackupUploaded(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        required PlatformInt64 nowMs,
        String? scopeId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbMarkCloudMediaBackupUploaded');

Future<CloudMediaBackupSummary> dbCloudMediaBackupSummary(
        {required String appDir, required List<int> key, String? scopeId}) =>
    throw UnsupportedError('rust_runtime_removed:dbCloudMediaBackupSummary');

Future<void> dbResetVaultDataPreservingLlmProfiles(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbResetVaultDataPreservingLlmProfiles');

Future<String> dbGetOrCreateDeviceId({required String appDir}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetOrCreateDeviceId');

Future<LlmProfile> dbCreateLlmProfile(
        {required String appDir,
        required List<int> key,
        required String name,
        required String providerType,
        String? baseUrl,
        String? apiKey,
        required String modelName,
        required bool setActive}) =>
    throw UnsupportedError('rust_runtime_removed:dbCreateLlmProfile');

Future<List<LlmProfile>> dbListLlmProfiles(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbListLlmProfiles');

Future<void> dbSetActiveLlmProfile(
        {required String appDir,
        required List<int> key,
        required String profileId}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetActiveLlmProfile');

Future<void> dbDeleteLlmProfile(
        {required String appDir,
        required List<int> key,
        required String profileId}) =>
    throw UnsupportedError('rust_runtime_removed:dbDeleteLlmProfile');

Future<EmbeddingProfile> dbCreateEmbeddingProfile(
        {required String appDir,
        required List<int> key,
        required String name,
        required String providerType,
        String? baseUrl,
        String? apiKey,
        required String modelName,
        required bool setActive}) =>
    throw UnsupportedError('rust_runtime_removed:dbCreateEmbeddingProfile');

Future<List<EmbeddingProfile>> dbListEmbeddingProfiles(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbListEmbeddingProfiles');

Future<void> dbSetActiveEmbeddingProfile(
        {required String appDir,
        required List<int> key,
        required String profileId}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetActiveEmbeddingProfile');

Future<void> dbDeleteEmbeddingProfile(
        {required String appDir,
        required List<int> key,
        required String profileId}) =>
    throw UnsupportedError('rust_runtime_removed:dbDeleteEmbeddingProfile');

Future<int> dbProcessPendingMessageEmbeddings(
        {required String appDir, required List<int> key, required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbProcessPendingMessageEmbeddings');

Future<int> dbProcessPendingTodoThreadEmbeddings(
        {required String appDir,
        required List<int> key,
        required int todoLimit,
        required int activityLimit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbProcessPendingTodoThreadEmbeddings');

Future<int> dbProcessPendingTodoThreadEmbeddingsCloudGateway(
        {required String appDir,
        required List<int> key,
        required int todoLimit,
        required int activityLimit,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbProcessPendingTodoThreadEmbeddingsCloudGateway');

Future<int> dbProcessPendingTodoThreadEmbeddingsBrok(
        {required String appDir,
        required List<int> key,
        required int todoLimit,
        required int activityLimit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbProcessPendingTodoThreadEmbeddingsBrok');

Future<List<SimilarMessage>> dbSearchSimilarMessages(
        {required String appDir,
        required List<int> key,
        required String query,
        required int topK}) =>
    throw UnsupportedError('rust_runtime_removed:dbSearchSimilarMessages');

Future<List<SimilarMessage>> dbSearchSimilarMessagesCloudGateway(
        {required String appDir,
        required List<int> key,
        required String query,
        required int topK,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbSearchSimilarMessagesCloudGateway');

Future<List<SimilarMessage>> dbSearchSimilarMessagesBrok(
        {required String appDir,
        required List<int> key,
        required String query,
        required int topK}) =>
    throw UnsupportedError('rust_runtime_removed:dbSearchSimilarMessagesBrok');

Future<List<SimilarTodoThread>> dbSearchSimilarTodoThreads(
        {required String appDir,
        required List<int> key,
        required String query,
        required int topK}) =>
    throw UnsupportedError('rust_runtime_removed:dbSearchSimilarTodoThreads');

Future<List<SimilarTodoThread>> dbSearchSimilarTodoThreadsCloudGateway(
        {required String appDir,
        required List<int> key,
        required String query,
        required int topK,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbSearchSimilarTodoThreadsCloudGateway');

Future<List<SimilarTodoThread>> dbSearchSimilarTodoThreadsBrok(
        {required String appDir,
        required List<int> key,
        required String query,
        required int topK}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbSearchSimilarTodoThreadsBrok');

Future<int> dbRebuildMessageEmbeddings(
        {required String appDir,
        required List<int> key,
        required int batchLimit}) =>
    throw UnsupportedError('rust_runtime_removed:dbRebuildMessageEmbeddings');

Future<List<String>> dbListEmbeddingModelNames(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbListEmbeddingModelNames');

Future<String> dbGetActiveEmbeddingModelName(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbGetActiveEmbeddingModelName');

Future<bool> dbSetActiveEmbeddingModelName(
        {required String appDir,
        required List<int> key,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbSetActiveEmbeddingModelName');

Future<void> dbRecordLlmUsageDaily(
        {required String appDir,
        required List<int> key,
        required String day,
        required String profileId,
        required String purpose,
        PlatformInt64? inputTokens,
        PlatformInt64? outputTokens,
        PlatformInt64? totalTokens}) =>
    throw UnsupportedError('rust_runtime_removed:dbRecordLlmUsageDaily');

Future<List<LlmUsageAggregate>> dbSumLlmUsageDailyByPurpose(
        {required String appDir,
        required List<int> key,
        required String profileId,
        required String startDay,
        required String endDay}) =>
    throw UnsupportedError('rust_runtime_removed:dbSumLlmUsageDailyByPurpose');

Future<String> aiTaskPriorityRerank(
        {required String appDir,
        required List<int> key,
        required String prompt,
        required String localDay}) =>
    throw UnsupportedError('rust_runtime_removed:aiTaskPriorityRerank');

Future<String> aiTaskPriorityRerankCloudGateway(
        {required String appDir,
        required List<int> key,
        required String prompt,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:aiTaskPriorityRerankCloudGateway');

Future<String> aiTodoFollowupRerankCloudGateway(
        {required String appDir,
        required List<int> key,
        required String prompt,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:aiTodoFollowupRerankCloudGateway');

Future<String> aiSemanticParseMessageAction(
        {required String appDir,
        required List<int> key,
        required String text,
        required String nowLocalIso,
        required String locale,
        required int dayEndMinutes,
        required List<TodoCandidate> candidates,
        required String localDay}) =>
    throw UnsupportedError('rust_runtime_removed:aiSemanticParseMessageAction');

Future<String> aiSemanticParseMessageActionCloudGateway(
        {required String appDir,
        required List<int> key,
        required String text,
        required String nowLocalIso,
        required String locale,
        required int dayEndMinutes,
        required List<TodoCandidate> candidates,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:aiSemanticParseMessageActionCloudGateway');

Future<String> aiSemanticParseAskAiTimeWindow(
        {required String appDir,
        required List<int> key,
        required String question,
        required String nowLocalIso,
        required String locale,
        required int firstDayOfWeekIndex,
        required String localDay}) =>
    throw UnsupportedError(
        'rust_runtime_removed:aiSemanticParseAskAiTimeWindow');

Future<String> aiSemanticParseAskAiTimeWindowCloudGateway(
        {required String appDir,
        required List<int> key,
        required String question,
        required String nowLocalIso,
        required String locale,
        required int firstDayOfWeekIndex,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:aiSemanticParseAskAiTimeWindowCloudGateway');

Stream<String> ragAskAiStream(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required String localDay}) =>
    throw UnsupportedError('rust_runtime_removed:ragAskAiStream');

Stream<String> ragAskAiStreamTimeWindow(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required PlatformInt64 timeStartMs,
        required PlatformInt64 timeEndMs,
        required String localDay}) =>
    throw UnsupportedError('rust_runtime_removed:ragAskAiStreamTimeWindow');

Stream<String> ragAskAiStreamWithBrokEmbeddings(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required String localDay}) =>
    throw UnsupportedError(
        'rust_runtime_removed:ragAskAiStreamWithBrokEmbeddings');

Stream<String> ragAskAiStreamWithBrokEmbeddingsTimeWindow(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required PlatformInt64 timeStartMs,
        required PlatformInt64 timeEndMs,
        required String localDay}) =>
    throw UnsupportedError(
        'rust_runtime_removed:ragAskAiStreamWithBrokEmbeddingsTimeWindow');

Stream<String> ragAskAiStreamCloudGateway(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError('rust_runtime_removed:ragAskAiStreamCloudGateway');

Stream<String> ragAskAiStreamCloudGatewayTimeWindow(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required PlatformInt64 timeStartMs,
        required PlatformInt64 timeEndMs,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:ragAskAiStreamCloudGatewayTimeWindow');

Stream<String> ragAskAiStreamCloudGatewayWithEmbeddings(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName,
        required String embeddingsModelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:ragAskAiStreamCloudGatewayWithEmbeddings');

Stream<String> ragAskAiStreamCloudGatewayWithEmbeddingsTimeWindow(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        required PlatformInt64 timeStartMs,
        required PlatformInt64 timeEndMs,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName,
        required String embeddingsModelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:ragAskAiStreamCloudGatewayWithEmbeddingsTimeWindow');

/// Deprecated compatibility path:
/// keep deterministic fixed-salt derivation only for legacy migration flows.
/// New recovery flows should use `sync::recovery_key` envelope APIs.
Future<Uint8List> syncDeriveKey({required String passphrase}) =>
    throw UnsupportedError('rust_runtime_removed:syncDeriveKey');

Future<String> syncCreateRecoveryEnvelope(
        {required List<int> syncKey, required String passphrase}) =>
    throw UnsupportedError('rust_runtime_removed:syncCreateRecoveryEnvelope');

Future<Uint8List> syncRecoverSyncKeyFromEnvelope(
        {required String envelopeJson, required String passphrase}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncRecoverSyncKeyFromEnvelope');

Future<void> syncWebdavTestConnection(
        {required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncWebdavTestConnection');

Future<BigInt> syncWebdavPush(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncWebdavPush');

Future<BigInt> syncWebdavPushOpsOnly(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncWebdavPushOpsOnly');

Future<BigInt> syncWebdavPull(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncWebdavPull');

Future<void> syncWebdavDownloadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot,
        required String sha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncWebdavDownloadAttachmentBytes');

Future<bool> syncWebdavUploadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot,
        required String sha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncWebdavUploadAttachmentBytes');

Future<void> syncWebdavClearRemoteRoot(
        {required String baseUrl,
        String? username,
        String? password,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncWebdavClearRemoteRoot');

Future<void> syncLocaldirTestConnection(
        {required String localDir, required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirTestConnection');

Future<BigInt> syncLocaldirPush(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirPush');

Future<BigInt> syncLocaldirPushOpsOnly(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirPushOpsOnly');

Future<BigInt> syncLocaldirPull(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirPull');

Future<void> syncLocaldirDownloadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot,
        required String sha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncLocaldirDownloadAttachmentBytes');

Future<bool> syncLocaldirUploadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String localDir,
        required String remoteRoot,
        required String sha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncLocaldirUploadAttachmentBytes');

Future<void> syncLocaldirClearRemoteRoot(
        {required String localDir, required String remoteRoot}) =>
    throw UnsupportedError('rust_runtime_removed:syncLocaldirClearRemoteRoot');

Future<BigInt> syncManagedVaultPush(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String firebaseIdToken}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultPush');

Future<BigInt> syncManagedVaultPushOpsOnly(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String firebaseIdToken}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultPushOpsOnly');

Future<BigInt> syncManagedVaultPull(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String firebaseIdToken}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultPull');

Future<bool> syncManagedVaultUploadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String firebaseIdToken,
        required String sha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultUploadAttachmentBytes');

Future<void> syncManagedVaultDownloadAttachmentBytes(
        {required String appDir,
        required List<int> key,
        required List<int> syncKey,
        required String baseUrl,
        required String vaultId,
        required String firebaseIdToken,
        required String sha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:syncManagedVaultDownloadAttachmentBytes');

Future<void> syncManagedVaultClearDevice(
        {required String baseUrl,
        required String vaultId,
        required String firebaseIdToken,
        required String deviceId}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultClearDevice');

Future<void> syncManagedVaultClearVault(
        {required String baseUrl,
        required String vaultId,
        required String firebaseIdToken}) =>
    throw UnsupportedError('rust_runtime_removed:syncManagedVaultClearVault');

Future<SecretaryMemoryProposalRecord> dbCreateSecretaryMemoryProposal(
        {required String appDir,
        required List<int> key,
        String? sourceMessageId,
        required String kind,
        required String title,
        required String body,
        required double confidence,
        String? sourceRefsJson,
        String? actionHint,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbCreateSecretaryMemoryProposal');

Future<List<SecretaryMemoryProposalRecord>> dbListSecretaryMemoryProposals(
        {required String appDir, required List<int> key, String? state}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListSecretaryMemoryProposals');

Future<MemoryPageRecord> dbAcceptSecretaryMemoryProposal(
        {required String appDir,
        required List<int> key,
        required String proposalId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbAcceptSecretaryMemoryProposal');

Future<SecretaryMemoryProposalRecord> dbDismissSecretaryMemoryProposal(
        {required String appDir,
        required List<int> key,
        required String proposalId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbDismissSecretaryMemoryProposal');

Future<List<MemoryPageRecord>> dbListMemoryPages(
        {required String appDir, required List<int> key, String? state}) =>
    throw UnsupportedError('rust_runtime_removed:dbListMemoryPages');

Future<MemoryPageRecord> dbGetMemoryPage(
        {required String appDir,
        required List<int> key,
        required String pageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetMemoryPage');

Future<MemoryPageRecord> dbCorrectMemoryPage(
        {required String appDir,
        required List<int> key,
        required String pageId,
        required String title,
        required String summary,
        required String body,
        String? reason,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbCorrectMemoryPage');

Future<MemoryPageRecord> dbArchiveMemoryPage(
        {required String appDir,
        required List<int> key,
        required String pageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbArchiveMemoryPage');

Future<MemoryPageRecord> dbRestoreMemoryPage(
        {required String appDir,
        required List<int> key,
        required String pageId,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbRestoreMemoryPage');

Future<PlanningOutputRecord> dbUpsertPlanningOutput(
        {required String appDir,
        required List<int> key,
        required String id,
        required String kind,
        required String title,
        required String body,
        required String itemsJson,
        String? sourceRefsJson,
        required String route,
        required String state,
        required PlatformInt64 createdAtMs,
        required PlatformInt64 updatedAtMs,
        PlatformInt64? expiresAtMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertPlanningOutput');

Future<List<PlanningOutputRecord>> dbListPlanningOutputs(
        {required String appDir,
        required List<int> key,
        String? kind,
        required PlatformInt64 nowMs,
        required bool includeExpired}) =>
    throw UnsupportedError('rust_runtime_removed:dbListPlanningOutputs');

Future<SecretaryRunRecord> dbCreateSecretaryRun(
        {required String appDir,
        required List<int> key,
        required String triggerKind,
        required String route,
        required String status,
        String? inputSummary,
        String? outputSummary,
        String? error,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbCreateSecretaryRun');

Future<SecretaryToolCallRecord> dbCreateSecretaryToolCall(
        {required String appDir,
        required List<int> key,
        required String runId,
        required String toolName,
        required String status,
        required bool requiresConfirmation,
        String? inputJson,
        String? outputJson,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError('rust_runtime_removed:dbCreateSecretaryToolCall');

Future<List<SecretaryToolCallRecord>> dbListSecretaryToolCallsForRun(
        {required String appDir,
        required List<int> key,
        required String runId}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListSecretaryToolCallsForRun');
