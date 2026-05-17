import '../../models/app_models.dart';
import '../../models/platform_int.dart';

Future<List<AttachmentAnnotationJob>> dbListDueImageAttachmentAnnotations(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListDueImageAttachmentAnnotations');

Future<List<AttachmentAnnotationJob>> dbListDueUrlManifestAttachmentAnnotations(
        {required String appDir,
        required List<int> key,
        required PlatformInt64 nowMs,
        required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbListDueUrlManifestAttachmentAnnotations');

Future<int> dbProcessPendingDocumentExtractions(
        {required String appDir, required List<int> key, required int limit}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbProcessPendingDocumentExtractions');

Future<String?> dbReadAttachmentAnnotationPayloadJson(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256}) =>
    throw UnsupportedError(
        'rust_runtime_removed:dbReadAttachmentAnnotationPayloadJson');
