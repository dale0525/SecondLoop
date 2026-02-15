import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'AttachmentViewerPage keeps video manifest preview when manifest read is one-shot',
      (tester) async {
    final backend = _VideoManifestOneShotBackend();
    const attachment = Attachment(
      sha256: _VideoManifestOneShotBackend.manifestSha,
      mimeType: 'application/x.secondloop.video+json',
      path: 'attachments/video_manifest.bin',
      byteLen: 512,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: AppBackendScope(
            backend: backend,
            child: const MaterialApp(
              home: AttachmentViewerPage(attachment: attachment),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('video_manifest_preview_surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video_manifest_open_proxy_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('video_manifest_keyframe_preview_0')),
      findsOneWidget,
    );
  });
}

final class _VideoManifestOneShotBackend
    implements AppBackend, AttachmentsBackend {
  static const String manifestSha = 'sha-manifest';
  static const String videoSha = 'sha-video-segment';
  static const String posterSha = 'sha-poster';
  static const String keyframeSha = 'sha-keyframe-0';

  static final Uint8List _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6Xgm1sAAAAASUVORK5CYII=',
  );

  static final Uint8List _manifestBytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'schema': 'secondloop.video_manifest.v4',
        'video_sha256': videoSha,
        'video_mime_type': 'video/mp4',
        'video_proxy_sha256': videoSha,
        'poster_sha256': posterSha,
        'poster_mime_type': 'image/png',
        'keyframes': [
          {
            'index': 0,
            'sha256': keyframeSha,
            'mime_type': 'image/png',
            't_ms': 500,
            'kind': 'scene',
          },
        ],
        'video_segments': [
          {
            'index': 0,
            'sha256': videoSha,
            'mime_type': 'video/mp4',
          },
        ],
      }),
    ),
  );

  var _manifestReads = 0;

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    if (sha256 == manifestSha) {
      _manifestReads += 1;
      if (_manifestReads == 1) {
        return _manifestBytes;
      }
      throw StateError('manifest bytes unavailable after first read');
    }

    if (sha256 == posterSha || sha256 == keyframeSha) {
      return _png1x1;
    }

    if (sha256 == videoSha) {
      return Uint8List.fromList(const <int>[1, 2, 3]);
    }

    throw StateError('missing bytes: $sha256');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
