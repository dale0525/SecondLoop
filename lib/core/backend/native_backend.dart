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
import '../../src/rust/api/knowledge.dart' as rust_knowledge;
import '../../src/rust/api/core.dart' as rust_core;
import '../../src/rust/api/todo_followup_generation.dart'
    as rust_todo_followup_generation;
import '../../src/rust/knowledge/models.dart' as rust_knowledge_models;
import '../../src/rust/api/attachments.dart' as rust_attachments;
import '../../src/rust/api/ask_scope.dart' as rust_ask_scope;
import '../../src/rust/api/sync_progress.dart' as rust_sync_progress;
import '../../src/rust/db.dart';
import '../../src/rust/frb_generated.dart';
import '../../src/rust/semantic_parse.dart';
import 'app_backend.dart';
import 'attachments_backend.dart';
import 'semantic_parse_attempt_aware_backend.dart';
import 'rust_external_library_resolver.dart';

part 'native_backend_knowledge.dart';
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
        _NativeAppBackendSyncMigration
    implements
        AppBackend,
        AttachmentsBackend,
        AttachmentAnnotationMutationsBackend,
        SemanticParseAttemptAwareBackend {
  @override
  bool get supportsTodoFollowupSuggestions => true;

  @override
  bool get autoEnqueuesTodoFollowupGenerationOnCreate => true;

  NativeAppBackend({
    FlutterSecureStorage? secureStorage,
    AppDirProvider? appDirProvider,
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
    RustLibInitFn? rustLibInit,
  })  : _secureBlobStore = SecureBlobStore(storage: secureStorage),
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
        _rustLibInit = rustLibInit ??
            (() => RustLib.init(
                  externalLibrary: resolveDesktopRustExternalLibrary(),
                ));

  final SecureBlobStore _secureBlobStore;
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

  @override
  Future<void> init() async {
    await _rustLibInit();
    await _getAppDir();
    await _recoverInterruptedExternalImportBatches();
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
    final deferredB64 = prefs.getString(_kDeferredSessionKeyB64PrefsKey);

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
          await prefs.remove(_kDeferredSessionKeyB64PrefsKey);
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
        await prefs.remove(_kDeferredSessionKeyB64PrefsKey);
        return rust_core.authInitMasterPassword(
          appDir: appDir,
          password: password,
        );
      }
    }

    final key = await init();
    await prefs.remove(_kDeferredSessionKeyB64PrefsKey);
    return key;
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
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final appDir = await _getAppDir();
    return _dbInsertAttachment(
      appDir: appDir,
      key: key,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  @override
  Future<void> upsertAttachmentDerivation(
    Uint8List key, {
    required String rootSha256,
    required String childSha256,
    required String role,
    required int createdAtMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpsertAttachmentDerivation(
      appDir: appDir,
      key: key,
      rootSha256: rootSha256,
      childSha256: childSha256,
      role: role,
      createdAtMs: PlatformInt64Util.from(createdAtMs),
    );
  }

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListRecentAttachments(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbLinkAttachmentToMessage(
      appDir: appDir,
      key: key,
      messageId: messageId,
      attachmentSha256: attachmentSha256,
    );
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
      Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    return rust_core.dbListMessageAttachments(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentBytes(
      appDir: appDir,
      key: key,
      sha256: sha256,
    );
  }

  @override
  Future<void> upsertAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
    int? capturedAtMs,
    double? latitude,
    double? longitude,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpsertAttachmentExifMetadata(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
      capturedAtMs:
          capturedAtMs == null ? null : PlatformInt64Util.from(capturedAtMs),
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentExifMetadata(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentPlaceDisplayName(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentAnnotationCaptionLong(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<String?> readAttachmentAnnotationPayloadJson(
    Uint8List key, {
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbReadAttachmentAnnotationPayloadJson(
      appDir: appDir,
      key: key,
      attachmentSha256: sha256,
    );
  }

  @override
  Future<void> enqueueAttachmentPlace(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueAttachmentPlace(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> enqueueAttachmentAnnotation(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueAttachmentAnnotation(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<AttachmentPlaceJob>> listDueAttachmentPlaces(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueAttachmentPlaces(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<List<AttachmentAnnotationJob>> listDueAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueAttachmentAnnotations(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<List<AttachmentAnnotationJob>> listDueImageAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbListDueImageAttachmentAnnotations(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<List<AttachmentAnnotationJob>> listDueUrlManifestAttachmentAnnotations(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbListDueUrlManifestAttachmentAnnotations(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<int> processPendingDocumentExtractions(
    Uint8List key, {
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_content_extract.dbProcessPendingDocumentExtractions(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  @override
  Future<void> markAttachmentPlaceFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentPlaceFailed(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markAttachmentAnnotationFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentAnnotationFailed(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markAttachmentPlaceOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String payloadJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentPlaceOkJson(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      payloadJson: payloadJson,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markAttachmentAnnotationOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkAttachmentAnnotationOkJson(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      lang: lang,
      modelName: modelName,
      payloadJson: payloadJson,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<String> geoReverseCloudGateway({
    required String gatewayBaseUrl,
    required String idToken,
    required double lat,
    required double lon,
    required String lang,
  }) async {
    return rust_core.geoReverseCloudGateway(
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      lat: lat,
      lon: lon,
      lang: lang,
    );
  }

  @override
  Future<String> mediaAnnotationCloudGateway({
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String lang,
    required String mimeType,
    required Uint8List imageBytes,
  }) async {
    return rust_core.mediaAnnotationCloudGateway(
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      lang: lang,
      mimeType: mimeType,
      imageBytes: imageBytes,
    );
  }

  @override
  Future<void> editMessage(
      Uint8List key, String messageId, String content) async {
    final appDir = await _getAppDir();
    await rust_core.dbEditMessage(
      appDir: appDir,
      key: key,
      messageId: messageId,
      content: content,
    );
  }

  @override
  Future<void> setMessageDeleted(
      Uint8List key, String messageId, bool isDeleted) async {
    final appDir = await _getAppDir();
    await rust_core.dbSetMessageDeleted(
      appDir: appDir,
      key: key,
      messageId: messageId,
      isDeleted: isDeleted,
    );
  }

  @override
  Future<void> purgeMessageAttachments(Uint8List key, String messageId) async {
    final appDir = await _getAppDir();
    await rust_core.dbPurgeMessageAttachments(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.dbResetVaultDataPreservingLlmProfiles(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<void> clearLocalAttachmentCache(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.dbClearLocalAttachmentCache(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async {
    final appDir = await _getAppDir();
    return rust_attachments.dbReadAttachmentBySha256(
      appDir: appDir,
      attachmentSha256: attachmentSha256,
    );
  }

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListTodos(appDir: appDir, key: key);
  }

  @override
  Future<List<Todo>> listTodosCreatedInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListTodosCreatedInRange(
      appDir: appDir,
      key: key,
      startAtMsInclusive: PlatformInt64Util.from(startAtMsInclusive),
      endAtMsExclusive: PlatformInt64Util.from(endAtMsExclusive),
    );
  }

  @override
  Future<Todo> setTodoStatus(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetTodoStatus(
      appDir: appDir,
      key: key,
      todoId: todoId,
      newStatus: newStatus,
      sourceMessageId: sourceMessageId,
    );
  }

  @override
  Future<Todo> transitionTodo(
    Uint8List key, {
    required String todoId,
    String? newStatus,
    int? dueAtMs,
    bool clearDueAtMs = false,
    int? reviewStage,
    bool clearReviewStage = false,
    int? nextReviewAtMs,
    bool clearNextReviewAtMs = false,
    int? lastReviewAtMs,
    bool clearLastReviewAtMs = false,
    int? manualImportanceNudgeScore,
    bool clearManualImportanceNudgeScore = false,
    int? manualUrgencyNudgeScore,
    bool clearManualUrgencyNudgeScore = false,
    String? sourceMessageId,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbTransitionTodo(
      appDir: appDir,
      key: key,
      todoId: todoId,
      newStatus: newStatus,
      dueAtMs: dueAtMs == null ? null : PlatformInt64Util.from(dueAtMs),
      clearDueAtMs: clearDueAtMs,
      reviewStage:
          reviewStage == null ? null : PlatformInt64Util.from(reviewStage),
      clearReviewStage: clearReviewStage,
      nextReviewAtMs: nextReviewAtMs == null
          ? null
          : PlatformInt64Util.from(nextReviewAtMs),
      clearNextReviewAtMs: clearNextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs == null
          ? null
          : PlatformInt64Util.from(lastReviewAtMs),
      clearLastReviewAtMs: clearLastReviewAtMs,
      manualImportanceNudgeScore: manualImportanceNudgeScore == null
          ? null
          : PlatformInt64Util.from(manualImportanceNudgeScore),
      clearManualImportanceNudgeScore: clearManualImportanceNudgeScore,
      manualUrgencyNudgeScore: manualUrgencyNudgeScore == null
          ? null
          : PlatformInt64Util.from(manualUrgencyNudgeScore),
      clearManualUrgencyNudgeScore: clearManualUrgencyNudgeScore,
      sourceMessageId: sourceMessageId,
    );
  }

  @override
  Future<Todo> updateTodoStatusWithScope(
    Uint8List key, {
    required String todoId,
    required String newStatus,
    String? sourceMessageId,
    required TodoRecurrenceEditScope scope,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbUpdateTodoStatusWithScope(
      appDir: appDir,
      key: key,
      todoId: todoId,
      newStatus: newStatus,
      sourceMessageId: sourceMessageId,
      scope: scope.wireValue,
    );
  }

  @override
  Future<Todo> updateTodoDueWithScope(
    Uint8List key, {
    required String todoId,
    required int dueAtMs,
    required TodoRecurrenceEditScope scope,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbUpdateTodoDueWithScope(
      appDir: appDir,
      key: key,
      todoId: todoId,
      dueAtMs: PlatformInt64Util.from(dueAtMs),
      scope: scope.wireValue,
    );
  }

  @override
  Future<void> upsertTodoRecurrence(
    Uint8List key, {
    required String todoId,
    required String seriesId,
    required String ruleJson,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpsertTodoRecurrence(
      appDir: appDir,
      key: key,
      todoId: todoId,
      seriesId: seriesId,
      ruleJson: ruleJson,
    );
  }

  @override
  Future<String?> getTodoRecurrenceRuleJson(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetTodoRecurrenceRuleJson(
      appDir: appDir,
      todoId: todoId,
    );
  }

  @override
  Future<void> updateTodoRecurrenceRuleWithScope(
    Uint8List key, {
    required String todoId,
    required String ruleJson,
    required TodoRecurrenceEditScope scope,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbUpdateTodoRecurrenceRuleWithScope(
      appDir: appDir,
      key: key,
      todoId: todoId,
      ruleJson: ruleJson,
      scope: scope.wireValue,
    );
  }

  @override
  Future<void> deleteTodo(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbDeleteTodoAndAssociatedMessages(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<TodoActivity> appendTodoNote(
    Uint8List key, {
    required String todoId,
    required String content,
    String? sourceMessageId,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbAppendTodoNote(
      appDir: appDir,
      key: key,
      todoId: todoId,
      content: content,
      sourceMessageId: sourceMessageId,
    );
  }

  @override
  Future<TodoActivity> moveTodoActivity(
    Uint8List key, {
    required String activityId,
    required String toTodoId,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbMoveTodoActivity(
      appDir: appDir,
      key: key,
      activityId: activityId,
      toTodoId: toTodoId,
    );
  }

  @override
  Future<TodoChecklistItem> createTodoChecklistItem(
    Uint8List key, {
    required String todoId,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    return _dbCreateTodoChecklistItem(
      appDir: appDir,
      key: key,
      todoId: todoId,
      content: content,
    );
  }

  @override
  Future<List<TodoChecklistItem>> listTodoChecklistItems(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoChecklistItems(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<TodoChecklistItem> updateTodoChecklistItemContent(
    Uint8List key, {
    required String itemId,
    required String content,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpdateTodoChecklistItemContent(
      appDir: appDir,
      key: key,
      itemId: itemId,
      content: content,
    );
  }

  @override
  Future<TodoChecklistItem> setTodoChecklistItemDone(
    Uint8List key, {
    required String itemId,
    required bool isDone,
  }) async {
    final appDir = await _getAppDir();
    return _dbSetTodoChecklistItemDone(
      appDir: appDir,
      key: key,
      itemId: itemId,
      isDone: isDone,
    );
  }

  @override
  Future<void> deleteTodoChecklistItem(
    Uint8List key, {
    required String itemId,
  }) async {
    final appDir = await _getAppDir();
    await _dbDeleteTodoChecklistItem(
      appDir: appDir,
      key: key,
      itemId: itemId,
    );
  }

  @override
  Future<void> reorderTodoChecklistItems(
    Uint8List key, {
    required String todoId,
    required List<String> orderedItemIds,
  }) async {
    final appDir = await _getAppDir();
    await _dbReorderTodoChecklistItems(
      appDir: appDir,
      key: key,
      todoId: todoId,
      orderedItemIds: orderedItemIds,
    );
  }

  @override
  Future<List<TodoChecklistProgress>> listTodoChecklistProgress(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoChecklistProgress(appDir: appDir, key: key);
  }

  @override
  Future<List<TodoChecklistSuggestion>> listTodoChecklistSuggestions(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return _dbListTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<List<TodoChecklistSuggestion>> upsertGeneratedTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  }) async {
    final appDir = await _getAppDir();
    return _dbUpsertGeneratedTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );
  }

  @override
  Future<List<TodoChecklistItem>> applyTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final appDir = await _getAppDir();
    return _dbApplyTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<void> dismissTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
    required List<String> suggestionIds,
  }) async {
    final appDir = await _getAppDir();
    await _dbDismissTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<void> dismissAllTodoChecklistSuggestions(
    Uint8List key, {
    required String todoId,
  }) async {
    final appDir = await _getAppDir();
    await _dbDismissAllTodoChecklistSuggestions(
      appDir: appDir,
      key: key,
      todoId: todoId,
    );
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async {
    final appDir = await _getAppDir();
    return rust_core.dbListTodoActivities(
        appDir: appDir, key: key, todoId: todoId);
  }

  @override
  Future<List<TodoActivity>> listTodoActivitiesInRange(
    Uint8List key, {
    required int startAtMsInclusive,
    required int endAtMsExclusive,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListTodoActivitiesInRange(
      appDir: appDir,
      key: key,
      startAtMsInclusive: PlatformInt64Util.from(startAtMsInclusive),
      endAtMsExclusive: PlatformInt64Util.from(endAtMsExclusive),
    );
  }

  @override
  Future<void> linkAttachmentToTodoActivity(
    Uint8List key, {
    required String activityId,
    required String attachmentSha256,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbLinkAttachmentToTodoActivity(
      appDir: appDir,
      key: key,
      activityId: activityId,
      attachmentSha256: attachmentSha256,
    );
  }

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async {
    final appDir = await _getAppDir();
    return rust_core.dbListTodoActivityAttachments(
      appDir: appDir,
      key: key,
      activityId: activityId,
    );
  }

  @override
  Future<List<Event>> listEvents(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListEvents(appDir: appDir, key: key);
  }

  @override
  Future<Event> upsertEvent(
    Uint8List key, {
    required String id,
    required String title,
    required int startAtMs,
    required int endAtMs,
    required String tz,
    String? sourceEntryId,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbUpsertEvent(
      appDir: appDir,
      key: key,
      id: id,
      title: title,
      startAtMs: PlatformInt64Util.from(startAtMs),
      endAtMs: PlatformInt64Util.from(endAtMs),
      tz: tz,
      sourceEntryId: sourceEntryId,
    );
  }

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async {
    final appDir = await _getAppDir();
    return _dbProcessPendingMessageEmbeddings(
      appDir: appDir,
      key: key,
      limit: limit,
    );
  }

  @override
  Future<bool> releaseLocalEmbeddingModelIfIdle(
    Uint8List key, {
    int maxIdleMs = 180000,
  }) async {
    final appDir = await _getAppDir();
    return _dbReleaseLocalEmbeddingModelIfIdle(
      appDir: appDir,
      key: key,
      maxIdleMs: maxIdleMs,
    );
  }

  @override
  Future<int> processPendingTodoThreadEmbeddings(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbProcessPendingTodoThreadEmbeddings(
      appDir: appDir,
      key: key,
      todoLimit: todoLimit,
      activityLimit: activityLimit,
    );
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsCloudGateway(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbProcessPendingTodoThreadEmbeddingsCloudGateway(
      appDir: appDir,
      key: key,
      todoLimit: todoLimit,
      activityLimit: activityLimit,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<int> processPendingTodoThreadEmbeddingsBrok(
    Uint8List key, {
    int todoLimit = 32,
    int activityLimit = 64,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbProcessPendingTodoThreadEmbeddingsBrok(
      appDir: appDir,
      key: key,
      todoLimit: todoLimit,
      activityLimit: activityLimit,
    );
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSearchSimilarMessages(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessagesCloudGateway(
    Uint8List key,
    String query, {
    int topK = 10,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSearchSimilarMessagesCloudGateway(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<List<SimilarMessage>> searchSimilarMessagesBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSearchSimilarMessagesBrok(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreads(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    final matches = await rust_core.dbSearchSimilarTodoThreads(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
    return matches
        .map(
          (m) => TodoThreadMatch(
            todoId: m.todoId,
            distance: m.distance,
          ),
        )
        .toList(growable: false);
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
    final appDir = await _getAppDir();
    final matches = await rust_core.dbSearchSimilarTodoThreadsCloudGateway(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
    return matches
        .map(
          (m) => TodoThreadMatch(
            todoId: m.todoId,
            distance: m.distance,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<TodoThreadMatch>> searchSimilarTodoThreadsBrok(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async {
    final appDir = await _getAppDir();
    final matches = await rust_core.dbSearchSimilarTodoThreadsBrok(
      appDir: appDir,
      key: key,
      query: query,
      topK: topK,
    );
    return matches
        .map(
          (m) => TodoThreadMatch(
            todoId: m.todoId,
            distance: m.distance,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbRebuildMessageEmbeddings(
      appDir: appDir,
      key: key,
      batchLimit: batchLimit,
    );
  }

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListEmbeddingModelNames(appDir: appDir, key: key);
  }

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetActiveEmbeddingModelName(appDir: appDir, key: key);
  }

  @override
  Future<bool> setActiveEmbeddingModelName(
    Uint8List key,
    String modelName,
  ) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetActiveEmbeddingModelName(
      appDir: appDir,
      key: key,
      modelName: modelName,
    );
  }

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListEmbeddingProfiles(appDir: appDir, key: key);
  }

  @override
  Future<EmbeddingProfile> createEmbeddingProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbCreateEmbeddingProfile(
      appDir: appDir,
      key: key,
      name: name,
      providerType: providerType,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelName: modelName,
      setActive: setActive,
    );
  }

  @override
  Future<void> setActiveEmbeddingProfile(
      Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetActiveEmbeddingProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<void> deleteEmbeddingProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbDeleteEmbeddingProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbListLlmProfiles(appDir: appDir, key: key);
  }

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbCreateLlmProfile(
      appDir: appDir,
      key: key,
      name: name,
      providerType: providerType,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelName: modelName,
      setActive: setActive,
    );
  }

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbSetActiveLlmProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {
    final appDir = await _getAppDir();
    return rust_core.dbDeleteLlmProfile(
      appDir: appDir,
      key: key,
      profileId: profileId,
    );
  }

  @override
  bool get supportsScopedAskAi => true;

  @override
  Future<List<LlmUsageAggregate>> sumLlmUsageDailyByPurpose(
    Uint8List key,
    String profileId, {
    required String startDay,
    required String endDay,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbSumLlmUsageDailyByPurpose(
      appDir: appDir,
      key: key,
      profileId: profileId,
      startDay: startDay,
      endDay: endDay,
    );
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStream(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStreamTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamWithBrokEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStreamWithBrokEmbeddings(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamWithBrokEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    yield* rust_core.ragAskAiStreamWithBrokEmbeddingsTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      localDay: localDay,
    );
  }

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
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGateway(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGatewayTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddings(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGatewayWithEmbeddings(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      embeddingsModelName: embeddingsModelName,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayWithEmbeddingsTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String embeddingsModelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_core.ragAskAiStreamCloudGatewayWithEmbeddingsTimeWindow(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: PlatformInt64Util.from(timeStartMs),
      timeEndMs: PlatformInt64Util.from(timeEndMs),
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      embeddingsModelName: embeddingsModelName,
    );
  }

  @override
  Stream<String> askAiStreamScoped(
    Uint8List key,
    String conversationId, {
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
  }) async* {
    final appDir = await _getAppDir();
    yield* _askAiStreamScoped(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      includeTagIds: includeTagIds,
      excludeTagIds: excludeTagIds,
      strictMode: strictMode,
      localeLanguage: localeLanguage,
      localDay: localDay,
    );
  }

  @override
  Stream<String> askAiStreamCloudGatewayScoped(
    Uint8List key,
    String conversationId, {
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
    required String idToken,
    required String modelName,
  }) async* {
    final appDir = await _getAppDir();
    yield* _askAiStreamCloudGatewayScoped(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      question: question,
      topK: topK,
      thisThreadOnly: thisThreadOnly,
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      includeTagIds: includeTagIds,
      excludeTagIds: excludeTagIds,
      strictMode: strictMode,
      localeLanguage: localeLanguage,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<String> taskPriorityRerankAi(
    Uint8List key, {
    required String prompt,
  }) async {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    return rust_core.aiTaskPriorityRerank(
      appDir: appDir,
      key: key,
      prompt: prompt,
      localDay: localDay,
    );
  }

  @override
  Future<String> taskPriorityRerankAiCloudGateway(
    Uint8List key, {
    required String prompt,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.aiTaskPriorityRerankCloudGateway(
      appDir: appDir,
      key: key,
      prompt: prompt,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  Uri _taskPriorityAssessmentsUri(String gatewayBaseUrl, String cacheScopeKey) {
    final base = gatewayBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/task-priority/assessments')
        .replace(queryParameters: <String, String>{'scope': cacheScopeKey});
  }

  Future<String> _sendTaskPriorityAssessmentRequest(
    String method, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    String? payloadJson,
  }) async {
    final http.Client client = createPlatformHttpClient();
    try {
      final uri = _taskPriorityAssessmentsUri(gatewayBaseUrl, cacheScopeKey);
      final headers = <String, String>{
        'authorization': 'Bearer $idToken',
        'accept': 'application/json',
        if (method == 'POST') 'content-type': 'application/json',
      };
      final response = method == 'GET'
          ? await client.get(uri, headers: headers)
          : await client.post(uri, headers: headers, body: payloadJson ?? '{}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'task_priority_assessment_http_${response.statusCode}');
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  @override
  Future<String> fetchTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
  }) {
    return _sendTaskPriorityAssessmentRequest(
      'GET',
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      cacheScopeKey: cacheScopeKey,
    );
  }

  @override
  Future<void> upsertTaskPriorityAiAssessmentsCloudGateway(
    Uint8List key, {
    required String gatewayBaseUrl,
    required String idToken,
    required String cacheScopeKey,
    required String payloadJson,
  }) async {
    await _sendTaskPriorityAssessmentRequest(
      'POST',
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      cacheScopeKey: cacheScopeKey,
      payloadJson: payloadJson,
    );
  }

  @override
  Future<String> semanticParseMessageAction(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<TodoCandidate> candidates,
  }) async {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    return rust_core.aiSemanticParseMessageAction(
      appDir: appDir,
      key: key,
      text: text,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      dayEndMinutes: dayEndMinutes,
      candidates: candidates,
      localDay: localDay,
    );
  }

  @override
  Future<String> semanticParseMessageActionCloudGateway(
    Uint8List key, {
    required String text,
    required String nowLocalIso,
    required Locale locale,
    required int dayEndMinutes,
    required List<TodoCandidate> candidates,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.aiSemanticParseMessageActionCloudGateway(
      appDir: appDir,
      key: key,
      text: text,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      dayEndMinutes: dayEndMinutes,
      candidates: candidates,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<String> semanticParseAskAiTimeWindow(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) async {
    final appDir = await _getAppDir();
    final localDay = _formatLocalDayKey(DateTime.now());
    return rust_core.aiSemanticParseAskAiTimeWindow(
      appDir: appDir,
      key: key,
      question: question,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      localDay: localDay,
    );
  }

  @override
  Future<String> semanticParseAskAiTimeWindowCloudGateway(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.aiSemanticParseAskAiTimeWindowCloudGateway(
      appDir: appDir,
      key: key,
      question: question,
      nowLocalIso: nowLocalIso,
      locale: locale.toLanguageTag(),
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
    );
  }

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueSemanticParseJob(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<List<SemanticParseJob>> listDueSemanticParseJobs(
    Uint8List key, {
    required int nowMs,
    int limit = 5,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueSemanticParseJobs(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListSemanticParseJobsByMessageIds(
      appDir: appDir,
      key: key,
      messageIds: messageIds,
    );
  }

  @override
  Future<void> markSemanticParseJobRunning(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobRunning(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobFailed(
    Uint8List key, {
    required String messageId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobFailed(
      appDir: appDir,
      key: key,
      messageId: messageId,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobRetry(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobRetry(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobSucceeded(
    Uint8List key, {
    required String messageId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobSucceeded(
      appDir: appDir,
      key: key,
      messageId: messageId,
      appliedActionKind: appliedActionKind,
      appliedTodoId: appliedTodoId,
      appliedTodoTitle: appliedTodoTitle,
      appliedPrevTodoStatus: appliedPrevTodoStatus,
      suggestedTags: suggestedTags,
      suggestedTagConfidence: suggestedTagConfidence,
      tagSuggestionState: tagSuggestionState,
      appliedTagIds: appliedTagIds,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobCanceled(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markSemanticParseJobUndone(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkSemanticParseJobUndone(
      appDir: appDir,
      key: key,
      messageId: messageId,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    return rust_core.syncDeriveKey(passphrase: passphrase);
  }

  @override
  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) async {
    return rust_core.syncCreateRecoveryEnvelope(
      syncKey: syncKey,
      passphrase: passphrase,
    );
  }

  @override
  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    return rust_core.syncRecoverSyncKeyFromEnvelope(
      envelopeJson: envelopeJson,
      passphrase: passphrase,
    );
  }

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    await rust_core.syncWebdavTestConnection(
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    await rust_core.syncWebdavClearRemoteRoot(
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncWebdavPush(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    return pushed.toInt();
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncWebdavPushOpsOnly(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    return pushed.toInt();
  }

  @override
  Stream<String> syncWebdavPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncWebdavPushOpsOnlyProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pulled = await rust_core.syncWebdavPull(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
    return pulled.toInt();
  }

  @override
  Stream<String> syncWebdavPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncWebdavPullProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<void> syncWebdavDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.syncWebdavDownloadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
      sha256: sha256,
    );
  }

  @override
  Future<bool> syncWebdavUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.syncWebdavUploadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
      sha256: sha256,
    );
  }

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {
    await rust_core.syncLocaldirTestConnection(
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {
    await rust_core.syncLocaldirClearRemoteRoot(
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncLocaldirPush(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
    return pushed.toInt();
  }

  @override
  Stream<String> syncLocaldirPushProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncLocaldirPushProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async {
    final appDir = await _getAppDir();
    final pulled = await rust_core.syncLocaldirPull(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
    return pulled.toInt();
  }

  @override
  Stream<String> syncLocaldirPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncLocaldirPullProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
    );
  }

  @override
  Future<void> syncLocaldirDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.syncLocaldirDownloadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      localDir: localDir,
      remoteRoot: remoteRoot,
      sha256: sha256,
    );
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncManagedVaultPush(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
    return pushed.toInt();
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _getAppDir();
    final pulled = await rust_core.syncManagedVaultPull(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
    return pulled.toInt();
  }

  @override
  Stream<String> syncManagedVaultPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncManagedVaultPullProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
  }

  @override
  Future<void> syncManagedVaultDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.syncManagedVaultDownloadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
      sha256: sha256,
    );
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final appDir = await _getAppDir();
    final pushed = await rust_core.syncManagedVaultPushOpsOnly(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
    return pushed.toInt();
  }

  @override
  Stream<String> syncManagedVaultPushOpsOnlyProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_sync_progress.syncManagedVaultPushOpsOnlyProgress(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
    );
  }

  @override
  Future<MigrationArchiveExportEstimate> estimateMigrationArchiveExport(
    Uint8List key,
  ) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveExportEstimate(
      appDir: appDir,
      key: key,
    );
  }

  @override
  Future<MigrationArchiveManifest> exportMigrationArchive(
    Uint8List key, {
    required String outputPath,
  }) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveExport(
      appDir: appDir,
      key: key,
      outputPath: outputPath,
    );
  }

  @override
  Stream<String> runMigrationArchiveExportProgress(
    Uint8List key, {
    required String outputPath,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_migration_archive.migrationArchiveExportProgress(
      appDir: appDir,
      key: key,
      outputPath: outputPath,
    );
  }

  @override
  Future<MigrationArchiveManifest> inspectMigrationArchive({
    required String archivePath,
  }) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveInspect(
      appDir: appDir,
      archivePath: archivePath,
    );
  }

  @override
  Future<MigrationArchiveManifest> importMigrationArchive(
    Uint8List key, {
    required String archivePath,
  }) async {
    final appDir = await _getAppDir();
    return rust_migration_archive.migrationArchiveImport(
      appDir: appDir,
      key: key,
      archivePath: archivePath,
    );
  }

  @override
  Stream<String> runMigrationArchiveImportProgress(
    Uint8List key, {
    required String archivePath,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_migration_archive.migrationArchiveImportProgress(
      appDir: appDir,
      key: key,
      archivePath: archivePath,
    );
  }

  @override
  Future<ExternalImportScanSummary> scanExternalImportSource({
    required String sourcePath,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportScanSource(
      appDir: appDir,
      sourcePath: sourcePath,
    );
  }

  @override
  Future<List<ExternalImportBatchSummary>> listExternalImportBatches() async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportListBatches(
      appDir: appDir,
    );
  }

  @override
  Future<String> readExternalImportBatchReport({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportBatchReportJson(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Stream<String> runExternalImportProgress(
    Uint8List key, {
    required String sourcePath,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_external_import.externalImportRunProgress(
      appDir: appDir,
      key: key,
      sourcePath: sourcePath,
    );
  }

  @override
  Future<void> deleteExternalImportBatch({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    await rust_external_import.externalImportDeleteBatch(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Future<void> requestExternalImportCancel({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    await rust_external_import.externalImportRequestCancel(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Future<String> estimateExternalImportPhaseB({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportPhaseBEstimateJson(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Future<String> readExternalImportPhaseBState({
    required String batchId,
  }) async {
    final appDir = await _getAppDir();
    return rust_external_import.externalImportPhaseBStateJson(
      appDir: appDir,
      batchId: batchId,
    );
  }

  @override
  Stream<String> runExternalImportPhaseBProgress(
    Uint8List key, {
    required String batchId,
  }) async* {
    final appDir = await _getAppDir();
    yield* rust_external_import.externalImportPhaseBRunProgress(
      appDir: appDir,
      key: key,
      batchId: batchId,
    );
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.syncManagedVaultUploadAttachmentBytes(
      appDir: appDir,
      key: key,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
      sha256: sha256,
    );
  }

  @override
  Future<String> getOrCreateDeviceId() async {
    final appDir = await _getAppDir();
    return rust_core.dbGetOrCreateDeviceId(appDir: appDir);
  }

  @override
  Future<void> syncManagedVaultClearDevice({
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String deviceId,
  }) async {
    await rust_core.syncManagedVaultClearDevice(
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
      deviceId: deviceId,
    );
  }

  @override
  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    await rust_core.syncManagedVaultClearVault(
      baseUrl: baseUrl,
      vaultId: vaultId,
      firebaseIdToken: idToken,
    );
  }

  @override
  Future<AttachmentVariant> upsertAttachmentVariant(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbUpsertAttachmentVariant(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      variant: variant,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  @override
  Future<Uint8List> readAttachmentVariantBytes(
    Uint8List key, {
    required String attachmentSha256,
    required String variant,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbReadAttachmentVariantBytes(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      variant: variant,
    );
  }

  @override
  Future<void> enqueueCloudMediaBackup(
    Uint8List key, {
    required String attachmentSha256,
    required String desiredVariant,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbEnqueueCloudMediaBackup(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      desiredVariant: desiredVariant,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    final affected = await rust_core.dbBackfillCloudMediaBackupImages(
      appDir: appDir,
      key: key,
      desiredVariant: desiredVariant,
      nowMs: PlatformInt64Util.from(nowMs),
    );
    return affected.toInt();
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
  }) async {
    final appDir = await _getAppDir();
    return rust_core.dbListDueCloudMediaBackups(
      appDir: appDir,
      key: key,
      nowMs: PlatformInt64Util.from(nowMs),
      limit: limit,
    );
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkCloudMediaBackupFailed(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      attempts: PlatformInt64Util.from(attempts),
      nextRetryAtMs: PlatformInt64Util.from(nextRetryAtMs),
      lastError: lastError,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
  }) async {
    final appDir = await _getAppDir();
    await rust_core.dbMarkCloudMediaBackupUploaded(
      appDir: appDir,
      key: key,
      attachmentSha256: attachmentSha256,
      nowMs: PlatformInt64Util.from(nowMs),
    );
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbCloudMediaBackupSummary(appDir: appDir, key: key);
  }
}
