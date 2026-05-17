import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import '../../test_i18n.dart';

final class _FakeBackend implements AppBackend, AttachmentsBackend {
  _FakeBackend({required this.bytesBySha});

  final Map<String, Uint8List> bytesBySha;

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async {
    final bytes = bytesBySha[sha256];
    if (bytes == null) throw StateError('missing_attachment_bytes');
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildViewer({
  required Attachment attachment,
  required Uint8List bytes,
  bool isWebOverride = true,
}) {
  return wrapWithI18n(
    SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: AppBackendScope(
        backend: _FakeBackend(bytesBySha: <String, Uint8List>{
          attachment.sha256: bytes,
        }),
        child: MaterialApp(
          home: AttachmentViewerPage(
            attachment: attachment,
            isWebOverride: isWebOverride,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'AttachmentViewerPage shows continue-in-app notice for video on web',
      (tester) async {
    const attachment = Attachment(
      sha256: 'video-sha',
      mimeType: 'video/mp4',
      path: 'attachments/video-sha.bin',
      byteLen: 4096,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      _buildViewer(
        attachment: attachment,
        bytes: Uint8List.fromList(const <int>[0, 1, 2, 3]),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Continue processing in the app'), findsOneWidget);
    expect(
      find.textContaining('Existing cloud results stay available here'),
      findsOneWidget,
    );
  });

  testWidgets(
      'AttachmentViewerPage does not show continue-in-app notice for text on web',
      (tester) async {
    const attachment = Attachment(
      sha256: 'text-sha',
      mimeType: 'text/plain',
      path: 'attachments/text-sha.bin',
      byteLen: 12,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      _buildViewer(
        attachment: attachment,
        bytes: Uint8List.fromList('plain text'.codeUnits),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Continue processing in the app'), findsNothing);
  });
}
