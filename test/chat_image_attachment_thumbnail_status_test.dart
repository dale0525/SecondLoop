import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/chat/chat_image_attachment_thumbnail.dart';
import 'package:secondloop/features/media_backup/cloud_media_backup_runner.dart';
import 'package:secondloop/features/media_backup/cloud_media_download.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Chat image thumbnail shows preparing state while loading',
      (tester) async {
    final backend = _BackendWithPendingLoad();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: Scaffold(
              body: ChatImageAttachmentThumbnail(
                attachment: const Attachment(
                  sha256: 'abc',
                  mimeType: 'image/png',
                  path: 'attachments/abc.bin',
                  byteLen: 67,
                  createdAtMs: 0,
                ),
                attachmentsBackend: backend,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Chat image thumbnail shows wifi-only blocked status',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/webdav',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 7)),
        SyncConfigStore.kChatThumbnailsWifiOnly: '1',
      }),
    });

    final oldPlatform = ConnectivityPlatform.instance;
    final fakeConnectivity = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakeConnectivity;

    final backend = _BackendWithImmediateFailure();

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: AppBackendScope(
                backend: backend,
                child: Scaffold(
                  body: ChatImageAttachmentThumbnail(
                    attachment: const Attachment(
                      sha256: 'abc',
                      mimeType: 'image/png',
                      path: 'attachments/abc.bin',
                      byteLen: 67,
                      createdAtMs: 0,
                    ),
                    attachmentsBackend: backend,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('chat_image_attachment_status_text')),
          findsOneWidget);
      expect(find.text('Download media files on Wi‑Fi only'), findsOneWidget);
    } finally {
      await fakeConnectivity.close();
      ConnectivityPlatform.instance = oldPlatform;
    }
  });

  testWidgets(
      'Chat image thumbnail trusts downloader policy result before local connectivity pre-check',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'webdav',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/webdav',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 7)),
        SyncConfigStore.kChatThumbnailsWifiOnly: '1',
      }),
    });

    final oldPlatform = ConnectivityPlatform.instance;
    final fakeConnectivity = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakeConnectivity;
    final backend = _BackendWithRemoteDownload();
    final downloader = CloudMediaDownload(
      networkProvider: () async => CloudMediaBackupNetwork.wifi,
    );

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: AppBackendScope(
                backend: backend,
                child: Scaffold(
                  body: ChatImageAttachmentThumbnail(
                    attachment: const Attachment(
                      sha256: 'abc',
                      mimeType: 'image/png',
                      path: 'attachments/abc.bin',
                      byteLen: 67,
                      createdAtMs: 0,
                    ),
                    attachmentsBackend: backend,
                    cloudMediaDownload: downloader,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(backend.syncDownloadCalls, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Download media files on Wi‑Fi only'), findsNothing);
    } finally {
      await fakeConnectivity.close();
      ConnectivityPlatform.instance = oldPlatform;
    }
  });
}

final class _FakeConnectivityPlatform extends ConnectivityPlatform {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const <ConnectivityResult>[ConnectivityResult.mobile];

  Future<void> close() async {
    await _controller.close();
  }
}

final class _BackendWithPendingLoad implements AttachmentsBackend {
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
  }) async {}

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
  }) =>
      Completer<Uint8List>().future;

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

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
}

final class _BackendWithImmediateFailure
    implements AppBackend, AttachmentsBackend {
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
  }) async {}

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
  }) async =>
      throw StateError('missing_local_bytes');

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BackendWithRemoteDownload
    implements AppBackend, AttachmentsBackend {
  static final Uint8List _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6Xgm1sAAAAASUVORK5CYII=',
  );

  bool _downloaded = false;
  int syncDownloadCalls = 0;

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
  }) async {}

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
    if (!_downloaded) {
      throw StateError('missing_local_bytes');
    }
    return _png1x1;
  }

  @override
  Future<void> syncWebdavDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    syncDownloadCalls += 1;
    _downloaded = true;
  }

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
