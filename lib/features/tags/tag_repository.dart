import 'package:flutter/foundation.dart';

import '../../core/backend/native_app_dir.dart';
import '../../src/rust/api/tags.dart' as rust_tags;
import '../../src/rust/db.dart';

enum TagMergeFeedbackAction {
  accept,
  dismiss,
  later,
}

extension TagMergeFeedbackActionWire on TagMergeFeedbackAction {
  String get wireValue => switch (this) {
        TagMergeFeedbackAction.accept => 'accept',
        TagMergeFeedbackAction.dismiss => 'dismiss',
        TagMergeFeedbackAction.later => 'later',
      };
}

class TagRepository {
  const TagRepository();

  Future<String?> _resolveAppDirOrNull() async {
    if (kIsWeb) return null;
    try {
      return await getNativeAppDir();
    } catch (_) {
      return null;
    }
  }

  Future<String> _requireAppDir() async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null || appDir.isEmpty) {
      throw StateError('native_app_dir_not_available');
    }
    return appDir;
  }

  Future<List<Tag>> listTags(Uint8List key) async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <Tag>[];
    return rust_tags.dbListTags(appDir: appDir, key: key);
  }

  Future<Tag> upsertTag(Uint8List key, String name) async {
    final appDir = await _requireAppDir();
    return rust_tags.dbUpsertTag(appDir: appDir, key: key, name: name);
  }

  Future<List<Tag>> listMessageTags(Uint8List key, String messageId) async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <Tag>[];
    return rust_tags.dbListMessageTags(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  Future<List<Tag>> setMessageTags(
    Uint8List key,
    String messageId,
    List<String> tagIds,
  ) async {
    final appDir = await _requireAppDir();
    return rust_tags.dbSetMessageTags(
      appDir: appDir,
      key: key,
      messageId: messageId,
      tagIds: tagIds,
    );
  }

  Future<List<String>> listMessageSuggestedTags(
    Uint8List key,
    String messageId,
  ) async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <String>[];
    return rust_tags.dbListMessageSuggestedTags(
      appDir: appDir,
      key: key,
      messageId: messageId,
    );
  }

  Future<List<TagMergeSuggestion>> listTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <TagMergeSuggestion>[];

    final clampedLimit = limit <= 0 ? 10 : (limit > 50 ? 50 : limit);
    return rust_tags.dbListTagMergeSuggestions(
      appDir: appDir,
      key: key,
      limit: clampedLimit,
    );
  }

  Future<int> mergeTags(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    final appDir = await _requireAppDir();
    return rust_tags.dbMergeTags(
      appDir: appDir,
      key: key,
      sourceTagId: sourceTagId,
      targetTagId: targetTagId,
    );
  }

  Future<void> recordTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
    required String reason,
    required TagMergeFeedbackAction action,
  }) async {
    final appDir = await _requireAppDir();
    await rust_tags.dbRecordTagMergeFeedback(
      appDir: appDir,
      key: key,
      sourceTagId: sourceTagId,
      targetTagId: targetTagId,
      reason: reason,
      action: action.wireValue,
    );
  }

  Future<List<String>> listMessageIdsByTagIds(
    Uint8List key,
    String conversationId,
    List<String> tagIds,
  ) async {
    if (tagIds.isEmpty) return const <String>[];

    final appDir = await _resolveAppDirOrNull();
    if (appDir == null) return const <String>[];
    return rust_tags.dbListMessageIdsByTagIds(
      appDir: appDir,
      key: key,
      conversationId: conversationId,
      tagIds: tagIds,
    );
  }
}
