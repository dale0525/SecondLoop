import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../cloud/http_client_factory_stub.dart'
    if (dart.library.io) '../cloud/http_client_factory_io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/models/platform_int.dart';

import '../../features/actions/todo/todo_thread_match.dart';
import '../storage/secure_blob_store.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/semantic_parse_models.dart';
import '../secretary/todo_command_models.dart';
import 'app_backend.dart';
import 'attachments_backend.dart';
import 'semantic_parse_attempt_aware_backend.dart';
import 'semantic_parse_enhancement_backend.dart';
import 'secretary_backend.dart';

part 'native_backend_todo_followups.dart';
part 'native_backend_todos.dart';
part 'native_backend_attachment_io.dart';
part 'native_backend_attachment_annotation_jobs.dart';
part 'native_backend_cloud_media_backup.dart';
part 'native_backend_embeddings.dart';
part 'native_backend_prompt_ai.dart';
part 'native_backend_jobs.dart';
part 'native_backend_sync_core.dart';
part 'native_backend_sync_webdav.dart';
part 'native_backend_sync_localdir.dart';
part 'native_backend_sync_managed_vault.dart';
part 'native_backend_runtime_first_store.dart';
part 'native_backend_runtime_first_todo_store.dart';
part 'native_backend_runtime_first_followup_store.dart';
part 'native_backend_secretary.dart';
part 'native_backend_secretary_memory_store.dart';
part 'native_backend_vault_rollback.dart';

typedef AppDirProvider = Future<String> Function();

typedef DbInsertMessageFn = Future<Message> Function({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String role,
  required String content,
  String? citationsJson,
});

typedef DbProcessPendingMessageEmbeddingsFn = Future<int> Function({
  required String appDir,
  required List<int> key,
  required int limit,
});

typedef DbReleaseLocalEmbeddingModelIfIdleFn = Future<bool> Function({
  required String appDir,
  required List<int> key,
  required int maxIdleMs,
});

typedef RuntimeCompatInitFn = Future<void> Function();

UnsupportedError _retiredNativeRuntimeFeature(String feature) {
  return UnsupportedError('runtime_first_native_runtime_removed:$feature');
}

typedef DbInsertAttachmentFn = Future<Attachment> Function({
  required String appDir,
  required List<int> key,
  required List<int> bytes,
  required String mimeType,
});

typedef AskAiStreamScopedFn = Stream<String> Function({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String question,
  required int topK,
  required bool thisThreadOnly,
  int? timeStartMs,
  int? timeEndMs,
  required List<String> includeTagIds,
  required List<String> excludeTagIds,
  required bool strictMode,
  required String localeLanguage,
  required String localDay,
});

typedef DbCreateTodoChecklistItemFn = Future<TodoChecklistItem> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required String content,
});

typedef DbListTodoChecklistItemsFn = Future<List<TodoChecklistItem>> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef DbUpdateTodoChecklistItemContentFn = Future<TodoChecklistItem>
    Function({
  required String appDir,
  required List<int> key,
  required String itemId,
  required String content,
});

typedef DbSetTodoChecklistItemDoneFn = Future<TodoChecklistItem> Function({
  required String appDir,
  required List<int> key,
  required String itemId,
  required bool isDone,
});

typedef DbDeleteTodoChecklistItemFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String itemId,
});

typedef DbReorderTodoChecklistItemsFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> orderedItemIds,
});

typedef DbListTodoChecklistProgressFn = Future<List<TodoChecklistProgress>>
    Function({
  required String appDir,
  required List<int> key,
});

typedef DbListTodoChecklistSuggestionsFn = Future<List<TodoChecklistSuggestion>>
    Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef DbUpsertGeneratedTodoChecklistSuggestionsFn
    = Future<List<TodoChecklistSuggestion>> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestions,
  required String source,
  String? generationKey,
});

typedef DbApplyTodoChecklistSuggestionsFn = Future<List<TodoChecklistItem>>
    Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
});

typedef DbDismissTodoChecklistSuggestionsFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
  required List<String> suggestionIds,
});

typedef DbDismissAllTodoChecklistSuggestionsFn = Future<void> Function({
  required String appDir,
  required List<int> key,
  required String todoId,
});

typedef AskAiStreamCloudGatewayScopedFn = Stream<String> Function({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String question,
  required int topK,
  required bool thisThreadOnly,
  int? timeStartMs,
  int? timeEndMs,
  required List<String> includeTagIds,
  required List<String> excludeTagIds,
  required bool strictMode,
  required String localeLanguage,
  required String gatewayBaseUrl,
  required String firebaseIdToken,
  required String modelName,
});

Stream<String> _ragAskAiStreamScopedCompat({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String question,
  required int topK,
  required bool thisThreadOnly,
  int? timeStartMs,
  int? timeEndMs,
  required List<String> includeTagIds,
  required List<String> excludeTagIds,
  required bool strictMode,
  required String localeLanguage,
  required String localDay,
}) {
  return Stream<String>.error(
    _retiredNativeRuntimeFeature('ragAskAiStreamScoped'),
  );
}

Stream<String> _ragAskAiStreamCloudGatewayScopedCompat({
  required String appDir,
  required List<int> key,
  required String conversationId,
  required String question,
  required int topK,
  required bool thisThreadOnly,
  int? timeStartMs,
  int? timeEndMs,
  required List<String> includeTagIds,
  required List<String> excludeTagIds,
  required bool strictMode,
  required String localeLanguage,
  required String gatewayBaseUrl,
  required String firebaseIdToken,
  required String modelName,
}) {
  return Stream<String>.error(
    _retiredNativeRuntimeFeature('ragAskAiStreamCloudGatewayScoped'),
  );
}

class NativeAppBackend extends _NativeAppBackendAccess
    with
        _NativeAppBackendTodos,
        _NativeAppBackendAttachmentIo,
        _NativeAppBackendAttachmentAnnotationJobs,
        _NativeAppBackendCloudMediaBackup,
        _NativeAppBackendEmbeddings,
        _NativeAppBackendPromptAi,
        _NativeAppBackendJobs,
        _NativeAppBackendSyncCore,
        _NativeAppBackendSyncWebdav,
        _NativeAppBackendSyncLocaldir,
        _NativeAppBackendSyncManagedVault,
        _NativeAppBackendSecretary,
        _NativeAppBackendVaultRollback
    implements
        AppBackend,
        AttachmentsBackend,
        AttachmentAnnotationMutationsBackend,
        SemanticParseAttemptAwareBackend,
        SecretaryBackend,
        AssistantCitationWriteBackend,
        DetachedAskCompletionRecoveryBackend {
  @override
  bool get supportsTodoFollowupSuggestions => true;

  @override
  bool get autoEnqueuesTodoFollowupGenerationOnCreate => true;

  NativeAppBackend({
    FlutterSecureStorage? secureStorage,
    AppDirProvider? appDirProvider,
    String? storageScope,
    DbListTodosFn? dbListTodos,
    DbGetTodoByIdFn? dbGetTodoById,
    DbUpsertTodoFn? dbUpsertTodo,
    DbUpsertTodoWithAutoFollowupJobFn? dbUpsertTodoWithAutoFollowupJob,
    DbInsertMessageFn? dbInsertMessage,
    DbInsertAttachmentFn? dbInsertAttachment,
    DbProcessPendingMessageEmbeddingsFn? dbProcessPendingMessageEmbeddings,
    DbReleaseLocalEmbeddingModelIfIdleFn? dbReleaseLocalEmbeddingModelIfIdle,
    AskAiStreamScopedFn? askAiStreamScopedFn,
    AskAiStreamCloudGatewayScopedFn? askAiStreamCloudGatewayScopedFn,
    DbCreateTodoChecklistItemFn? dbCreateTodoChecklistItem,
    DbListTodoChecklistItemsFn? dbListTodoChecklistItems,
    DbUpdateTodoChecklistItemContentFn? dbUpdateTodoChecklistItemContent,
    DbSetTodoChecklistItemDoneFn? dbSetTodoChecklistItemDone,
    DbDeleteTodoChecklistItemFn? dbDeleteTodoChecklistItem,
    DbReorderTodoChecklistItemsFn? dbReorderTodoChecklistItems,
    DbListTodoChecklistProgressFn? dbListTodoChecklistProgress,
    DbListTodoChecklistSuggestionsFn? dbListTodoChecklistSuggestions,
    DbUpsertGeneratedTodoChecklistSuggestionsFn?
        dbUpsertGeneratedTodoChecklistSuggestions,
    DbApplyTodoChecklistSuggestionsFn? dbApplyTodoChecklistSuggestions,
    DbDismissTodoChecklistSuggestionsFn? dbDismissTodoChecklistSuggestions,
    DbDismissAllTodoChecklistSuggestionsFn?
        dbDismissAllTodoChecklistSuggestions,
    DbListTodoFollowupSuggestionsFn? dbListTodoFollowupSuggestions,
    DbUpsertGeneratedTodoFollowupSuggestionsFn?
        dbUpsertGeneratedTodoFollowupSuggestions,
    DbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaimFn?
        dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim,
    DbApplyTodoFollowupSuggestionsFn? dbApplyTodoFollowupSuggestions,
    DbDismissTodoFollowupSuggestionsFn? dbDismissTodoFollowupSuggestions,
    DbDismissAllTodoFollowupSuggestionsFn? dbDismissAllTodoFollowupSuggestions,
    DbEnqueueTodoFollowupGenerationJobFn? dbEnqueueTodoFollowupGenerationJob,
    DbListDueTodoFollowupGenerationJobsFn? dbListDueTodoFollowupGenerationJobs,
    DbListDueAutoTodoFollowupGenerationJobsFn?
        dbListDueAutoTodoFollowupGenerationJobs,
    DbGetTodoFollowupGenerationJobFn? dbGetTodoFollowupGenerationJob,
    DbMarkTodoFollowupGenerationJobRunningFn?
        dbMarkTodoFollowupGenerationJobRunning,
    DbMarkTodoFollowupGenerationJobFailedFn?
        dbMarkTodoFollowupGenerationJobFailed,
    DbMarkTodoFollowupGenerationJobSucceededFn?
        dbMarkTodoFollowupGenerationJobSucceeded,
    DbMarkTodoFollowupGenerationJobSkippedFn?
        dbMarkTodoFollowupGenerationJobSkipped,
    DbMarkTodoFollowupGenerationJobCanceledFn?
        dbMarkTodoFollowupGenerationJobCanceled,
    DbCreateSecretaryMemoryProposalFn? dbCreateSecretaryMemoryProposal,
    DbListSecretaryMemoryProposalsFn? dbListSecretaryMemoryProposals,
    DbAcceptSecretaryMemoryProposalFn? dbAcceptSecretaryMemoryProposal,
    DbDismissSecretaryMemoryProposalFn? dbDismissSecretaryMemoryProposal,
    DbListMemoryPagesFn? dbListMemoryPages,
    DbGetMemoryPageFn? dbGetMemoryPage,
    DbCorrectMemoryPageFn? dbCorrectMemoryPage,
    DbSetMemoryPageStateFn? dbArchiveMemoryPage,
    DbSetMemoryPageStateFn? dbRestoreMemoryPage,
    DbUpsertPlanningOutputFn? dbUpsertPlanningOutput,
    DbListPlanningOutputsFn? dbListPlanningOutputs,
    DbCreateSecretaryRunFn? dbCreateSecretaryRun,
    DbCreateSecretaryToolCallFn? dbCreateSecretaryToolCall,
    DbListSecretaryToolCallsForRunFn? dbListSecretaryToolCallsForRun,
    RuntimeCompatInitFn? runtimeCompatInit,
    RuntimeCompatInitFn? rustLibInit,
  })  : _storageScope = _normalizeStorageScope(storageScope),
        _secureBlobStore = SecureBlobStore(
          storage: secureStorage,
          scopeKey: _normalizeStorageScope(storageScope),
        ),
        _appDirProvider = appDirProvider ?? _defaultAppDirProvider,
        _dbListTodos = dbListTodos ?? _dartDbListTodos,
        _dbGetTodoById = dbGetTodoById ?? _dartDbGetTodoById,
        _dbUpsertTodoWithAutoFollowupJob =
            _resolveDbUpsertTodoWithAutoFollowupJob(
          dbUpsertTodoWithAutoFollowupJob: dbUpsertTodoWithAutoFollowupJob,
          dbUpsertTodo: dbUpsertTodo,
          dbEnqueueTodoFollowupGenerationJob:
              dbEnqueueTodoFollowupGenerationJob,
        ),
        _dbInsertMessage = dbInsertMessage ?? _dartDbInsertMessage,
        _dbInsertAttachment = dbInsertAttachment ?? _dartDbInsertAttachment,
        _dbProcessPendingMessageEmbeddings =
            dbProcessPendingMessageEmbeddings ??
                _dartDbProcessPendingMessageEmbeddings,
        _dbReleaseLocalEmbeddingModelIfIdle =
            dbReleaseLocalEmbeddingModelIfIdle ??
                _dartDbReleaseLocalEmbeddingModelIfIdle,
        _askAiStreamScoped = askAiStreamScopedFn ?? _ragAskAiStreamScopedCompat,
        _askAiStreamCloudGatewayScoped = askAiStreamCloudGatewayScopedFn ??
            _ragAskAiStreamCloudGatewayScopedCompat,
        _dbCreateTodoChecklistItem =
            dbCreateTodoChecklistItem ?? _dartDbCreateTodoChecklistItem,
        _dbListTodoChecklistItems =
            dbListTodoChecklistItems ?? _dartDbListTodoChecklistItems,
        _dbUpdateTodoChecklistItemContent = dbUpdateTodoChecklistItemContent ??
            _dartDbUpdateTodoChecklistItemContent,
        _dbSetTodoChecklistItemDone =
            dbSetTodoChecklistItemDone ?? _dartDbSetTodoChecklistItemDone,
        _dbDeleteTodoChecklistItem =
            dbDeleteTodoChecklistItem ?? _dartDbDeleteTodoChecklistItem,
        _dbReorderTodoChecklistItems =
            dbReorderTodoChecklistItems ?? _dartDbReorderTodoChecklistItems,
        _dbListTodoChecklistProgress =
            dbListTodoChecklistProgress ?? _dartDbListTodoChecklistProgress,
        _dbListTodoChecklistSuggestions = dbListTodoChecklistSuggestions ??
            _dartDbListTodoChecklistSuggestions,
        _dbUpsertGeneratedTodoChecklistSuggestions =
            dbUpsertGeneratedTodoChecklistSuggestions ??
                _dartDbUpsertGeneratedTodoChecklistSuggestions,
        _dbApplyTodoChecklistSuggestions = dbApplyTodoChecklistSuggestions ??
            _dartDbApplyTodoChecklistSuggestions,
        _dbDismissTodoChecklistSuggestions =
            dbDismissTodoChecklistSuggestions ??
                _dartDbDismissTodoChecklistSuggestions,
        _dbDismissAllTodoChecklistSuggestions =
            dbDismissAllTodoChecklistSuggestions ??
                _dartDbDismissAllTodoChecklistSuggestions,
        _dbListTodoFollowupSuggestions =
            dbListTodoFollowupSuggestions ?? _dartDbListTodoFollowupSuggestions,
        _dbUpsertGeneratedTodoFollowupSuggestions =
            dbUpsertGeneratedTodoFollowupSuggestions ??
                _dartDbUpsertGeneratedTodoFollowupSuggestions,
        _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim =
            dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim ??
                _dartDbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim,
        _dbApplyTodoFollowupSuggestions = dbApplyTodoFollowupSuggestions ??
            _dartDbApplyTodoFollowupSuggestions,
        _dbDismissTodoFollowupSuggestions = dbDismissTodoFollowupSuggestions ??
            _dartDbDismissTodoFollowupSuggestions,
        _dbDismissAllTodoFollowupSuggestions =
            dbDismissAllTodoFollowupSuggestions ??
                _dartDbDismissAllTodoFollowupSuggestions,
        _dbEnqueueTodoFollowupGenerationJob =
            dbEnqueueTodoFollowupGenerationJob ??
                _dartDbEnqueueTodoFollowupGenerationJob,
        _dbListDueTodoFollowupGenerationJobs =
            dbListDueTodoFollowupGenerationJobs ??
                _dartDbListDueTodoFollowupGenerationJobs,
        _dbListDueAutoTodoFollowupGenerationJobs =
            dbListDueAutoTodoFollowupGenerationJobs ??
                _dartDbListDueAutoTodoFollowupGenerationJobs,
        _dbGetTodoFollowupGenerationJob = dbGetTodoFollowupGenerationJob ??
            _dartDbGetTodoFollowupGenerationJob,
        _dbMarkTodoFollowupGenerationJobRunning =
            dbMarkTodoFollowupGenerationJobRunning ??
                _dartDbMarkTodoFollowupGenerationJobRunning,
        _dbMarkTodoFollowupGenerationJobFailed =
            dbMarkTodoFollowupGenerationJobFailed ??
                _dartDbMarkTodoFollowupGenerationJobFailed,
        _dbMarkTodoFollowupGenerationJobSucceeded =
            dbMarkTodoFollowupGenerationJobSucceeded ??
                _dartDbMarkTodoFollowupGenerationJobSucceeded,
        _dbMarkTodoFollowupGenerationJobSkipped =
            dbMarkTodoFollowupGenerationJobSkipped ??
                _dartDbMarkTodoFollowupGenerationJobSkipped,
        _dbMarkTodoFollowupGenerationJobCanceled =
            dbMarkTodoFollowupGenerationJobCanceled ??
                _dartDbMarkTodoFollowupGenerationJobCanceled,
        _dbCreateSecretaryMemoryProposal = dbCreateSecretaryMemoryProposal,
        _dbListSecretaryMemoryProposals = dbListSecretaryMemoryProposals,
        _dbAcceptSecretaryMemoryProposal = dbAcceptSecretaryMemoryProposal,
        _dbDismissSecretaryMemoryProposal = dbDismissSecretaryMemoryProposal,
        _dbListMemoryPages = dbListMemoryPages,
        _dbGetMemoryPage = dbGetMemoryPage,
        _dbCorrectMemoryPage = dbCorrectMemoryPage,
        _dbArchiveMemoryPage = dbArchiveMemoryPage,
        _dbRestoreMemoryPage = dbRestoreMemoryPage,
        _dbUpsertPlanningOutput =
            dbUpsertPlanningOutput ?? _dartDbUpsertPlanningOutput,
        _dbListPlanningOutputs =
            dbListPlanningOutputs ?? _dartDbListPlanningOutputs,
        _dbCreateSecretaryRun =
            dbCreateSecretaryRun ?? _dartDbCreateSecretaryRun,
        _dbCreateSecretaryToolCall =
            dbCreateSecretaryToolCall ?? _dartDbCreateSecretaryToolCall,
        _dbListSecretaryToolCallsForRun = dbListSecretaryToolCallsForRun ??
            _dartDbListSecretaryToolCallsForRun,
        _runtimeCompatInit = runtimeCompatInit ?? rustLibInit ?? (() async {});

  @override
  final SecureBlobStore _secureBlobStore;
  final String? _storageScope;
  final AppDirProvider _appDirProvider;
  @override
  final DbListTodosFn _dbListTodos;
  @override
  final DbGetTodoByIdFn _dbGetTodoById;
  @override
  final DbUpsertTodoWithAutoFollowupJobFn _dbUpsertTodoWithAutoFollowupJob;
  final DbInsertMessageFn _dbInsertMessage;
  @override
  final DbInsertAttachmentFn _dbInsertAttachment;
  @override
  final DbProcessPendingMessageEmbeddingsFn _dbProcessPendingMessageEmbeddings;
  @override
  final DbReleaseLocalEmbeddingModelIfIdleFn
      _dbReleaseLocalEmbeddingModelIfIdle;
  @override
  final AskAiStreamScopedFn _askAiStreamScoped;
  @override
  final AskAiStreamCloudGatewayScopedFn _askAiStreamCloudGatewayScoped;
  @override
  final DbCreateTodoChecklistItemFn _dbCreateTodoChecklistItem;
  @override
  final DbListTodoChecklistItemsFn _dbListTodoChecklistItems;
  @override
  final DbUpdateTodoChecklistItemContentFn _dbUpdateTodoChecklistItemContent;
  @override
  final DbSetTodoChecklistItemDoneFn _dbSetTodoChecklistItemDone;
  @override
  final DbDeleteTodoChecklistItemFn _dbDeleteTodoChecklistItem;
  @override
  final DbReorderTodoChecklistItemsFn _dbReorderTodoChecklistItems;
  @override
  final DbListTodoChecklistProgressFn _dbListTodoChecklistProgress;
  @override
  final DbListTodoChecklistSuggestionsFn _dbListTodoChecklistSuggestions;
  @override
  final DbUpsertGeneratedTodoChecklistSuggestionsFn
      _dbUpsertGeneratedTodoChecklistSuggestions;
  @override
  final DbApplyTodoChecklistSuggestionsFn _dbApplyTodoChecklistSuggestions;
  @override
  final DbDismissTodoChecklistSuggestionsFn _dbDismissTodoChecklistSuggestions;
  @override
  final DbDismissAllTodoChecklistSuggestionsFn
      _dbDismissAllTodoChecklistSuggestions;
  @override
  final DbListTodoFollowupSuggestionsFn _dbListTodoFollowupSuggestions;
  @override
  final DbUpsertGeneratedTodoFollowupSuggestionsFn
      _dbUpsertGeneratedTodoFollowupSuggestions;
  @override
  final DbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaimFn
      _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim;
  @override
  final DbApplyTodoFollowupSuggestionsFn _dbApplyTodoFollowupSuggestions;
  @override
  final DbDismissTodoFollowupSuggestionsFn _dbDismissTodoFollowupSuggestions;
  @override
  final DbDismissAllTodoFollowupSuggestionsFn
      _dbDismissAllTodoFollowupSuggestions;
  @override
  final DbEnqueueTodoFollowupGenerationJobFn
      _dbEnqueueTodoFollowupGenerationJob;
  @override
  final DbListDueTodoFollowupGenerationJobsFn
      _dbListDueTodoFollowupGenerationJobs;
  @override
  final DbListDueAutoTodoFollowupGenerationJobsFn
      _dbListDueAutoTodoFollowupGenerationJobs;
  @override
  final DbGetTodoFollowupGenerationJobFn _dbGetTodoFollowupGenerationJob;
  @override
  final DbMarkTodoFollowupGenerationJobRunningFn
      _dbMarkTodoFollowupGenerationJobRunning;
  @override
  final DbMarkTodoFollowupGenerationJobFailedFn
      _dbMarkTodoFollowupGenerationJobFailed;
  @override
  final DbMarkTodoFollowupGenerationJobSucceededFn
      _dbMarkTodoFollowupGenerationJobSucceeded;
  @override
  final DbMarkTodoFollowupGenerationJobSkippedFn
      _dbMarkTodoFollowupGenerationJobSkipped;
  @override
  final DbMarkTodoFollowupGenerationJobCanceledFn
      _dbMarkTodoFollowupGenerationJobCanceled;
  @override
  final DbCreateSecretaryMemoryProposalFn? _dbCreateSecretaryMemoryProposal;
  @override
  final DbListSecretaryMemoryProposalsFn? _dbListSecretaryMemoryProposals;
  @override
  final DbAcceptSecretaryMemoryProposalFn? _dbAcceptSecretaryMemoryProposal;
  @override
  final DbDismissSecretaryMemoryProposalFn? _dbDismissSecretaryMemoryProposal;
  @override
  final DbListMemoryPagesFn? _dbListMemoryPages;
  @override
  final DbGetMemoryPageFn? _dbGetMemoryPage;
  @override
  final DbCorrectMemoryPageFn? _dbCorrectMemoryPage;
  @override
  final DbSetMemoryPageStateFn? _dbArchiveMemoryPage;
  @override
  final DbSetMemoryPageStateFn? _dbRestoreMemoryPage;
  @override
  final DbUpsertPlanningOutputFn _dbUpsertPlanningOutput;
  @override
  final DbListPlanningOutputsFn _dbListPlanningOutputs;
  @override
  final DbCreateSecretaryRunFn _dbCreateSecretaryRun;
  @override
  final DbCreateSecretaryToolCallFn _dbCreateSecretaryToolCall;
  @override
  final DbListSecretaryToolCallsForRunFn _dbListSecretaryToolCallsForRun;
  final RuntimeCompatInitFn _runtimeCompatInit;

  String? _appDir;

  static const _kSessionKeyB64 = 'session_key_b64';

  static const _kDefaultSessionKeyB64PrefsKey = 'default_session_key_b64_v1';
  static const _kDeferredSessionKeyB64PrefsKey = 'deferred_session_key_b64_v1';
  static const _kInternalSessionPassword = 'secondloop-internal-session-v1';

  bool get _isMacNoKeychain =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<String> _defaultAppDirProvider() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  @override
  Future<String> _getAppDir() async {
    final cached = _appDir;
    if (cached != null) return cached;

    _appDir = await _appDirProvider();
    return _appDir!;
  }

  @visibleForTesting
  Future<String> debugResolvedAppDir() => _getAppDir();

  @override
  Future<void> init() async {
    await _runtimeCompatInit();
    await _getAppDir();
  }

  @override
  Future<bool> isMasterPasswordSet() async {
    final appDir = await _getAppDir();
    return _dartAuthIsInitialized(appDir: appDir);
  }

  @override
  Future<Uint8List?> loadSavedSessionKey() async {
    if (_isMacNoKeychain) return null;

    var b64 = await _secureBlobStore.readValue(_kSessionKeyB64);
    if (b64 == null || b64.isEmpty) {
      final legacy = await _secureBlobStore.readKey(_kSessionKeyB64);
      if (legacy != null && legacy.isNotEmpty) {
        await _secureBlobStore.update({_kSessionKeyB64: legacy});
        await _secureBlobStore.deleteKey(_kSessionKeyB64);
        b64 = legacy;
      }
    }
    if (b64 == null || b64.isEmpty) return null;

    try {
      final bytes = base64Decode(b64);
      return Uint8List.fromList(bytes);
    } catch (_) {
      await clearSavedSessionKey();
      return null;
    }
  }

  @override
  Future<void> saveSessionKey(Uint8List key) async {
    if (_isMacNoKeychain) return;

    await _secureBlobStore.update({
      _kSessionKeyB64: base64Encode(key),
    });
  }

  @override
  Future<void> clearSavedSessionKey() async {
    if (_isMacNoKeychain) return;

    await _secureBlobStore.update({_kSessionKeyB64: null});
  }

  @override
  Future<void> validateKey(Uint8List key) async {
    final appDir = await _getAppDir();
    await _dartAuthValidateKey(appDir: appDir, key: key);
  }

  Uint8List _createSessionKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  Uint8List? _decodeSessionKeyB64(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final bytes = base64Decode(value);
      if (bytes.length != 32) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _loadOrCreateDefaultSessionKey(
    SharedPreferences prefs,
  ) async {
    final defaultPrefsKey = _scopedPrefsKey(_kDefaultSessionKeyB64PrefsKey);
    final existing = _decodeSessionKeyB64(prefs.getString(defaultPrefsKey));
    if (existing != null) return existing;

    final deferredPrefsKey = _scopedPrefsKey(_kDeferredSessionKeyB64PrefsKey);
    final deferred = _decodeSessionKeyB64(prefs.getString(deferredPrefsKey));
    final key = deferred ?? _createSessionKey();
    await prefs.setString(defaultPrefsKey, base64Encode(key));
    await prefs.remove(deferredPrefsKey);
    return Uint8List.fromList(key);
  }

  @override
  Future<Uint8List> ensureSessionKey() async {
    final appDir = await _getAppDir();
    final prefs = await SharedPreferences.getInstance();
    final key = await _loadOrCreateDefaultSessionKey(prefs);
    return _dartAuthInitMasterPasswordWithExistingKey(
      appDir: appDir,
      password: _kInternalSessionPassword,
      key: key,
    );
  }

  @override
  Future<Uint8List> initMasterPassword(String password) async {
    final appDir = await _getAppDir();
    final prefs = await SharedPreferences.getInstance();
    final deferredPrefsKey = _scopedPrefsKey(_kDeferredSessionKeyB64PrefsKey);
    final deferred = _decodeSessionKeyB64(prefs.getString(deferredPrefsKey));
    final key = deferred == null
        ? await _dartAuthInitMasterPassword(
            appDir: appDir,
            password: password,
          )
        : await _dartAuthInitMasterPasswordWithExistingKey(
            appDir: appDir,
            password: password,
            key: deferred,
          );
    await prefs.remove(deferredPrefsKey);
    return key;
  }

  String _scopedPrefsKey(String key) {
    final storageScope = _storageScope;
    if (storageScope == null) return key;
    return '$key::$storageScope';
  }

  static String? _normalizeStorageScope(String? storageScope) {
    final normalized = storageScope?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  @override
  Future<Uint8List> unlockWithPassword(String password) async {
    final appDir = await _getAppDir();
    return _dartAuthUnlockWithPassword(appDir: appDir, password: password);
  }

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbListConversations(appDir: appDir, key: key);
  }

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async {
    final appDir = await _getAppDir();
    return _dartDbGetOrCreateLoopHomeConversation(appDir: appDir, key: key);
  }

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async {
    final appDir = await _getAppDir();
    return _dartDbCreateConversation(
      appDir: appDir,
      key: key,
      title: title,
    );
  }

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    final appDir = await _getAppDir();
    return _dartDbListMessages(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
    );
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    return _dartDbGetMessageById(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  @override
  Future<List<Message>> listMessagesPage(
    Uint8List key,
    String conversationId, {
    int? beforeCreatedAtMs,
    String? beforeId,
    int limit = 60,
  }) async {
    final appDir = await _getAppDir();
    return _dartDbListMessagesPage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      beforeCreatedAtMs: beforeCreatedAtMs == null
          ? null
          : PlatformInt64Util.from(beforeCreatedAtMs),
      beforeId: beforeId,
      limit: limit,
    );
  }

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    final message = await _dbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: role,
      content: content,
    );

    return message;
  }

  @override
  Future<Message> insertAssistantMessageWithCitations(
    Uint8List key,
    String conversationId, {
    required String content,
    String? citationsJson,
  }) async {
    final appDir = await _getAppDir();
    return _dbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: 'assistant',
      content: content,
      citationsJson: citationsJson,
    );
  }

  @override
  Future<bool> applyDetachedAskCompletionOnce(
    Uint8List key, {
    required String requestId,
    required String conversationId,
    required String question,
    required String answer,
    String? citationsJson,
  }) async {
    final appDir = await _getAppDir();
    final state = _dartNativeRuntimeStateFor(appDir);
    _dartRuntimeValidateKey(state, key);
    if (state.detachedAskCompletionRequestIds.contains(requestId)) {
      return false;
    }
    state.detachedAskCompletionRequestIds.add(requestId);
    await _dartDbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: 'user',
      content: question,
    );
    await _dartDbInsertMessage(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      role: 'assistant',
      content: answer,
      citationsJson: citationsJson,
    );
    return true;
  }
}
