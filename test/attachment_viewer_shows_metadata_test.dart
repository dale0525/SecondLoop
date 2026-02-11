import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Attachment viewer keeps core app bar actions', (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
    );

    const attachment = Attachment(
      sha256: 'abc',
      mimeType: 'image/png',
      path: 'attachments/abc.bin',
      byteLen: 67,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AttachmentViewerPage(attachment: attachment),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_viewer_share')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment_viewer_open_with_system')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment_viewer_download')),
      findsOneWidget,
    );
    expect(find.text('abc.bin'), findsWidgets);
    expect(find.text('Image attachment'), findsNothing);
  });

  testWidgets('Image attachment uses compact unified layout', (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
    );

    const attachment = Attachment(
      sha256: 'abc',
      mimeType: 'image/png',
      path: 'attachments/abc.bin',
      byteLen: 67,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AttachmentViewerPage(attachment: attachment),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_image_detail_scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment_image_preview_surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment_image_preview_tap_target')),
      findsOneWidget,
    );
    final previewSize = tester
        .getSize(find.byKey(const ValueKey('attachment_image_preview_box')));
    expect(previewSize.height, lessThanOrEqualTo(300));
  });

  testWidgets('Attachment viewer hides metadata cards even when EXIF exists',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyJpegWithExif()},
      exifBySha: {
        'abc': AttachmentExifMetadata(
          capturedAtMs:
              DateTime(2026, 1, 27, 10, 23, 45).toUtc().millisecondsSinceEpoch,
          latitude: 37.76667,
          longitude: -122.41667,
        ),
      },
      placeBySha: const {'abc': 'San Francisco'},
    );

    const attachment = Attachment(
      sha256: 'abc',
      mimeType: 'image/jpeg',
      path: 'attachments/abc.bin',
      byteLen: 123,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AttachmentViewerPage(attachment: attachment),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_metadata_captured_at')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('attachment_metadata_location_name')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('attachment_metadata_location')),
      findsNothing,
    );
  });

  testWidgets('Image preview opens full-size dialog on tap', (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
    );

    const attachment = Attachment(
      sha256: 'abc',
      mimeType: 'image/png',
      path: 'attachments/abc.bin',
      byteLen: 67,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const AttachmentViewerPage(attachment: attachment),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('attachment_image_preview_tap_target')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_image_full_preview_dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('attachment_image_full_preview_close')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_image_full_preview_dialog')),
      findsNothing,
    );
  });
}

Uint8List _tinyPngBytes() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBApGq4QAAAABJRU5ErkJggg==';
  return Uint8List.fromList(base64Decode(b64));
}

Uint8List _tinyJpegWithExif() {
  final base = img.encodeJpg(img.Image(width: 1, height: 1), quality: 90);

  final exif = img.ExifData();
  exif.exifIfd['DateTimeOriginal'] = '2026:01:27 10:23:45';
  exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  exif.gpsIfd['GPSLatitude'] = _gpsCoordinateValue(
    degrees: 37,
    minutes: 46,
    seconds: 0,
  );
  exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('W');
  exif.gpsIfd['GPSLongitude'] = _gpsCoordinateValue(
    degrees: 122,
    minutes: 25,
    seconds: 0,
  );

  return img.injectJpgExif(base, exif) ?? base;
}

img.IfdValueRational _gpsCoordinateValue({
  required int degrees,
  required int minutes,
  required int seconds,
}) {
  final data = ByteData(24)
    ..setUint32(0, degrees, Endian.big)
    ..setUint32(4, 1, Endian.big)
    ..setUint32(8, minutes, Endian.big)
    ..setUint32(12, 1, Endian.big)
    ..setUint32(16, seconds, Endian.big)
    ..setUint32(20, 1, Endian.big);
  return img.IfdValueRational.data(
    img.InputBuffer(data.buffer.asUint8List(), bigEndian: true),
    3,
  );
}

final class _Backend extends TestAppBackend implements AttachmentsBackend {
  _Backend({
    required Map<String, Uint8List> bytesBySha,
    Map<String, AttachmentExifMetadata>? exifBySha,
    Map<String, String>? placeBySha,
  })  : _bytesBySha = Map<String, Uint8List>.from(bytesBySha),
        _exifBySha = Map<String, AttachmentExifMetadata>.from(exifBySha ?? {}),
        _placeBySha = Map<String, String>.from(placeBySha ?? {});

  final Map<String, Uint8List> _bytesBySha;
  final Map<String, AttachmentExifMetadata> _exifBySha;
  final Map<String, String> _placeBySha;

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async =>
      const <Attachment>[];

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async =>
      const <Attachment>[];

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final bytes = _bytesBySha[sha256];
    if (bytes == null) throw StateError('missing_bytes');
    return bytes;
  }

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      _placeBySha[sha256];

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      _exifBySha[sha256];
}
