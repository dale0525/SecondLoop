import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../cloud/http_client_factory_stub.dart'
    if (dart.library.io) '../cloud/http_client_factory_io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../features/actions/todo/todo_thread_match.dart';
import '../storage/secure_blob_store.dart';
import '../../src/rust/api/content_extract.dart' as rust_content_extract;
import '../../src/rust/api/embedding_lifecycle.dart'
    as rust_embedding_lifecycle;
import '../../src/rust/api/external_import.dart' as rust_external_import;
import '../../src/rust/api/migration_archive.dart' as rust_migration_archive;
import '../../src/rust/api/core.dart' as rust_core;
import '../../src/rust/api/detached_ask.dart' as rust_detached_ask;
import '../../src/rust/api/semantic_parse_enhancement.dart'
    as rust_semantic_parse_enhancement;
import '../../src/rust/api/semantic_parse_jobs.dart'
    as rust_semantic_parse_jobs;
import '../../src/rust/api/todo_followup_generation.dart'
    as rust_todo_followup_generation;
import '../../src/rust/api/attachments.dart' as rust_attachments;
import '../../src/rust/api/ask_scope.dart' as rust_ask_scope;
import '../../src/rust/api/sync_diagnostics.dart' as rust_sync_diagnostics;
import '../../src/rust/api/sync_progress.dart' as rust_sync_progress;
import '../../src/rust/db.dart';
import '../../src/rust/frb_generated.dart';
import '../../src/rust/semantic_parse.dart';
import '../secretary/todo_command_executor.dart';
import '../secretary/todo_command_models.dart';
import 'app_backend.dart';
import 'attachments_backend.dart';
import 'semantic_parse_attempt_aware_backend.dart';
import 'semantic_parse_enhancement_backend.dart';
import 'secretary_backend.dart';
import '../sync/sync_config_store.dart';
import 'rust_external_library_resolver.dart';
import 'serialized_rust_handler.dart';

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
part 'native_backend_sync_migration.dart';
part 'native_backend_secretary.dart';

Future<bool> _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaimBridge({
  required String appDir,
  required List<int> key,
  required String todoId,
  required int jobStartedAtMs,
  required List<TodoFollowupSuggestionDraftInput> suggestions,
  required String source,
  String? generationKey,
}) =>
    rust_core.dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim(
      appDir: appDir,
      key: key,
      todoId: todoId,
      jobStartedAtMs: PlatformInt64Util.from(jobStartedAtMs),
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );

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

typedef RustLibInitFn = Future<void> Function();

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
  return rust_ask_scope.ragAskAiStreamScoped(
    appDir: appDir,
    key: key,
    conversationId: conversationId,
    question: question,
    topK: topK,
    thisThreadOnly: thisThreadOnly,
    timeStartMs:
        timeStartMs == null ? null : PlatformInt64Util.from(timeStartMs),
    timeEndMs: timeEndMs == null ? null : PlatformInt64Util.from(timeEndMs),
    includeTagIds: includeTagIds,
    excludeTagIds: excludeTagIds,
    strictMode: strictMode,
    localeLanguage: localeLanguage,
    localDay: localDay,
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
  return rust_ask_scope.ragAskAiStreamCloudGatewayScoped(
    appDir: appDir,
    key: key,
    conversationId: conversationId,
    question: question,
    topK: topK,
    thisThreadOnly: thisThreadOnly,
    timeStartMs:
        timeStartMs == null ? null : PlatformInt64Util.from(timeStartMs),
    timeEndMs: timeEndMs == null ? null : PlatformInt64Util.from(timeEndMs),
    includeTagIds: includeTagIds,
    excludeTagIds: excludeTagIds,
    strictMode: strictMode,
    localeLanguage: localeLanguage,
    gatewayBaseUrl: gatewayBaseUrl,
    firebaseIdToken: firebaseIdToken,
    modelName: modelName,
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
        _NativeAppBackendSyncMigration,
        _NativeAppBackendSecretary
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
    bool recoverInterruptedExternalImportBatchesOnInit = true,
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
    RustLibInitFn? rustLibInit,
  })  : _storageScope = _normalizeStorageScope(storageScope),
        _secureBlobStore = SecureBlobStore(
          storage: secureStorage,
          scopeKey: _normalizeStorageScope(storageScope),
        ),
        _appDirProvider = appDirProvider ?? _defaultAppDirProvider,
        _dbListTodos = dbListTodos ?? rust_core.dbListTodos,
        _dbGetTodoById = dbGetTodoById ?? rust_core.dbGetTodoById,
        _dbUpsertTodoWithAutoFollowupJob =
            _resolveDbUpsertTodoWithAutoFollowupJob(
          dbUpsertTodoWithAutoFollowupJob: dbUpsertTodoWithAutoFollowupJob,
          dbUpsertTodo: dbUpsertTodo,
          dbEnqueueTodoFollowupGenerationJob:
              dbEnqueueTodoFollowupGenerationJob,
        ),
        _dbInsertMessage = dbInsertMessage ?? rust_core.dbInsertMessage,
        _dbInsertAttachment =
            dbInsertAttachment ?? rust_core.dbInsertAttachment,
        _dbProcessPendingMessageEmbeddings =
            dbProcessPendingMessageEmbeddings ??
                rust_core.dbProcessPendingMessageEmbeddings,
        _dbReleaseLocalEmbeddingModelIfIdle =
            dbReleaseLocalEmbeddingModelIfIdle ??
                rust_embedding_lifecycle.dbReleaseLocalEmbeddingModelIfIdle,
        _askAiStreamScoped = askAiStreamScopedFn ?? _ragAskAiStreamScopedCompat,
        _askAiStreamCloudGatewayScoped = askAiStreamCloudGatewayScopedFn ??
            _ragAskAiStreamCloudGatewayScopedCompat,
        _dbCreateTodoChecklistItem =
            dbCreateTodoChecklistItem ?? rust_core.dbCreateTodoChecklistItem,
        _dbListTodoChecklistItems =
            dbListTodoChecklistItems ?? rust_core.dbListTodoChecklistItems,
        _dbUpdateTodoChecklistItemContent = dbUpdateTodoChecklistItemContent ??
            rust_core.dbUpdateTodoChecklistItemContent,
        _dbSetTodoChecklistItemDone =
            dbSetTodoChecklistItemDone ?? rust_core.dbSetTodoChecklistItemDone,
        _dbDeleteTodoChecklistItem =
            dbDeleteTodoChecklistItem ?? rust_core.dbDeleteTodoChecklistItem,
        _dbReorderTodoChecklistItems = dbReorderTodoChecklistItems ??
            rust_core.dbReorderTodoChecklistItems,
        _dbListTodoChecklistProgress = dbListTodoChecklistProgress ??
            rust_core.dbListTodoChecklistProgress,
        _dbListTodoChecklistSuggestions = dbListTodoChecklistSuggestions ??
            rust_core.dbListTodoChecklistSuggestions,
        _dbUpsertGeneratedTodoChecklistSuggestions =
            dbUpsertGeneratedTodoChecklistSuggestions ??
                rust_core.dbUpsertGeneratedTodoChecklistSuggestions,
        _dbApplyTodoChecklistSuggestions = dbApplyTodoChecklistSuggestions ??
            rust_core.dbApplyTodoChecklistSuggestions,
        _dbDismissTodoChecklistSuggestions =
            dbDismissTodoChecklistSuggestions ??
                rust_core.dbDismissTodoChecklistSuggestions,
        _dbDismissAllTodoChecklistSuggestions =
            dbDismissAllTodoChecklistSuggestions ??
                rust_core.dbDismissAllTodoChecklistSuggestions,
        _dbListTodoFollowupSuggestions = dbListTodoFollowupSuggestions ??
            rust_core.dbListTodoFollowupSuggestions,
        _dbUpsertGeneratedTodoFollowupSuggestions =
            dbUpsertGeneratedTodoFollowupSuggestions ??
                rust_core.dbUpsertGeneratedTodoFollowupSuggestions,
        _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim =
            dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaim ??
                _dbUpsertGeneratedTodoFollowupSuggestionsIfCurrentClaimBridge,
        _dbApplyTodoFollowupSuggestions = dbApplyTodoFollowupSuggestions ??
            rust_core.dbApplyTodoFollowupSuggestions,
        _dbDismissTodoFollowupSuggestions = dbDismissTodoFollowupSuggestions ??
            rust_core.dbDismissTodoFollowupSuggestions,
        _dbDismissAllTodoFollowupSuggestions =
            dbDismissAllTodoFollowupSuggestions ??
                rust_core.dbDismissAllTodoFollowupSuggestions,
        _dbEnqueueTodoFollowupGenerationJob =
            dbEnqueueTodoFollowupGenerationJob ??
                rust_core.dbEnqueueTodoFollowupGenerationJob,
        _dbListDueTodoFollowupGenerationJobs =
            dbListDueTodoFollowupGenerationJobs ??
                rust_core.dbListDueTodoFollowupGenerationJobs,
        _dbListDueAutoTodoFollowupGenerationJobs =
            dbListDueAutoTodoFollowupGenerationJobs ??
                rust_todo_followup_generation
                    .dbListDueAutoTodoFollowupGenerationJobs,
        _dbGetTodoFollowupGenerationJob = dbGetTodoFollowupGenerationJob ??
            rust_core.dbGetTodoFollowupGenerationJob,
        _dbMarkTodoFollowupGenerationJobRunning =
            dbMarkTodoFollowupGenerationJobRunning ??
                rust_core.dbMarkTodoFollowupGenerationJobRunning,
        _dbMarkTodoFollowupGenerationJobFailed =
            dbMarkTodoFollowupGenerationJobFailed ??
                rust_core.dbMarkTodoFollowupGenerationJobFailed,
        _dbMarkTodoFollowupGenerationJobSucceeded =
            dbMarkTodoFollowupGenerationJobSucceeded ??
                rust_core.dbMarkTodoFollowupGenerationJobSucceeded,
        _dbMarkTodoFollowupGenerationJobSkipped =
            dbMarkTodoFollowupGenerationJobSkipped ??
                rust_core.dbMarkTodoFollowupGenerationJobSkipped,
        _dbMarkTodoFollowupGenerationJobCanceled =
            dbMarkTodoFollowupGenerationJobCanceled ??
                rust_core.dbMarkTodoFollowupGenerationJobCanceled,
        _dbCreateSecretaryMemoryProposal = dbCreateSecretaryMemoryProposal ??
            rust_core.dbCreateSecretaryMemoryProposal,
        _dbListSecretaryMemoryProposals = dbListSecretaryMemoryProposals ??
            rust_core.dbListSecretaryMemoryProposals,
        _dbAcceptSecretaryMemoryProposal = dbAcceptSecretaryMemoryProposal ??
            rust_core.dbAcceptSecretaryMemoryProposal,
        _dbDismissSecretaryMemoryProposal = dbDismissSecretaryMemoryProposal ??
            rust_core.dbDismissSecretaryMemoryProposal,
        _dbListMemoryPages = dbListMemoryPages ?? rust_core.dbListMemoryPages,
        _dbGetMemoryPage = dbGetMemoryPage ?? rust_core.dbGetMemoryPage,
        _dbCorrectMemoryPage =
            dbCorrectMemoryPage ?? rust_core.dbCorrectMemoryPage,
        _dbArchiveMemoryPage =
            dbArchiveMemoryPage ?? rust_core.dbArchiveMemoryPage,
        _dbRestoreMemoryPage =
            dbRestoreMemoryPage ?? rust_core.dbRestoreMemoryPage,
        _dbUpsertPlanningOutput =
            dbUpsertPlanningOutput ?? rust_core.dbUpsertPlanningOutput,
        _dbListPlanningOutputs =
            dbListPlanningOutputs ?? rust_core.dbListPlanningOutputs,
        _dbCreateSecretaryRun =
            dbCreateSecretaryRun ?? rust_core.dbCreateSecretaryRun,
        _dbCreateSecretaryToolCall =
            dbCreateSecretaryToolCall ?? rust_core.dbCreateSecretaryToolCall,
        _dbListSecretaryToolCallsForRun = dbListSecretaryToolCallsForRun ??
            rust_core.dbListSecretaryToolCallsForRun,
        _recoverInterruptedExternalImportBatchesOnInit =
            recoverInterruptedExternalImportBatchesOnInit,
        _rustLibInit = rustLibInit ??
            (() => RustLib.init(
                  handler: kIsWeb ? SerializedRustHandler() : null,
                  externalLibrary: resolveDesktopRustExternalLibrary(),
                ));

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
  final DbCreateSecretaryMemoryProposalFn _dbCreateSecretaryMemoryProposal;
  @override
  final DbListSecretaryMemoryProposalsFn _dbListSecretaryMemoryProposals;
  @override
  final DbAcceptSecretaryMemoryProposalFn _dbAcceptSecretaryMemoryProposal;
  @override
  final DbDismissSecretaryMemoryProposalFn _dbDismissSecretaryMemoryProposal;
  @override
  final DbListMemoryPagesFn _dbListMemoryPages;
  @override
  final DbGetMemoryPageFn _dbGetMemoryPage;
  @override
  final DbCorrectMemoryPageFn _dbCorrectMemoryPage;
  @override
  final DbSetMemoryPageStateFn _dbArchiveMemoryPage;
  @override
  final DbSetMemoryPageStateFn _dbRestoreMemoryPage;
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
  final bool _recoverInterruptedExternalImportBatchesOnInit;
  final RustLibInitFn _rustLibInit;

  String? _appDir;

  static String _formatLocalDayKey(DateTime value) {
    final dt = value.toLocal();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static const _kAutoUnlockEnabled = 'auto_unlock_enabled';
  static const _kSessionKeyB64 = 'session_key_b64';

  static const _kDeferredSessionKeyB64PrefsKey = 'deferred_session_key_b64_v1';

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
    await _rustLibInit();
    await _getAppDir();
    if (_recoverInterruptedExternalImportBatchesOnInit) {
      await _recoverInterruptedExternalImportBatches();
    }
  }

  Future<void> _recoverInterruptedExternalImportBatches() async {
    final batches = await listExternalImportBatches();
    for (final batch in batches) {
      if (!_isInterruptedExternalImportStatus(batch.status)) {
        continue;
      }
      await deleteExternalImportBatch(batchId: batch.batchId);
    }
  }

  static bool _isInterruptedExternalImportStatus(String status) {
    return switch (status.trim()) {
      'in_progress' || 'cancelling' || 'rollback' => true,
      _ => false,
    };
  }

  @override
  Future<bool> isMasterPasswordSet() async {
    final appDir = await _getAppDir();
    return rust_core.authIsInitialized(appDir: appDir);
  }

  @override
  Future<bool> readAutoUnlockEnabled() async {
    if (_isMacNoKeychain) return false;

    final value = await _secureBlobStore.readValue(_kAutoUnlockEnabled);
    if (value != null) return value == '1';

    final legacy = await _secureBlobStore.readKey(_kAutoUnlockEnabled);
    if (legacy == null || legacy.isEmpty) return true;

    await _secureBlobStore.update({_kAutoUnlockEnabled: legacy});
    await _secureBlobStore.deleteKey(_kAutoUnlockEnabled);
    return legacy == '1';
  }

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {
    if (_isMacNoKeychain) return;

    final updates = <String, String?>{
      _kAutoUnlockEnabled: enabled ? '1' : '0',
    };
    if (!enabled) {
      updates[_kSessionKeyB64] = null;
    }
    await _secureBlobStore.update(updates);
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
      _kAutoUnlockEnabled: '1',
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
    await rust_core.authValidateKey(appDir: appDir, key: key);
  }

  @override
  Future<Uint8List> initMasterPassword(String password) async {
    final appDir = await _getAppDir();
    final prefs = await SharedPreferences.getInstance();
    final deferredPrefsKey = _scopedPrefsKey(_kDeferredSessionKeyB64PrefsKey);
    final deferredB64 = prefs.getString(deferredPrefsKey);

    Future<Uint8List> init() async {
      if (deferredB64 == null || deferredB64.isEmpty) {
        return rust_core.authInitMasterPassword(
          appDir: appDir,
          password: password,
        );
      }

      try {
        final deferred = base64Decode(deferredB64);
        if (deferred.length != 32) {
          await prefs.remove(deferredPrefsKey);
          return rust_core.authInitMasterPassword(
            appDir: appDir,
            password: password,
          );
        }

        return rust_core.authInitMasterPasswordWithExistingKey(
          appDir: appDir,
          password: password,
          key: deferred,
        );
      } catch (_) {
        await prefs.remove(deferredPrefsKey);
        return rust_core.authInitMasterPassword(
          appDir: appDir,
          password: password,
        );
      }
    }

    final key = await init();
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
    return rust_core.authUnlockWithPassword(appDir: appDir, password: password);
  }

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListConversations(appDir: appDir, key: key);
  }

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetOrCreateLoopHomeConversation(
        appDir: appDir, key: key);
  }

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async {
    final appDir = await _getAppDir();
    return rust_core.dbCreateConversation(
        appDir: appDir, key: key, title: title);
  }

  @override
  Future<List<Message>> listMessages(
      Uint8List key, String conversationId) async {
    final appDir = await _getAppDir();
    return rust_core.dbListMessages(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
    );
  }

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetMessageById(
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
    return rust_core.dbListMessagesPage(
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
    return rust_detached_ask.dbApplyDetachedAskCompletionOnce(
      appDir: appDir,
      key: key,
      requestId: requestId,
      conversationId: conversationId,
      question: question,
      answer: answer,
      citationsJson: citationsJson,
    );
  }
}
