import 'dart:typed_data';

import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';
import 'package:secondloop/features/tags/tag_repository.dart';

Tag _fakeTag({
  required String id,
  required String name,
  String? systemKey,
  bool isSystem = false,
}) {
  return Tag(
    id: id,
    name: name,
    systemKey: systemKey,
    isSystem: isSystem,
    color: null,
    createdAtMs: PlatformInt64Util.from(0),
    updatedAtMs: PlatformInt64Util.from(0),
  );
}

class FakeTagRepository extends TagRepository {
  FakeTagRepository({
    required List<Tag> tags,
    List<Tag> messageTags = const <Tag>[],
    List<String> suggestedTags = const <String>[],
    List<TagMergeSuggestion> mergeSuggestions = const <TagMergeSuggestion>[],
    List<TagMergeSuggestion> hiddenMergeSuggestions =
        const <TagMergeSuggestion>[],
  })  : _tags = List<Tag>.from(tags),
        _messageTags = List<Tag>.from(messageTags),
        _suggestedTags = List<String>.from(suggestedTags),
        _mergeSuggestions = List<TagMergeSuggestion>.from(mergeSuggestions),
        _hiddenMergeSuggestions =
            List<TagMergeSuggestion>.from(hiddenMergeSuggestions);

  final List<Tag> _tags;
  final List<Tag> _messageTags;
  final List<String> _suggestedTags;
  final List<TagMergeSuggestion> _mergeSuggestions;
  final List<TagMergeSuggestion> _hiddenMergeSuggestions;
  List<String>? lastSetTagIds;
  String? lastMergeSourceTagId;
  String? lastMergeTargetTagId;
  String? lastDeletedTagId;
  String? lastClearedMergeSourceTagId;
  String? lastClearedMergeTargetTagId;
  final List<String> feedbackRecords = <String>[];

  @override
  Future<List<Tag>> listTags(Uint8List key) async => List<Tag>.from(_tags);

  @override
  Future<List<Tag>> listMessageTags(Uint8List key, String messageId) async {
    return List<Tag>.from(_messageTags);
  }

  @override
  Future<List<String>> listMessageSuggestedTags(
    Uint8List key,
    String messageId,
  ) async {
    return List<String>.from(_suggestedTags);
  }

  @override
  Future<List<TagMergeSuggestion>> listTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    return List<TagMergeSuggestion>.from(_mergeSuggestions.take(limit));
  }

  @override
  Future<List<TagMergeSuggestion>> listHiddenTagMergeSuggestions(
    Uint8List key, {
    int limit = 10,
  }) async {
    return List<TagMergeSuggestion>.from(_hiddenMergeSuggestions.take(limit));
  }

  @override
  Future<int> mergeTags(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    lastMergeSourceTagId = sourceTagId;
    lastMergeTargetTagId = targetTagId;
    _mergeSuggestions.removeWhere(
      (item) =>
          item.sourceTag.id == sourceTagId && item.targetTag.id == targetTagId,
    );
    _hiddenMergeSuggestions.removeWhere(
      (item) =>
          item.sourceTag.id == sourceTagId && item.targetTag.id == targetTagId,
    );
    return 2;
  }

  @override
  Future<void> deleteTag(Uint8List key, String tagId) async {
    lastDeletedTagId = tagId;
    _tags.removeWhere((tag) => tag.id == tagId);
    _messageTags.removeWhere((tag) => tag.id == tagId);
    _mergeSuggestions.removeWhere(
      (suggestion) =>
          suggestion.sourceTag.id == tagId || suggestion.targetTag.id == tagId,
    );
  }

  @override
  Future<void> recordTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
    required String reason,
    required TagMergeFeedbackAction action,
  }) async {
    feedbackRecords.add(
      '${action.wireValue}:$sourceTagId:$targetTagId:$reason',
    );
    if (action == TagMergeFeedbackAction.dismiss) {
      final index = _mergeSuggestions.indexWhere(
        (item) =>
            item.sourceTag.id == sourceTagId &&
            item.targetTag.id == targetTagId,
      );
      if (index >= 0) {
        _hiddenMergeSuggestions.add(_mergeSuggestions.removeAt(index));
      }
    }
  }

  @override
  Future<void> clearTagMergeFeedback(
    Uint8List key, {
    required String sourceTagId,
    required String targetTagId,
  }) async {
    lastClearedMergeSourceTagId = sourceTagId;
    lastClearedMergeTargetTagId = targetTagId;
    final index = _hiddenMergeSuggestions.indexWhere(
      (item) =>
          item.sourceTag.id == sourceTagId && item.targetTag.id == targetTagId,
    );
    if (index >= 0) {
      _mergeSuggestions.insert(0, _hiddenMergeSuggestions.removeAt(index));
    }
  }

  @override
  Future<Tag> upsertTag(Uint8List key, String name) async {
    final normalized = name.trim();
    for (final tag in _tags) {
      if (tag.systemKey == normalized || tag.name.trim() == normalized) {
        return tag;
      }
    }

    final created = _fakeTag(
      id: 'custom.${_tags.length + 1}',
      name: normalized,
      systemKey: null,
      isSystem: false,
    );
    _tags.insert(0, created);
    return created;
  }

  @override
  Future<List<Tag>> setMessageTags(
    Uint8List key,
    String messageId,
    List<String> tagIds,
  ) async {
    lastSetTagIds = List<String>.from(tagIds);
    final selected = <Tag>[];
    for (final tag in _tags) {
      if (tagIds.contains(tag.id)) {
        selected.add(tag);
      }
    }
    return selected;
  }
}
