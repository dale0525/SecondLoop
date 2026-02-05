import 'dart:typed_data';

import '../../src/rust/db.dart';

abstract class AttachmentsBackend {
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  });

  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  });

  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  });

  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  );

  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  });
}

abstract class AttachmentAnnotationMutationsBackend {
  Future<void> markAttachmentAnnotationOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  });
}
