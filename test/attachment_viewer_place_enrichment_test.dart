import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'AttachmentViewerPage keeps place enrichment hidden in compact layout',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
      exifBySha: const {
        'abc': AttachmentExifMetadata(
          capturedAtMs: null,
          latitude: 47.6062,
          longitude: -122.3321,
        ),
      },
      placeBySha: const {'abc': 'Seattle'},
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AttachmentViewerPage(
                attachment: Attachment(
                  sha256: 'abc',
                  mimeType: 'image/png',
                  path: 'attachments/abc.bin',
                  byteLen: 67,
                  createdAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_metadata_location_name')),
      findsNothing,
    );
    expect(find.text('Seattle'), findsNothing);
  });
}

Uint8List _tinyPngBytes() {
  // 1x1 transparent PNG.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({
    required Map<String, Uint8List> bytesBySha,
    required Map<String, AttachmentExifMetadata?> exifBySha,
    required Map<String, String?> placeBySha,
  })  : _bytesBySha = Map<String, Uint8List>.from(bytesBySha),
        _exifBySha = Map<String, AttachmentExifMetadata?>.from(exifBySha),
        _placeBySha = Map<String, String?>.from(placeBySha);

  final Map<String, Uint8List> _bytesBySha;
  final Map<String, AttachmentExifMetadata?> _exifBySha;
  final Map<String, String?> _placeBySha;

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final bytes = _bytesBySha[sha256];
    if (bytes == null) throw StateError('missing_bytes:$sha256');
    return bytes;
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async {
    return _exifBySha[sha256];
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async {
    return _placeBySha[sha256];
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) =>
      throw UnimplementedError();
}
