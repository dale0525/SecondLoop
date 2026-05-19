import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

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

  _DartTagState _stateFor(Uint8List key) {
    final id = kIsWeb ? 'web' : base64UrlEncode(key);
    return _dartTagStates.putIfAbsent(id, _DartTagState.new);
  }

  Future<List<Tag>> listTags(Uint8List key) async {
    return _stateFor(key).sortedTags();
  }

  Future<Tag> upsertTag(Uint8List key, String name) async {
    return _stateFor(key).upsertTag(name);
  }

  Future<List<Tag>> listMessageTags(Uint8List key, String messageId) async {
    return _stateFor(key).messageTags(messageId);
  }

  Future<List<Tag>> setMessageTags(
    Uint8List key,
    String messageId,
    List<String> tagIds,
  ) async {
    return _stateFor(key).setMessageTags(messageId, tagIds);
  }

  Future<List<String>> listMessageSuggestedTags(
    Uint8List key,
    String messageId,
  ) async {
    return const <String>[];
  }

  Future<List<String>> listManualMessageTagNames(
    Uint8List key,
    String messageId,
  ) async {
    return _stateFor(key).manualMessageTagNames(messageId);
  }

  Future<List<TagMergeSuggestion>> listTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    return const <TagMergeSuggestion>[];
  }

  Future<List<TagMergeSuggestion>> listHiddenTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    return const <TagMergeSuggestion>[];
  }

  Future<int> mergeTags(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    return _stateFor(key).mergeTags(
      sourceTagId: sourceTagId,
      targetTagId: targetTagId,
    );
  }

  Future<void> deleteTag(Uint8List key, String tagId) async {
    _stateFor(key).deleteTag(tagId);
  }

  Future<void> recordTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
    required String reason,
    required TagMergeFeedbackAction action,
  }) async {
    _stateFor(key).recordFeedback(sourceTagId, targetTagId, action);
  }

  Future<void> clearTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    _stateFor(key).clearFeedback(sourceTagId, targetTagId);
  }

  Future<List<String>> listMessageIdsByTagIds(
    Uint8List key,
    String conversationId,
    List<String> tagIds,
  ) async {
    if (tagIds.isEmpty) return const <String>[];
    return _stateFor(key).messageIdsByTagIds(tagIds);
  }
}

final Map<String, _DartTagState> _dartTagStates = <String, _DartTagState>{};

final class _DartTagState {
  int _nextTagSeq = 1;
  final Map<String, Tag> _tags = <String, Tag>{};
  final Map<String, Set<String>> _messageTagIds = <String, Set<String>>{};
  final Set<String> _hiddenMergeFeedback = <String>{};

  List<Tag> sortedTags() {
    final tags = _tags.values.toList(growable: false);
    tags.sort((left, right) {
      final bySystem =
          (right.isSystem ? 1 : 0).compareTo(left.isSystem ? 1 : 0);
      if (bySystem != 0) return bySystem;
      final byName =
          left.name.toLowerCase().compareTo(right.name.toLowerCase());
      if (byName != 0) return byName;
      return left.id.compareTo(right.id);
    });
    return tags;
  }

  Tag upsertTag(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw StateError('tag_name_empty');
    }
    final existing = _tags.values.cast<Tag?>().firstWhere(
          (tag) =>
              tag != null &&
              (tag.name.trim().toLowerCase() == normalized.toLowerCase() ||
                  tag.systemKey?.trim().toLowerCase() ==
                      normalized.toLowerCase()),
          orElse: () => null,
        );
    if (existing != null) return existing;

    final now = PlatformInt64Util.from(DateTime.now().millisecondsSinceEpoch);
    final tag = Tag(
      id: 'tag_${_nextTagSeq++}',
      name: normalized,
      isSystem: false,
      color: null,
      createdAtMs: now,
      updatedAtMs: now,
    );
    _tags[tag.id] = tag;
    return tag;
  }

  List<Tag> messageTags(String messageId) {
    final ids = _messageTagIds[messageId] ?? const <String>{};
    return sortedTags().where((tag) => ids.contains(tag.id)).toList();
  }

  List<Tag> setMessageTags(String messageId, List<String> tagIds) {
    final ids = tagIds.where(_tags.containsKey).toSet();
    _messageTagIds[messageId] = ids;
    return messageTags(messageId);
  }

  List<String> manualMessageTagNames(String messageId) {
    return messageTags(messageId)
        .where((tag) => !tag.isSystem)
        .map((tag) => tag.name)
        .toList(growable: false);
  }

  int mergeTags({
    required String sourceTagId,
    required String targetTagId,
  }) {
    if (sourceTagId == targetTagId) return 0;
    if (!_tags.containsKey(sourceTagId) || !_tags.containsKey(targetTagId)) {
      return 0;
    }
    var affected = 0;
    for (final ids in _messageTagIds.values) {
      if (ids.remove(sourceTagId)) {
        ids.add(targetTagId);
        affected += 1;
      }
    }
    _tags.remove(sourceTagId);
    return affected;
  }

  void deleteTag(String tagId) {
    _tags.remove(tagId);
    for (final ids in _messageTagIds.values) {
      ids.remove(tagId);
    }
  }

  void recordFeedback(
    String sourceTagId,
    String targetTagId,
    TagMergeFeedbackAction action,
  ) {
    if (action == TagMergeFeedbackAction.dismiss) {
      _hiddenMergeFeedback.add('$sourceTagId->$targetTagId');
    }
  }

  void clearFeedback(String sourceTagId, String targetTagId) {
    _hiddenMergeFeedback.remove('$sourceTagId->$targetTagId');
  }

  List<String> messageIdsByTagIds(List<String> tagIds) {
    final requiredIds = tagIds.toSet();
    return _messageTagIds.entries
        .where((entry) => requiredIds.every(entry.value.contains))
        .map((entry) => entry.key)
        .toList(growable: false);
  }
}
