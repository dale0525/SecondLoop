import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../features/actions/todo/todo_thread_match.dart';
import '../storage/secure_blob_store.dart';
import '../../src/rust/api/core.dart' as rust_core;
import '../../src/rust/db.dart';
import '../../src/rust/frb_generated.dart';
import 'app_backend.dart';
import 'attachments_backend.dart';

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

typedef DbInsertAttachmentFn = Future<Attachment> Function({
  required String appDir,
  required List<int> key,
  required List<int> bytes,
  required String mimeType,
});

class NativeAppBackend implements AppBackend, AttachmentsBackend {
  NativeAppBackend({
    FlutterSecureStorage? secureStorage,
    AppDirProvider? appDirProvider,
    DbInsertMessageFn? dbInsertMessage,
    DbInsertAttachmentFn? dbInsertAttachment,
    DbProcessPendingMessageEmbeddingsFn? dbProcessPendingMessageEmbeddings,
  })  : _secureBlobStore = SecureBlobStore(storage: secureStorage),
        _appDirProvider = appDirProvider ?? _defaultAppDirProvider,
        _dbInsertMessage = dbInsertMessage ?? rust_core.dbInsertMessage,
        _dbInsertAttachment =
            dbInsertAttachment ?? rust_core.dbInsertAttachment,
        _dbProcessPendingMessageEmbeddings =
            dbProcessPendingMessageEmbeddings ??
                rust_core.dbProcessPendingMessageEmbeddings;

  final SecureBlobStore _secureBlobStore;
  final AppDirProvider _appDirProvider;
  final DbInsertMessageFn _dbInsertMessage;
  final DbInsertAttachmentFn _dbInsertAttachment;
  final DbProcessPendingMessageEmbeddingsFn _dbProcessPendingMessageEmbeddings;

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

  static const _kLegacyPrefsAutoUnlockEnabled = 'auto_unlock_enabled_v1';
  static const _kLegacyPrefsSessionKeyB64 = 'session_key_b64_v1';

  static Future<String> _defaultAppDirProvider() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<String> _getAppDir() async {
    final cached = _appDir;
    if (cached != null) return cached;

    _appDir = await _appDirProvider();
    return _appDir!;
  }

  @override
  Future<void> init() async {
    await RustLib.init();
    await _getAppDir();
  }

  @override
  Future<bool> isMasterPasswordSet() async {
    final appDir = await _getAppDir();
    return rust_core.authIsInitialized(appDir: appDir);
  }

  @override
  Future<bool> readAutoUnlockEnabled() async {
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
    var b64 = await _secureBlobStore.readValue(_kSessionKeyB64);
    if (b64 == null || b64.isEmpty) {
      final legacy = await _secureBlobStore.readKey(_kSessionKeyB64);
      if (legacy != null && legacy.isNotEmpty) {
        await _secureBlobStore.update({_kSessionKeyB64: legacy});
        await _secureBlobStore.deleteKey(_kSessionKeyB64);
        b64 = legacy;
      }
    }
    if ((b64 == null || b64.isEmpty) &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS) {
      final prefs = await SharedPreferences.getInstance();
      final legacyPrefs = prefs.getString(_kLegacyPrefsSessionKeyB64);
      if (legacyPrefs != null && legacyPrefs.isNotEmpty) {
        try {
          final bytes = base64Decode(legacyPrefs);
          final key = Uint8List.fromList(bytes);
          await saveSessionKey(key);
          return key;
        } catch (_) {
          await prefs.remove(_kLegacyPrefsSessionKeyB64);
          await prefs.remove(_kLegacyPrefsAutoUnlockEnabled);
          return null;
        }
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
    await _secureBlobStore.update({
      _kSessionKeyB64: base64Encode(key),
      _kAutoUnlockEnabled: '1',
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLegacyPrefsSessionKeyB64);
      await prefs.remove(_kLegacyPrefsAutoUnlockEnabled);
    }
  }

  @override
  Future<void> clearSavedSessionKey() async {
    await _secureBlobStore.update({_kSessionKeyB64: null});

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLegacyPrefsSessionKeyB64);
    }
  }

  @override
  Future<void> validateKey(Uint8List key) async {
    final appDir = await _getAppDir();
    await rust_core.authValidateKey(appDir: appDir, key: key);
  }

  @override
  Future<Uint8List> initMasterPassword(String password) async {
    final appDir = await _getAppDir();
    return rust_core.authInitMasterPassword(appDir: appDir, password: password);
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
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbGetOrCreateMainStreamConversation(
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
      beforeCreatedAtMs: beforeCreatedAtMs,
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
      startAtMsInclusive: startAtMsInclusive,
      endAtMsExclusive: endAtMsExclusive,
    );
  }

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
    final appDir = await _getAppDir();
    return rust_core.dbUpsertTodo(
      appDir: appDir,
      key: key,
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
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
      startAtMsInclusive: startAtMsInclusive,
      endAtMsExclusive: endAtMsExclusive,
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
      startAtMs: startAtMs,
      endAtMs: endAtMs,
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
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
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
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
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
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
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
      timeStartMs: timeStartMs,
      timeEndMs: timeEndMs,
      gatewayBaseUrl: gatewayBaseUrl,
      firebaseIdToken: idToken,
      modelName: modelName,
      embeddingsModelName: embeddingsModelName,
    );
  }

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    return rust_core.syncDeriveKey(passphrase: passphrase);
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
      nowMs: nowMs,
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
      nowMs: nowMs,
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
      nowMs: nowMs,
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
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
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
      nowMs: nowMs,
    );
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    final appDir = await _getAppDir();
    return rust_core.dbCloudMediaBackupSummary(appDir: appDir, key: key);
  }
}
