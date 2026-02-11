import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/audio_attachment_player.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'AudioAttachmentPlayerView renders full text, retry, and edit actions',
      (tester) async {
    final attachment = Attachment(
      sha256: 'audio-transcript-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-transcript-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    var retryInvoked = 0;
    String? savedFull;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              initialAnnotationPayload: const <String, Object?>{
                'duration_ms': 42000,
                'transcript_excerpt': 'hello transcript excerpt',
                'transcript_full':
                    'hello transcript excerpt with more details for full text',
              },
              onRetryRecognition: () async {
                retryInvoked += 1;
              },
              onSaveFull: (value) async {
                savedFull = value;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('attachment_text_summary_display')),
        findsNothing);
    expect(find.byKey(const ValueKey('attachment_text_full_markdown_display')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_transcript_retry')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('attachment_metadata_format')), findsNothing);

    expect(find.byKey(const ValueKey('attachment_text_summary_edit')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('attachment_text_full_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attachment_text_full_field')),
      '# Edited Full',
    );
    await tester.tap(find.byKey(const ValueKey('attachment_text_full_save')));
    await tester.pumpAndSettle();

    expect(savedFull, '# Edited Full');
    expect(find.text('Full text'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('attachment_transcript_retry')));
    await tester.pump();
    expect(retryInvoked, 1);
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
