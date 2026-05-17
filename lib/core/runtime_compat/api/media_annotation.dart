import '../../models/app_models.dart';

Future<MediaAnnotationConfig> dbGetMediaAnnotationConfig(
        {required String appDir, required List<int> key}) =>
    throw UnsupportedError('rust_runtime_removed:dbGetMediaAnnotationConfig');

Future<void> dbSetMediaAnnotationConfig(
        {required String appDir,
        required List<int> key,
        required MediaAnnotationConfig config}) =>
    throw UnsupportedError('rust_runtime_removed:dbSetMediaAnnotationConfig');

Future<String> mediaAnnotationByokProfile(
        {required String appDir,
        required List<int> key,
        required String profileId,
        required String localDay,
        required String lang,
        required String mimeType,
        required List<int> imageBytes}) =>
    throw UnsupportedError('rust_runtime_removed:mediaAnnotationByokProfile');

Future<String> urlEnrichmentByokProfile(
        {required String appDir,
        required List<int> key,
        required String profileId,
        required String lang,
        required String originalUrl,
        required String finalUrl,
        required String site,
        String? title,
        required String readableTextExcerpt,
        required String readableTextFull}) =>
    throw UnsupportedError('rust_runtime_removed:urlEnrichmentByokProfile');

Future<String> urlEnrichmentCloudGateway(
        {required String appDir,
        required List<int> key,
        required String gatewayBaseUrl,
        required String firebaseIdToken,
        required String modelName,
        required String lang,
        required String originalUrl,
        required String finalUrl,
        required String site,
        String? title,
        required String readableTextExcerpt,
        required String readableTextFull}) =>
    throw UnsupportedError('rust_runtime_removed:urlEnrichmentCloudGateway');
