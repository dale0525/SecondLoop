import 'dart:async';
import 'dart:typed_data';

import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/backend/native_backend.dart';
import 'attachment_ingest_pipeline.dart';
import 'attachment_url_manifest_draft.dart';

typedef LinkCreatedUrlAttachment = Future<void> Function(
  String attachmentSha256,
  String normalizedUrl,
);

Future<String> insertUrlManifestAttachment({
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required String url,
}) async {
  final normalizedUrl = url.trim();
  final attachment = await backend.insertAttachment(
    sessionKey,
    bytes: buildUrlManifestAttachmentBytes(normalizedUrl),
    mimeType: kSecondLoopUrlManifestMimeType,
  );
  return attachment.sha256;
}

Future<bool> trySendUrlManifestAttachment({
  required String text,
  required NativeAppBackend backend,
  required Uint8List sessionKey,
  required LinkCreatedUrlAttachment linkCreatedAttachment,
  AttachmentMetadataStore metadataStore = const DartAttachmentMetadataStore(),
}) async {
  final trimmed = text.trim();
  if (!looksLikeHttpUrlText(trimmed)) return false;

  try {
    final attachmentSha256 = await insertUrlManifestAttachment(
      backend: backend,
      sessionKey: sessionKey,
      url: trimmed,
    );
    await linkCreatedAttachment(attachmentSha256, trimmed);
    unawaited(
      metadataStore.upsert(
        sessionKey,
        attachmentSha256: attachmentSha256,
        title: trimmed,
        sourceUrls: <String>[trimmed],
      ).catchError((_) {}),
    );
    return true;
  } catch (_) {
    return false;
  }
}
