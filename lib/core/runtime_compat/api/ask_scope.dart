import '../../models/platform_int.dart';

// These types are ignored because they are not used by any `pub` functions: `ScopedFocus`, `TimeScope`

Stream<String> ragAskAiStreamScoped(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        PlatformInt64? timeStartMs,
        PlatformInt64? timeEndMs,
        required List<String> includeTagIds,
        required List<String> excludeTagIds,
        required bool strictMode,
        required String localeLanguage,
        required String localDay}) =>
    throw UnsupportedError('rust_runtime_removed:ragAskAiStreamScoped');

Stream<String> ragAskAiStreamCloudGatewayScoped(
        {required String appDir,
        required List<int> key,
        required String conversationId,
        required String question,
        required int topK,
        required bool thisThreadOnly,
        PlatformInt64? timeStartMs,
        PlatformInt64? timeEndMs,
        required List<String> includeTagIds,
        required List<String> excludeTagIds,
        required bool strictMode,
        required String localeLanguage,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName}) =>
    throw UnsupportedError(
        'rust_runtime_removed:ragAskAiStreamCloudGatewayScoped');
