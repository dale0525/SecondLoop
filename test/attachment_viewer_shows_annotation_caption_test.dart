import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('AttachmentViewerPage shows annotation caption when available',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
      annotationCaptionBySha: const {'abc': 'A long caption'},
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

    expect(find.text('A long caption'), findsWidgets);
  });

  testWidgets(
      'AttachmentViewerPage shows full OCR text when image fallback payload exists',
      (tester) async {
    final longOcr = List<String>.generate(80, (i) => 'token_$i').join(' ');
    final caption =
        'OCR fallback caption: ${longOcr.substring(0, 120).trimRight()}...';

    final backend = _NativeImageBackend(
      bytesBySha: {'abc': _tinyPngBytes()},
      annotationCaptionBySha: {'abc': caption},
      annotationPayloadJsonBySha: {
        'abc': jsonEncode({
          'caption_long': caption,
          'tags': const <String>['ocr_fallback'],
          'ocr_text': longOcr,
        }),
      },
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

    expect(find.text(caption), findsNothing);
    expect(
      find.byKey(const ValueKey('attachment_text_summary_display')),
      findsNothing,
    );
    expect(find.textContaining('token_79'), findsWidgets);
  });

  testWidgets(
      'AttachmentViewerPage shows retry action for recognized image annotation',
      (tester) async {
    final backend = _NativeImageBackend(
      bytesBySha: {'abc': _tinyPngBytes()},
      annotationCaptionBySha: {'abc': 'Cloud detected caption'},
      annotationPayloadJsonBySha: {
        'abc': jsonEncode({
          'caption_long': 'Cloud detected caption',
          'tags': const <String>['receipt'],
        }),
      },
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

    final retryFinder =
        find.byKey(const ValueKey('attachment_annotation_retry'));
    expect(retryFinder, findsOneWidget);

    await tester.ensureVisible(retryFinder);
    await tester.tap(retryFinder);
    await tester.pump();

    expect(backend.retryEnqueueCalls, 1);
    expect(backend.retryMarkFailedCalls, 1);
  });

  testWidgets(
      'AttachmentViewerPage allows editing full text and saves unified payload',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
      annotationCaptionBySha: const {'abc': 'Old caption'},
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

    expect(find.text('Old caption'), findsWidgets);

    final editFinder = find.byKey(const ValueKey('attachment_text_full_edit'));
    await tester.ensureVisible(editFinder);
    await tester.pumpAndSettle();

    await tester.tap(editFinder);
    await tester.pumpAndSettle();

    final editFieldFinder =
        find.byKey(const ValueKey('attachment_text_full_field'));
    await tester.ensureVisible(editFieldFinder);
    await tester.pumpAndSettle();

    await tester.enterText(editFieldFinder, '# New full markdown');

    final saveFinder = find.byKey(const ValueKey('attachment_text_full_save'));
    await tester.ensureVisible(saveFinder);
    await tester.pumpAndSettle();

    await tester.tap(saveFinder);
    await tester.pumpAndSettle();

    expect(find.textContaining('New full markdown'), findsWidgets);
    expect(backend.savedPayloadJsons.length, 1);
    expect(
        backend.savedPayloadJsons.single.contains('manual_full_text'), isTrue);
    expect(backend.savedPayloadJsons.single.contains('# New full markdown'),
        isTrue);
  });
}

Uint8List _tinyPngBytes() {
  // 1x1 transparent PNG.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

final class _NativeImageBackend extends NativeAppBackend {
  _NativeImageBackend({
    required Map<String, Uint8List> bytesBySha,
    required Map<String, String?> annotationCaptionBySha,
    required Map<String, String?> annotationPayloadJsonBySha,
  })  : _bytesBySha = Map<String, Uint8List>.from(bytesBySha),
        _annotationCaptionBySha =
            Map<String, String?>.from(annotationCaptionBySha),
        _annotationPayloadJsonBySha =
            Map<String, String?>.from(annotationPayloadJsonBySha),
        super(appDirProvider: () async => '/tmp/secondloop_test');

  final Map<String, Uint8List> _bytesBySha;
  final Map<String, String?> _annotationCaptionBySha;
  final Map<String, String?> _annotationPayloadJsonBySha;
  int retryEnqueueCalls = 0;
  int retryMarkFailedCalls = 0;

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
    return null;
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    return _annotationCaptionBySha[sha256];
  }

  @override
  Future<String?> readAttachmentAnnotationPayloadJson(
    Uint8List key, {
    required String sha256,
  }) async {
    return _annotationPayloadJsonBySha[sha256];
  }

  @override
  Future<void> enqueueAttachmentAnnotation(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required int nowMs,
  }) async {
    retryEnqueueCalls += 1;
  }

  @override
  Future<void> markAttachmentAnnotationFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    retryMarkFailedCalls += 1;
  }
}

final class _Backend extends TestAppBackend
    implements AttachmentsBackend, AttachmentAnnotationMutationsBackend {
  _Backend({
    required Map<String, Uint8List> bytesBySha,
    required Map<String, String?> annotationCaptionBySha,
  })  : _bytesBySha = Map<String, Uint8List>.from(bytesBySha),
        _annotationCaptionBySha =
            Map<String, String?>.from(annotationCaptionBySha);

  final Map<String, Uint8List> _bytesBySha;
  final Map<String, String?> _annotationCaptionBySha;
  final List<String> savedPayloadJsons = <String>[];

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
    return null;
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    return _annotationCaptionBySha[sha256];
  }

  @override
  Future<void> markAttachmentAnnotationOkJson(
    Uint8List key, {
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    savedPayloadJsons.add(payloadJson);
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, dynamic>) {
      final caption = decoded['caption_long'];
      if (caption is String) {
        _annotationCaptionBySha[attachmentSha256] = caption;
      }
    }
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
