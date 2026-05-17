import '../../models/app_models.dart';

Future<AttachmentMetadata?> dbReadAttachmentMetadata(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256}) =>
    throw UnsupportedError('rust_runtime_removed:dbReadAttachmentMetadata');

Future<void> dbUpsertAttachmentMetadata(
        {required String appDir,
        required List<int> key,
        required String attachmentSha256,
        String? title,
        required List<String> filenames,
        required List<String> sourceUrls}) =>
    throw UnsupportedError('rust_runtime_removed:dbUpsertAttachmentMetadata');

Future<Attachment?> dbReadAttachmentBySha256(
        {required String appDir, required String attachmentSha256}) =>
    throw UnsupportedError('rust_runtime_removed:dbReadAttachmentBySha256');
