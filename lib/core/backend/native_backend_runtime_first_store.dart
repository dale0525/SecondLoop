part of 'native_backend.dart';

final Map<String, _DartNativeRuntimeState> _dartNativeRuntimeStates =
    <String, _DartNativeRuntimeState>{};

_DartNativeRuntimeState _dartNativeRuntimeStateFor(String appDir) {
  return _dartNativeRuntimeStates.putIfAbsent(
    appDir,
    _DartNativeRuntimeState.new,
  );
}

final class _DartNativeRuntimeState {
  String? password;
  Uint8List? key;
  int nextConversationSeq = 1;
  int nextMessageSeq = 1;
  int nextChecklistItemSeq = 1;
  int nextChecklistSuggestionSeq = 1;
  int nextTodoActivitySeq = 1;
  int nextTodoFollowupSuggestionSeq = 1;
  int nextEmbeddingProfileSeq = 1;
  int nextLlmProfileSeq = 1;
  int nextSecretaryRunSeq = 1;
  int nextSecretaryToolCallSeq = 1;
  final Map<String, Conversation> conversations = <String, Conversation>{};
  final Map<String, List<Message>> messagesByConversation =
      <String, List<Message>>{};
  final Map<String, Todo> todos = <String, Todo>{};
  final Map<String, TodoActivity> todoActivities = <String, TodoActivity>{};
  final Map<String, Attachment> attachments = <String, Attachment>{};
  final Map<String, Uint8List> attachmentBytes = <String, Uint8List>{};
  final Map<String, List<String>> messageAttachmentShas =
      <String, List<String>>{};
  final Map<String, AttachmentExifMetadata> attachmentExif =
      <String, AttachmentExifMetadata>{};
  final Map<String, String> attachmentAnnotationPayloadJson =
      <String, String>{};
  final Map<String, Event> events = <String, Event>{};
  String activeEmbeddingModelName = '';
  final Map<String, EmbeddingProfile> embeddingProfiles =
      <String, EmbeddingProfile>{};
  final Map<String, LlmProfile> llmProfiles = <String, LlmProfile>{};
  final Map<String, TodoChecklistItem> checklistItems =
      <String, TodoChecklistItem>{};
  final Map<String, TodoChecklistSuggestion> checklistSuggestions =
      <String, TodoChecklistSuggestion>{};
  final Map<String, TodoFollowupSuggestion> todoFollowupSuggestions =
      <String, TodoFollowupSuggestion>{};
  final Map<String, TodoFollowupGenerationJob> todoFollowupJobs =
      <String, TodoFollowupGenerationJob>{};
  final Map<String, PlanningOutputRecord> planningOutputs =
      <String, PlanningOutputRecord>{};
  final Map<String, SecretaryRunRecord> secretaryRuns =
      <String, SecretaryRunRecord>{};
  final Map<String, SecretaryToolCallRecord> secretaryToolCalls =
      <String, SecretaryToolCallRecord>{};
  final Map<String, String> todoRecurrenceRules = <String, String>{};
  final Map<String, List<String>> todoActivityAttachmentShas =
      <String, List<String>>{};
  final Set<String> detachedAskCompletionRequestIds = <String>{};
}

int _dartRuntimeNowMs() => DateTime.now().millisecondsSinceEpoch;

Uint8List _dartRuntimeNewSessionKey() {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(32, (_) => random.nextInt(256)),
  );
}

void _dartRuntimeValidateKey(
  _DartNativeRuntimeState state,
  List<int> key,
) {
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

Future<bool> _dartAuthIsInitialized({required String appDir}) async {
  return _dartNativeRuntimeStateFor(appDir).key != null;
}

Future<Uint8List> _dartAuthInitMasterPassword({
  required String appDir,
  required String password,
}) async {
  return _dartAuthInitMasterPasswordWithExistingKey(
    appDir: appDir,
    password: password,
    key: _dartRuntimeNewSessionKey(),
  );
}

Future<Uint8List> _dartAuthInitMasterPasswordWithExistingKey({
  required String appDir,
  required String password,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  final sessionKey = Uint8List.fromList(key);
  state
    ..password = password
    ..key = sessionKey;
  return Uint8List.fromList(sessionKey);
}

Future<Uint8List> _dartAuthUnlockWithPassword({
  required String appDir,
  required String password,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  if (state.password != password || state.key == null) {
    throw StateError('invalid_master_password');
  }
  return Uint8List.fromList(state.key!);
}

Future<void> _dartAuthValidateKey({
  required String appDir,
  required List<int> key,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
}

Future<List<Conversation>> _dartDbListConversations({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.conversations.values.toList(growable: false)
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
}

Future<Conversation> _dartDbCreateConversation({
  required String appDir,
  required List<int> key,
  required String title,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
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

Future<Conversation> _dartDbGetOrCreateLoopHomeConversation({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  const id = 'loop_home';
  final existing = state.conversations[id];
  if (existing != null) return existing;
  final now = _dartRuntimeNowMs();
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

Future<List<Message>> _dartDbListMessages({
  required String appDir,
  required List<int> key,
  required String conversationId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return List<Message>.from(
    state.messagesByConversation[conversationId] ?? const <Message>[],
  );
}

Future<List<Message>> _dartDbListMessagesPage({
  required String appDir,
  required List<int> key,
  required String conversationId,
  PlatformInt64? beforeCreatedAtMs,
  String? beforeId,
  required int limit,
}) async {
  final messages = await _dartDbListMessages(
    appDir: appDir,
    key: key,
    conversationId: conversationId,
  );
  messages.sort((a, b) {
    final byTime = b.createdAtMs.compareTo(a.createdAtMs);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  });
  if (beforeCreatedAtMs == null || beforeId == null) {
    return messages.take(limit).toList(growable: false);
  }
  final cursor = messages.indexWhere(
    (message) =>
        message.id == beforeId && message.createdAtMs == beforeCreatedAtMs,
  );
  if (cursor < 0) return const <Message>[];
  return messages.skip(cursor + 1).take(limit).toList(growable: false);
}

Future<Message?> _dartDbGetMessageById({
  required String appDir,
  required List<int> key,
  required String messageId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  for (final messages in state.messagesByConversation.values) {
    for (final message in messages) {
      if (message.id == messageId) return message;
    }
  }
  return null;
}

Future<Message> _dartDbInsertMessage({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String role,
  required String content,
  String? citationsJson,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = _dartRuntimeNowMs();
  final conversation = state.conversations[conversationId];
  state.conversations[conversationId] = Conversation(
    id: conversationId,
    title: conversation?.title ??
        (conversationId == 'loop_home' ? 'Loop' : 'Conversation'),
    createdAtMs: conversation?.createdAtMs ?? now,
    updatedAtMs: now,
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

String _dartAttachmentSha(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return '${hash.toRadixString(16).padLeft(16, '0')}${bytes.length}';
}

Future<Attachment> _dartDbInsertAttachment({
  required String appDir,
  required List<int> key,
  required List<int> bytes,
  required String mimeType,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final data = Uint8List.fromList(bytes);
  final sha = _dartAttachmentSha(data);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  final existing = state.attachments[sha];
  if (existing != null) return existing;
  final attachment = Attachment(
    sha256: sha,
    mimeType: mimeType,
    path: 'dart-runtime://attachment/$sha',
    byteLen: PlatformInt64Util.from(data.length),
    createdAtMs: now,
  );
  state.attachments[sha] = attachment;
  state.attachmentBytes[sha] = data;
  return attachment;
}

Future<void> _dartDbUpsertAttachmentDerivation({
  required String appDir,
  required List<int> key,
  required String rootSha256,
  required String childSha256,
  required String role,
  required PlatformInt64 createdAtMs,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!state.attachments.containsKey(rootSha256)) {
    throw StateError('attachment_not_found:$rootSha256');
  }
  if (!state.attachments.containsKey(childSha256)) {
    throw StateError('attachment_not_found:$childSha256');
  }
}

Future<List<Attachment>> _dartDbListRecentAttachments({
  required String appDir,
  required List<int> key,
  required int limit,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final attachments = state.attachments.values.toList(growable: false);
  attachments.sort((a, b) {
    final byTime = b.createdAtMs.compareTo(a.createdAtMs);
    return byTime != 0 ? byTime : a.sha256.compareTo(b.sha256);
  });
  return attachments.take(limit).toList(growable: false);
}

Future<void> _dartDbLinkAttachmentToMessage({
  required String appDir,
  required List<int> key,
  required String messageId,
  required String attachmentSha256,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!state.attachments.containsKey(attachmentSha256)) {
    throw StateError('attachment_not_found:$attachmentSha256');
  }
  final shas = state.messageAttachmentShas.putIfAbsent(
    messageId,
    () => <String>[],
  );
  if (!shas.contains(attachmentSha256)) shas.add(attachmentSha256);
}

Future<List<Attachment>> _dartDbListMessageAttachments({
  required String appDir,
  required List<int> key,
  required String messageId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return (state.messageAttachmentShas[messageId] ?? const <String>[])
      .map((sha) => state.attachments[sha])
      .whereType<Attachment>()
      .toList(growable: false);
}

Future<Uint8List> _dartDbReadAttachmentBytes({
  required String appDir,
  required List<int> key,
  required String sha256,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final bytes = state.attachmentBytes[sha256];
  if (bytes == null) throw StateError('attachment_not_found:$sha256');
  return Uint8List.fromList(bytes);
}

Future<void> _dartDbUpsertAttachmentExifMetadata({
  required String appDir,
  required List<int> key,
  required String attachmentSha256,
  PlatformInt64? capturedAtMs,
  double? latitude,
  double? longitude,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.attachmentExif[attachmentSha256] = AttachmentExifMetadata(
    capturedAtMs: capturedAtMs,
    latitude: latitude,
    longitude: longitude,
  );
}

Future<AttachmentExifMetadata?> _dartDbReadAttachmentExifMetadata({
  required String appDir,
  required List<int> key,
  required String attachmentSha256,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.attachmentExif[attachmentSha256];
}

Future<String?> _dartDbReadAttachmentPlaceDisplayName({
  required String appDir,
  required List<int> key,
  required String attachmentSha256,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return null;
}

Future<String?> _dartDbReadAttachmentAnnotationPayloadJson({
  required String appDir,
  required List<int> key,
  required String attachmentSha256,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.attachmentAnnotationPayloadJson[attachmentSha256];
}

Future<String?> _dartDbReadAttachmentAnnotationCaptionLong({
  required String appDir,
  required List<int> key,
  required String attachmentSha256,
}) async {
  final raw = await _dartDbReadAttachmentAnnotationPayloadJson(
    appDir: appDir,
    key: key,
    attachmentSha256: attachmentSha256,
  );
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final caption =
        (decoded['caption_long'] ?? decoded['caption'])?.toString().trim();
    return caption == null || caption.isEmpty ? null : caption;
  } catch (_) {
    return null;
  }
}

Future<void> _dartDbEditMessage({
  required String appDir,
  required List<int> key,
  required String messageId,
  required String content,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  for (final entry in state.messagesByConversation.entries) {
    final index = entry.value.indexWhere((message) => message.id == messageId);
    if (index < 0) continue;
    final existing = entry.value[index];
    entry.value[index] = Message(
      id: existing.id,
      conversationId: existing.conversationId,
      role: existing.role,
      content: content,
      createdAtMs: existing.createdAtMs,
      isMemory: existing.isMemory,
      citationsJson: existing.citationsJson,
    );
    return;
  }
  throw StateError('message_not_found:$messageId');
}

Future<void> _dartDbSetMessageDeleted({
  required String appDir,
  required List<int> key,
  required String messageId,
  required bool isDeleted,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  if (!isDeleted) return;
  for (final messages in state.messagesByConversation.values) {
    messages.removeWhere((message) => message.id == messageId);
  }
  state.messageAttachmentShas.remove(messageId);
}

Future<void> _dartDbPurgeMessageAttachments({
  required String appDir,
  required List<int> key,
  required String messageId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.messageAttachmentShas.remove(messageId);
}

Future<void> _dartDbResetVaultDataPreservingLlmProfiles({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state
    ..nextConversationSeq = 1
    ..nextMessageSeq = 1
    ..nextChecklistItemSeq = 1
    ..nextChecklistSuggestionSeq = 1
    ..nextTodoActivitySeq = 1
    ..nextTodoFollowupSuggestionSeq = 1
    ..nextSecretaryRunSeq = 1
    ..nextSecretaryToolCallSeq = 1;
  state.conversations.clear();
  state.messagesByConversation.clear();
  state.todos.clear();
  state.todoActivities.clear();
  state.attachments.clear();
  state.attachmentBytes.clear();
  state.messageAttachmentShas.clear();
  state.attachmentExif.clear();
  state.attachmentAnnotationPayloadJson.clear();
  state.checklistItems.clear();
  state.checklistSuggestions.clear();
  state.todoFollowupSuggestions.clear();
  state.todoFollowupJobs.clear();
  state.planningOutputs.clear();
  state.secretaryRuns.clear();
  state.secretaryToolCalls.clear();
  state.todoRecurrenceRules.clear();
  state.todoActivityAttachmentShas.clear();
}

Future<void> _dartDbClearLocalAttachmentCache({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
}

Future<Attachment?> _dartDbReadAttachmentBySha256({
  required String appDir,
  required String attachmentSha256,
}) async {
  return _dartNativeRuntimeStateFor(appDir).attachments[attachmentSha256];
}

Future<void> _dartDbMarkAttachmentAnnotationOkJson({
  required String appDir,
  required List<int> key,
  required String attachmentSha256,
  required String lang,
  required String modelName,
  required String payloadJson,
  required PlatformInt64 nowMs,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.attachmentAnnotationPayloadJson[attachmentSha256] = payloadJson;
}

Future<List<Event>> _dartDbListEvents({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.events.values.toList(growable: false)
    ..sort((a, b) => a.startAtMs.compareTo(b.startAtMs));
}

Future<Event?> _dartDbGetEventById({
  required String appDir,
  required List<int> key,
  required String eventId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.events[eventId];
}

Future<Event> _dartDbUpsertEvent({
  required String appDir,
  required List<int> key,
  required String id,
  required String title,
  required PlatformInt64 startAtMs,
  required PlatformInt64 endAtMs,
  required String tz,
  String? sourceEntryId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  final existing = state.events[id];
  final event = Event(
    id: id,
    title: title,
    startAtMs: startAtMs,
    endAtMs: endAtMs,
    tz: tz,
    sourceEntryId: sourceEntryId,
    createdAtMs: existing?.createdAtMs ?? now,
    updatedAtMs: now,
  );
  state.events[id] = event;
  return event;
}

Future<int> _dartDbProcessPendingMessageEmbeddings({
  required String appDir,
  required List<int> key,
  required int limit,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  return 0;
}

Future<bool> _dartDbReleaseLocalEmbeddingModelIfIdle({
  required String appDir,
  required List<int> key,
  required int maxIdleMs,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  return false;
}

Future<int> _dartDbNoopEmbeddingBatch({
  required String appDir,
  required List<int> key,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  return 0;
}

Future<List<SimilarMessage>> _dartDbSearchSimilarMessages({
  required String appDir,
  required List<int> key,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  return const <SimilarMessage>[];
}

Future<List<TodoThreadMatch>> _dartDbSearchSimilarTodoThreads({
  required String appDir,
  required List<int> key,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  return const <TodoThreadMatch>[];
}

Future<List<String>> _dartDbListEmbeddingModelNames({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final values = <String>{};
  if (state.activeEmbeddingModelName.trim().isNotEmpty) {
    values.add(state.activeEmbeddingModelName);
  }
  for (final profile in state.embeddingProfiles.values) {
    if (profile.modelName.trim().isNotEmpty) values.add(profile.modelName);
  }
  return values.toList(growable: false)..sort();
}

Future<String> _dartDbGetActiveEmbeddingModelName({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.activeEmbeddingModelName;
}

Future<bool> _dartDbSetActiveEmbeddingModelName({
  required String appDir,
  required List<int> key,
  required String modelName,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.activeEmbeddingModelName = modelName;
  return true;
}

EmbeddingProfile _copyEmbeddingProfile(
  EmbeddingProfile profile, {
  bool? isActive,
  PlatformInt64? updatedAtMs,
}) {
  return EmbeddingProfile(
    id: profile.id,
    name: profile.name,
    providerType: profile.providerType,
    baseUrl: profile.baseUrl,
    modelName: profile.modelName,
    isActive: isActive ?? profile.isActive,
    createdAtMs: profile.createdAtMs,
    updatedAtMs: updatedAtMs ?? profile.updatedAtMs,
  );
}

LlmProfile _copyLlmProfile(
  LlmProfile profile, {
  bool? isActive,
  PlatformInt64? updatedAtMs,
}) {
  return LlmProfile(
    id: profile.id,
    name: profile.name,
    providerType: profile.providerType,
    baseUrl: profile.baseUrl,
    modelName: profile.modelName,
    isActive: isActive ?? profile.isActive,
    createdAtMs: profile.createdAtMs,
    updatedAtMs: updatedAtMs ?? profile.updatedAtMs,
  );
}

Future<List<EmbeddingProfile>> _dartDbListEmbeddingProfiles({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.embeddingProfiles.values.toList(growable: false)
    ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
}

Future<EmbeddingProfile> _dartDbCreateEmbeddingProfile({
  required String appDir,
  required List<int> key,
  required String name,
  required String providerType,
  String? baseUrl,
  String? apiKey,
  required String modelName,
  required bool setActive,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  final id = 'embedding_profile_${state.nextEmbeddingProfileSeq++}';
  if (setActive) {
    for (final entry in state.embeddingProfiles.entries.toList()) {
      state.embeddingProfiles[entry.key] = _copyEmbeddingProfile(
        entry.value,
        isActive: false,
        updatedAtMs: now,
      );
    }
  }
  final profile = EmbeddingProfile(
    id: id,
    name: name,
    providerType: providerType,
    baseUrl: baseUrl,
    modelName: modelName,
    isActive: setActive,
    createdAtMs: now,
    updatedAtMs: now,
  );
  state.embeddingProfiles[id] = profile;
  if (setActive) state.activeEmbeddingModelName = modelName;
  return profile;
}

Future<void> _dartDbSetActiveEmbeddingProfile({
  required String appDir,
  required List<int> key,
  required String profileId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  if (!state.embeddingProfiles.containsKey(profileId)) {
    throw StateError('embedding_profile_not_found:$profileId');
  }
  for (final entry in state.embeddingProfiles.entries.toList()) {
    final active = entry.key == profileId;
    state.embeddingProfiles[entry.key] = _copyEmbeddingProfile(
      entry.value,
      isActive: active,
      updatedAtMs: now,
    );
    if (active) state.activeEmbeddingModelName = entry.value.modelName;
  }
}

Future<void> _dartDbDeleteEmbeddingProfile({
  required String appDir,
  required List<int> key,
  required String profileId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.embeddingProfiles.remove(profileId);
}

Future<List<LlmProfile>> _dartDbListLlmProfiles({
  required String appDir,
  required List<int> key,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  return state.llmProfiles.values.toList(growable: false)
    ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
}

Future<LlmProfile> _dartDbCreateLlmProfile({
  required String appDir,
  required List<int> key,
  required String name,
  required String providerType,
  String? baseUrl,
  String? apiKey,
  required String modelName,
  required bool setActive,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  final id = 'llm_profile_${state.nextLlmProfileSeq++}';
  if (setActive) {
    for (final entry in state.llmProfiles.entries.toList()) {
      state.llmProfiles[entry.key] = _copyLlmProfile(
        entry.value,
        isActive: false,
        updatedAtMs: now,
      );
    }
  }
  final profile = LlmProfile(
    id: id,
    name: name,
    providerType: providerType,
    baseUrl: baseUrl,
    modelName: modelName,
    isActive: setActive,
    createdAtMs: now,
    updatedAtMs: now,
  );
  state.llmProfiles[id] = profile;
  return profile;
}

Future<void> _dartDbSetActiveLlmProfile({
  required String appDir,
  required List<int> key,
  required String profileId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  final now = PlatformInt64Util.from(_dartRuntimeNowMs());
  if (!state.llmProfiles.containsKey(profileId)) {
    throw StateError('llm_profile_not_found:$profileId');
  }
  for (final entry in state.llmProfiles.entries.toList()) {
    state.llmProfiles[entry.key] = _copyLlmProfile(
      entry.value,
      isActive: entry.key == profileId,
      updatedAtMs: now,
    );
  }
}

Future<void> _dartDbDeleteLlmProfile({
  required String appDir,
  required List<int> key,
  required String profileId,
}) async {
  final state = _dartNativeRuntimeStateFor(appDir);
  _dartRuntimeValidateKey(state, key);
  state.llmProfiles.remove(profileId);
}

Future<List<LlmUsageAggregate>> _dartDbSumLlmUsageDailyByPurpose({
  required String appDir,
  required List<int> key,
}) async {
  _dartRuntimeValidateKey(_dartNativeRuntimeStateFor(appDir), key);
  return const <LlmUsageAggregate>[];
}
