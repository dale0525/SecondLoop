import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

final class _FakeBackend implements AppBackend, AttachmentsBackend {
  bool downloaded = false;
  static final Uint8List _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6Xgm1sAAAAASUVORK5CYII=',
  );

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    if (!downloaded) throw Exception('missing_attachment_bytes');
    return _png1x1;
  }

  @override
  Future<void> syncLocaldirDownloadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
    required String sha256,
  }) async {
    downloaded = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AttachmentViewerPage downloads from sync on demand',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_config_plain_json_v1': jsonEncode({
        SyncConfigStore.kBackendType: 'localdir',
        SyncConfigStore.kRemoteRoot: 'SecondLoopTest',
        SyncConfigStore.kLocalDir: '/tmp/secondloop-test',
        SyncConfigStore.kSyncKeyB64: base64Encode(List<int>.filled(32, 7)),
      }),
    });

    final backend = _FakeBackend();
    final attachment = Attachment(
      sha256: 'deadbeef',
      mimeType: 'image/png',
      path: 'attachments/deadbeef.bin',
      byteLen: _FakeBackend._png1x1.length,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: AppBackendScope(
            backend: backend,
            child: MaterialApp(
              home: AttachmentViewerPage(
                attachment: attachment,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(backend.downloaded, isTrue);
    expect(find.byType(Image), findsOneWidget);
  });
}
