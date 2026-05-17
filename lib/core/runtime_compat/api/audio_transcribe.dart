// These types are ignored because they are not used by any `pub` functions: `OpenAiAudioTranscribeResponse`, `OpenAiUsage`

Future<String> audioTranscribeLocalWhisper(
        {required String appDir,
        required String modelName,
        required String lang,
        required List<int> wavBytes}) =>
    throw UnsupportedError('rust_runtime_removed:audioTranscribeLocalWhisper');

Future<String> audioTranscribeByokProfile(
        {required String appDir,
        required List<int> key,
        required String profileId,
        required String localDay,
        required String lang,
        required String mimeType,
        required List<int> audioBytes}) =>
    throw UnsupportedError('rust_runtime_removed:audioTranscribeByokProfile');

Future<String> audioTranscribeByokProfileMultimodal(
        {required String appDir,
        required List<int> key,
        required String profileId,
        required String localDay,
        required String lang,
        required String mimeType,
        required List<int> audioBytes}) =>
    throw UnsupportedError(
        'rust_runtime_removed:audioTranscribeByokProfileMultimodal');
