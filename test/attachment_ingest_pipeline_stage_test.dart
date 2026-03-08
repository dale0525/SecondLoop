import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/features/attachments/attachment_ingest_pipeline.dart';
import 'package:secondloop/features/attachments/attachment_processing_status.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('ingestImageAttachmentBytes emits finalizing stage for images',
      () async {
    final backend = _ImageIngestBackend();
    final stages = <AttachmentProcessingStage>[];

    final result = await ingestImageAttachmentBytes(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      rawBytes: _tinyTransparentPng(),
      inferredMimeType: 'image/png',
      lang: 'en',
      onStage: stages.add,
    );

    expect(result.attachmentSha256, 'sha_image');
    expect(stages, contains(AttachmentProcessingStage.finalizingAttachment));
  });
}

final class _ImageIngestBackend extends NativeAppBackend {
  _ImageIngestBackend()
      : super(appDirProvider: () async => '/tmp/image_ingest_test');

  @override
  Future<Attachment> insertAttachment(
    Uint8List key, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    return Attachment(
      sha256: 'sha_image',
      mimeType: mimeType,
      path: '/tmp/sha_image',
      byteLen: bytes.length,
      createdAtMs: 0,
    );
  }

  @override
  Future<void> upsertAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
    int? capturedAtMs,
    double? latitude,
    double? longitude,
  }) async {}
}

Uint8List _tinyTransparentPng() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}
