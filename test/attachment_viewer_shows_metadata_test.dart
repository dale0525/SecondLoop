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

import 'test_i18n.dart';

void main() {
  testWidgets('Attachment viewer shows basic metadata when no EXIF',
      (tester) async {
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

    expect(find.byKey(const ValueKey('attachment_metadata_format')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('attachment_metadata_size')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.byKey(const ValueKey('attachment_metadata_format')))
          .data,
      'image/png',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('attachment_metadata_size')))
          .data,
      '67 B',
    );

    expect(find.byKey(const ValueKey('attachment_metadata_captured_at')),
        findsNothing);
    expect(find.byKey(const ValueKey('attachment_metadata_location')),
        findsNothing);
  });

  testWidgets('Attachment viewer shows captured time + location when present',
      (tester) async {
    final backend = _Backend(bytesBySha: {'abc': _tinyJpegWithExif()});

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

    expect(find.byKey(const ValueKey('attachment_metadata_captured_at')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_metadata_location')),
        findsOneWidget);
    expect(find.text('2026-01-27 10:23'), findsOneWidget);
    expect(find.text('37.76667 N, 122.41667 W'), findsOneWidget);
  });

  testWidgets('Attachment viewer falls back to persisted metadata',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyPngBytes()},
      exifBySha: {
        'abc': AttachmentExifMetadata(
          capturedAtMs:
              DateTime(2026, 1, 27, 10, 23, 45).toUtc().millisecondsSinceEpoch,
          latitude: 37.76667,
          longitude: -122.41667,
        ),
      },
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

    expect(find.byKey(const ValueKey('attachment_metadata_captured_at')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_metadata_location')),
        findsOneWidget);
    expect(find.text('2026-01-27 10:23'), findsOneWidget);
    expect(find.text('37.76667 N, 122.41667 W'), findsOneWidget);
  });

  testWidgets(
      'Attachment viewer prefers persisted location when bytes EXIF is wrong',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyJpegWithExifAtOrigin()},
      exifBySha: {
        'abc': AttachmentExifMetadata(
          capturedAtMs:
              DateTime(2026, 1, 27, 10, 23, 45).toUtc().millisecondsSinceEpoch,
          latitude: 37.76667,
          longitude: -122.41667,
        ),
      },
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

    expect(find.text('37.76667 N, 122.41667 W'), findsOneWidget);
    expect(find.text('0.00000 N, 0.00000 E'), findsNothing);
  });

  testWidgets(
      'Attachment viewer ignores persisted (0,0) location and uses bytes EXIF',
      (tester) async {
    final backend = _Backend(
      bytesBySha: {'abc': _tinyJpegWithExif()},
      exifBySha: {
        'abc': AttachmentExifMetadata(
          capturedAtMs:
              DateTime(2026, 1, 27, 10, 23, 45).toUtc().millisecondsSinceEpoch,
          latitude: 0,
          longitude: 0,
        ),
      },
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

    expect(find.text('37.76667 N, 122.41667 W'), findsOneWidget);
    expect(find.text('0.00000 N, 0.00000 E'), findsNothing);
  });
}

Uint8List _tinyPngBytes() {
  // 1x1 transparent PNG.
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

Uint8List _tinyJpegWithExifAtOrigin() {
  final base = img.encodeJpg(img.Image(width: 1, height: 1), quality: 90);

  final exif = img.ExifData();
  exif.exifIfd['DateTimeOriginal'] = '2026:01:27 10:23:45';
  exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  exif.gpsIfd['GPSLatitude'] = _gpsCoordinateValue(
    degrees: 0,
    minutes: 0,
    seconds: 0,
  );
  exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('E');
  exif.gpsIfd['GPSLongitude'] = _gpsCoordinateValue(
    degrees: 0,
    minutes: 0,
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

final class _Backend extends AppBackend implements AttachmentsBackend {
  _Backend({
    required Map<String, Uint8List> bytesBySha,
    Map<String, AttachmentExifMetadata>? exifBySha,
  })  : _bytesBySha = Map<String, Uint8List>.from(bytesBySha),
        _exifBySha = Map<String, AttachmentExifMetadata>.from(exifBySha ?? {});

  final Map<String, Uint8List> _bytesBySha;
  final Map<String, AttachmentExifMetadata> _exifBySha;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      const <Message>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key,
          {int batchLimit = 256}) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>[];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) =>
      Future<String>.value('');

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(false);

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {}

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {}

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      const Stream<String>.empty();

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;

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
      null;

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
