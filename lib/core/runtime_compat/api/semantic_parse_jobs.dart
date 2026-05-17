import '../../models/platform_int.dart';

Future<bool> dbCompleteSemanticParseFollowupIfCurrentAttempt(
        {required String appDir,
        required List<int> key,
        required String messageId,
        required PlatformInt64 expectedAttemptId,
        required String todoId,
        String? todoTitle,
        String? newStatus,
        PlatformInt64? dueAtMs,
        List<String>? pendingSuggestedTags,
        List<String>? autoApplySuggestedTags,
        double? suggestedTagConfidence,
        required PlatformInt64 nowMs}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbCompleteSemanticParseFollowupIfCurrentAttempt');
