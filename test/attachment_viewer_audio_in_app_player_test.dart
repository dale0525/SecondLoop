import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/features/attachments/audio_attachment_player.dart';
import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

final class _AudioBackend implements AppBackend, AttachmentsBackend {
  static final Uint8List _tinyM4a = Uint8List.fromList(<int>[
    0x00,
    0x00,
    0x00,
    0x18,
    0x66,
    0x74,
    0x79,
    0x70,
    0x4D,
    0x34,
    0x41,
    0x20,
    0x69,
    0x73,
    0x6F,
    0x6D,
  ]);

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async =>
      _tinyM4a;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'AttachmentViewerPage renders in-app audio player for audio files',
      (tester) async {
    final backend = _AudioBackend();
    final attachment = Attachment(
      sha256: 'audio-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-sha.bin',
      byteLen: _AudioBackend._tinyM4a.length,
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
              home: AttachmentViewerPage(attachment: attachment),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AudioAttachmentPlayerView), findsOneWidget);
    expect(find.byType(NonImageAttachmentView), findsNothing);
    expect(
      find.byKey(const ValueKey('audio_attachment_player_view')),
      findsOneWidget,
    );
  });
}
