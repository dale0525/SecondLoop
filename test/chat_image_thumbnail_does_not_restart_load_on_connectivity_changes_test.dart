import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/chat/chat_image_attachment_thumbnail.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  testWidgets(
    'Chat image thumbnail does not restart byte load on connectivity changes while loading',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'sync_config_plain_json_v1': jsonEncode(
          {SyncConfigStore.kChatThumbnailsWifiOnly: '0'},
        ),
      });

      final oldPlatform = ConnectivityPlatform.instance;
      final fakeConnectivity = _FakeConnectivityPlatform();
      ConnectivityPlatform.instance = fakeConnectivity;
      try {
        final backend = _Backend();
        final sessionKey = Uint8List.fromList(List<int>.filled(32, 1));

        await tester.pumpWidget(
          MaterialApp(
            home: SessionScope(
              sessionKey: sessionKey,
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
        );

        await tester.pump();
        expect(find.byType(ChatImageAttachmentThumbnail), findsOneWidget);
        final thumbWidget = tester.widget<ChatImageAttachmentThumbnail>(
            find.byType(ChatImageAttachmentThumbnail));
        expect(identical(thumbWidget.attachmentsBackend, backend), isTrue);

        final futureBuilderFinder = find.descendant(
          of: find.byType(ChatImageAttachmentThumbnail),
          matching: find.byWidgetPredicate((w) => w is FutureBuilder),
        );
        expect(futureBuilderFinder, findsOneWidget);
        final futureBefore =
            (tester.widget(futureBuilderFinder) as FutureBuilder).future;
        expect(futureBefore, isNotNull);

        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(backend.readCalled.isCompleted, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        fakeConnectivity.emit([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 50));

        fakeConnectivity.emit([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 50));

        fakeConnectivity.emit([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 50));

        final futureAfter =
            (tester.widget(futureBuilderFinder) as FutureBuilder).future;
        expect(identical(futureBefore, futureAfter), isTrue);
      } finally {
        await fakeConnectivity.close();
        ConnectivityPlatform.instance = oldPlatform;
      }
    },
  );
}

final class _FakeConnectivityPlatform extends ConnectivityPlatform {
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const <ConnectivityResult>[ConnectivityResult.wifi];

  void emit(List<ConnectivityResult> results) {
    _controller.add(results);
  }

  Future<void> close() async {
    await _controller.close();
  }
}

final class _Backend implements AttachmentsBackend {
  final Completer<Uint8List> _bytesCompleter = Completer<Uint8List>();
  final Completer<void> readCalled = Completer<void>();

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
    if (!readCalled.isCompleted) {
      readCalled.complete();
    }
    return _bytesCompleter.future;
  }
}
