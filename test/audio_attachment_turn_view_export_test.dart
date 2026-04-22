import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/audio_attachment_player.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'audio transcript copy keeps raw transcript when turn view exists', (
    tester,
  ) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final attachment = Attachment(
      sha256: 'audio-turn-copy-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-turn-copy-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              displayTitle: 'Audio attachment',
              initialAnnotationPayload: const <String, Object?>{
                'duration_ms': 42000,
                'transcript_excerpt': 'raw excerpt',
                'transcript_full': 'raw transcript body',
                'transcript_turns_v1': {
                  'builder_version': 'turns_v1',
                  'status': 'ok',
                  'turns': [
                    {
                      'start_ms': 12000,
                      'end_ms': 18000,
                      'text': 'Hello everyone.',
                      'segment_count': 1,
                      'source_segment_start_index': 0,
                      'source_segment_end_index': 0,
                    },
                  ],
                },
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('attachment_text_full_copy')));
    await tester.pumpAndSettle();

    expect(clipboardText, 'raw transcript body');
  });

  testWidgets(
      'audio transcript copy falls back to raw transcript on turn failure',
      (tester) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final attachment = Attachment(
      sha256: 'audio-raw-copy-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-raw-copy-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              displayTitle: 'Audio attachment',
              initialAnnotationPayload: const <String, Object?>{
                'duration_ms': 42000,
                'transcript_excerpt': 'raw excerpt',
                'transcript_full': 'raw transcript body',
                'transcript_turns_v1': {
                  'builder_version': 'turns_v1',
                  'status': 'fallback_builder_error',
                  'turns': [],
                },
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('attachment_text_full_copy')));
    await tester.pumpAndSettle();

    expect(clipboardText, 'raw transcript body');
  });
}

final Uint8List _tinyM4a = Uint8List.fromList(const <int>[
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
