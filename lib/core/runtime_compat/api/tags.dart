import '../../models/app_models.dart';

Future<List<Tag>> dbListTags(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbListTags');

Future<Tag> dbUpsertTag(
        {required String appDir,
        required List<int> key,
        required String name}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertTag');

Future<List<Tag>> dbListMessageTags(
        {required String appDir,
        required List<int> key,
        required String messageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListMessageTags');

Future<List<Tag>> dbSetMessageTags(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required List<String> tagIds}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetMessageTags');

Future<List<String>> dbListMessageSuggestedTags(
        {required String appDir,
        required List<int> key,
        required String messageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListMessageSuggestedTags');

Future<List<String>> dbListManualMessageTagNames(
        {required String appDir,
        required List<int> key,
        required String messageId}) =>
    throw UnsupportedError('rust_runtime_removed:dbListManualMessageTagNames');

Future<List<TagMergeSuggestion>> dbListTagMergeSuggestions(
        {required String appDir, required List<int> key, required int limit}) =>
    throw UnsupportedError('rust_runtime_removed:dbListTagMergeSuggestions');

Future<int> dbMergeTags(
        {required String appDir,
        required List<int> key,
        required String sourceTagId,
        required String targetTagId}) =>
    throw UnsupportedError('rust_runtime_removed:dbMergeTags');

Future<List<TagMergeSuggestion>> dbListHiddenTagMergeSuggestions(
        {required String appDir, required List<int> key, required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListHiddenTagMergeSuggestions');

Future<void> dbDeleteTag(
        {required String appDir,
        required List<int> key,
        required String tagId}) =>
    throw UnsupportedError('rust_runtime_removed:dbDeleteTag');

Future<void> dbRecordTagMergeFeedback(
        {required String appDir,
        required List<int> key,
        required String sourceTagId,
        required String targetTagId,
        required String reason,
        required String action}) =>
    throw UnsupportedError('rust_runtime_removed:dbRecordTagMergeFeedback');

Future<void> dbClearTagMergeFeedback(
        {required String appDir,
        required List<int> key,
        required String sourceTagId,
        required String targetTagId}) =>
    throw UnsupportedError('rust_runtime_removed:dbClearTagMergeFeedback');

Future<List<String>> dbListMessageIdsByTagIds(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required List<String> tagIds}) =>
    throw UnsupportedError('rust_runtime_removed:dbListMessageIdsByTagIds');
