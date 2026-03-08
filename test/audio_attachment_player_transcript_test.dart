import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/theme.dart';
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
              displayTitle: 'Audio attachment',
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
    expect(find.byKey(const ValueKey('attachment_text_full_regenerate')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('attachment_metadata_format')), findsNothing);

    expect(find.byKey(const ValueKey('attachment_text_summary_edit')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('attachment_text_full_edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
        findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat_markdown_editor_input')),
      '# Edited Full',
    );
    await tester.tap(find.byKey(const ValueKey('chat_markdown_editor_save')));
    await tester.pumpAndSettle();

    expect(savedFull, '# Edited Full');
    expect(find.text('Full text'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('attachment_text_full_regenerate')));
    await tester.pump();
    expect(retryInvoked, 1);
  });

  testWidgets(
      'AudioAttachmentPlayerView keeps player width aligned with transcript and styles seek slider',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final attachment = Attachment(
      sha256: 'audio-layout-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-layout-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              displayTitle: 'Audio attachment',
              initialAnnotationPayload: const <String, Object?>{
                'transcript_full': 'A full transcript shown in the detail page',
                'duration_ms': 42000,
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    final playerCardFinder =
        find.byKey(const ValueKey('audio_attachment_player_card'));
    final transcriptCardFinder =
        find.byKey(const ValueKey('attachment_text_full_card'));

    expect(find.byKey(const ValueKey('attachment_detail_workspace')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_header_bar')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_inspector')),
        findsOneWidget);
    expect(find.text('Audio attachment'), findsOneWidget);
    expect(find.text('audio/mp4'), findsWidgets);
    expect(find.text('00:42'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(playerCardFinder, findsOneWidget);
    expect(transcriptCardFinder, findsOneWidget);

    final playerSize = tester.getSize(playerCardFinder);
    final transcriptSize = tester.getSize(transcriptCardFinder);
    expect(transcriptSize.width, lessThanOrEqualTo(playerSize.width));

    final sliderFinder =
        find.byKey(const ValueKey('audio_attachment_seek_slider'));
    expect(sliderFinder, findsOneWidget);

    final sliderThemeFinder = find.ancestor(
      of: sliderFinder,
      matching: find.byType(SliderTheme),
    );
    expect(sliderThemeFinder, findsOneWidget);

    final sliderTheme = tester.widget<SliderTheme>(sliderThemeFinder);
    final sliderThemeData = sliderTheme.data;
    expect(sliderThemeData.activeTrackColor, isNotNull);
    expect(sliderThemeData.thumbColor, isNotNull);
    expect(
      sliderThemeData.activeTrackColor,
      isNot(equals(sliderThemeData.inactiveTrackColor)),
    );

    await tester
        .tap(find.byKey(const ValueKey('attachment_detail_tab_metadata')));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('16 B'), findsOneWidget);
  });

  testWidgets('AudioAttachmentPlayerView shows turn view by default', (
    tester,
  ) async {
    final attachment = Attachment(
      sha256: 'audio-turn-view-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-turn-view-sha.bin',
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

    expect(
        find.textContaining('[00:12–00:18] Hello everyone.'), findsOneWidget);
    expect(find.text('raw transcript body'), findsNothing);
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
