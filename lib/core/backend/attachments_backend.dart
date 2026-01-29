import 'dart:typed_data';

import '../../src/rust/db.dart';

abstract class AttachmentsBackend {
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  });

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
