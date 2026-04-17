import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_detail_text_content.dart';
import 'package:secondloop/features/attachments/audio_transcript_turn_view_display.dart';

void main() {
  test('resolveAttachmentDetailTextContent prefers knowledge video fields', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_content_kind': 'knowledge',
        'video_summary': 'Lesson summary from classifier',
        'knowledge_markdown_excerpt': '## Key points',
        'knowledge_markdown_full': '## Key points\n1. OCR\n2. fallback',
        'readable_text_full': 'legacy readable text',
      },
    );

    expect(content.summary, '## Key points');
    expect(content.full, '## Key points\n1. OCR\n2. fallback');
  });

  test('resolveAttachmentDetailTextContent prefers non-knowledge description',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_content_kind': 'non_knowledge',
        'video_summary': 'Travel vlog summary',
        'video_description_excerpt': 'A calm beach sunset scene.',
        'video_description_full':
            'A calm beach sunset scene with walking and ambient sounds.',
      },
    );

    expect(content.summary, 'A calm beach sunset scene.');
    expect(
      content.full,
      'A calm beach sunset scene with walking and ambient sounds.',
    );
  });

  test('resolveAttachmentDetailTextContent prefers extracted video detail', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'video_segment_count': 1,
        'video_summary': 'Travel vlog summary',
        'video_description_full': 'A calm beach sunset scene.',
        'transcript_full': 'Narrator talks about the trip.',
        'ocr_text_full': '',
        'ocr_text_excerpt': '',
      },
    );

    expect(content.summary, '');
    expect(content.full, 'A calm beach sunset scene.');
  });

  test('image detail full prefers summary over extracted metadata', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'image/jpeg',
        'summary': 'A cat is sleeping on the sofa.',
        'extracted_text_full': 'ISO 100\\nExposure 1/120\\nF2.8',
      },
    );

    expect(content.full, 'A cat is sleeping on the sofa.');
  });

  test('image detail full uses annotation caption before extracted metadata',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'image/png',
        'extracted_text_full': 'Lens 35mm\\nCamera Model X',
      },
      annotationCaption: 'Sunset over the lake with orange reflections.',
    );

    expect(content.full, 'Sunset over the lake with orange reflections.');
  });

  test('image detail full keeps AI summary and OCR text together', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'image/png',
        'caption_long': 'AI: A white cat sleeping on a blue sofa.',
        'ocr_text_full': 'OCR: noon 12:30 · call mom',
      },
    );

    expect(
      content.full,
      'AI: A white cat sleeping on a blue sofa.\n\nOCR: noon 12:30 · call mom',
    );
  });

  test('mimeTypeOverride forces image merge when payload lacks mime_type', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'caption_long': 'AI says this is a calendar screenshot.',
        'ocr_text': 'OCR found: meeting with team at 14:00',
      },
      mimeTypeOverride: 'image/png',
    );

    expect(
      content.full,
      'AI says this is a calendar screenshot.\n\n'
      'OCR found: meeting with team at 14:00',
    );
  });

  test('non-image detail full keeps preferring extracted text', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/pdf',
        'summary': 'Document summary',
        'extracted_text_full': 'Document full text body',
      },
    );

    expect(content.full, 'Document full text body');
  });

  test('preferred attachment content kind accepts full chunk kinds', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/pdf',
        'readable_text_excerpt': 'Readable excerpt',
        'readable_text_full': 'Readable full',
        'transcript_excerpt': 'Transcript excerpt',
        'transcript_full': 'Transcript full',
        kPreferredAttachmentContentKindKey: 'transcript_full',
      },
    );

    expect(content.summary, 'Transcript excerpt');
    expect(content.full, 'Transcript full');
  });

  test('url detail summary prefers llm_summary when available', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/x.secondloop.url+json',
        'llm_summary': 'Cloud generated concise summary.',
        'readable_text_excerpt': 'Local extracted excerpt.',
        'readable_text_full': 'Local extracted full text.',
      },
    );

    expect(content.summary, 'Cloud generated concise summary.');
    expect(content.full, 'Cloud generated concise summary.');
  });

  test('url detail full falls back to local extracted text when no summary',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'application/x.secondloop.url+json',
        'readable_text_excerpt': 'Local extracted excerpt.',
        'readable_text_full': 'Local extracted full text.',
      },
    );

    expect(content.summary, 'Local extracted excerpt.');
    expect(content.full, 'Local extracted full text.');
  });

  test('audio detail summary prefers turn view while full keeps transcript',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
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
    );

    expect(content.summary, contains('[00:12–00:18] Hello everyone.'));
    expect(content.full, 'raw transcript body');
  });

  test('audio detail reuses persisted turn view after initial resolution', () {
    final payload = _TranscriptTurnPayloadReadTrackingMap(
      <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_excerpt': 'raw excerpt',
        'transcript_full': 'raw transcript body',
      },
      transcriptTurnView: const <String, Object?>{
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
    );

    final content = resolveAttachmentDetailTextContent(payload);

    expect(content.summary, contains('[00:12–00:18] Hello everyone.'));
    expect(content.full, 'raw transcript body');
    expect(payload.transcriptTurnViewReadCount, 2);
  });

  test('audio detail full prefers transcript_full over turn view', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'full_text': 'generic enrichment full text',
        'transcript_full': 'Speaker A: Hello.\nSpeaker B: Hi.',
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
    );

    expect(content.full, 'Speaker A: Hello.\n\nSpeaker B: Hi.');
  });

  test('audio detail full lightly paragraphizes long transcript using segments',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_full': 'Alice said we should keep the current draft. '
            'Bob said the deadline felt too tight. '
            'Alice proposed moving the launch to Friday. '
            'Bob agreed and asked for one more review.',
        'transcript_segments': [
          {
            't_ms': 0,
            'text': 'Alice said we should keep the current draft.',
          },
          {
            't_ms': 2400,
            'text': 'Bob said the deadline felt too tight.',
          },
          {
            't_ms': 5200,
            'text': 'Alice proposed moving the launch to Friday.',
          },
          {
            't_ms': 7600,
            'text': 'Bob agreed and asked for one more review.',
          },
        ],
      },
    );

    expect(
      content.full,
      'Alice said we should keep the current draft. '
      'Bob said the deadline felt too tight.\n\n'
      'Alice proposed moving the launch to Friday. '
      'Bob agreed and asked for one more review.',
    );
  });

  test('audio detail full upgrades existing single newlines into paragraphs',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_full':
            'Speaker A: Hello.\nSpeaker B: Hi.\nSpeaker A: Great.',
      },
    );

    expect(
      content.full,
      'Speaker A: Hello.\n\nSpeaker B: Hi.\n\nSpeaker A: Great.',
    );
  });

  test(
      'audio detail full does not treat chunk newlines as paragraph boundaries when segments exist',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_full':
            'First sentence.\nSecond sentence.\nThird sentence.\nFourth sentence.',
        'transcript_segments': [
          {
            't_ms': 0,
            'text': 'First sentence.',
          },
          {
            't_ms': 2400,
            'text': 'Second sentence.',
          },
          {
            't_ms': 5200,
            'text': 'Third sentence.',
          },
          {
            't_ms': 7600,
            'text': 'Fourth sentence.',
          },
        ],
      },
    );

    expect(
      content.full,
      'First sentence. Second sentence.\n\n'
      'Third sentence. Fourth sentence.',
    );
  });

  test('audio detail full keeps cjk sentences compact when paragraphized', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_full': '你好。谢谢。再见。明天聊。',
        'transcript_segments': [
          {
            't_ms': 0,
            'text': '你好。',
          },
          {
            't_ms': 2400,
            'text': '谢谢。',
          },
          {
            't_ms': 5200,
            'text': '再见。',
          },
          {
            't_ms': 7600,
            'text': '明天聊。',
          },
        ],
      },
    );

    expect(
      content.full,
      '你好。谢谢。\n\n再见。明天聊。',
    );
  });

  test('audio detail full prefers transcript_full over generic full_text', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'full_text': 'generic enrichment full text',
        'transcript_full': 'raw transcript body',
        'transcript_turns_v1': {
          'builder_version': 'turns_v1',
          'status': 'fallback_builder_error',
          'turns': [],
        },
      },
    );

    expect(content.full, 'raw transcript body');
  });

  test('audio detail falls back to raw transcript when turn view is not ok',
      () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_excerpt': 'raw excerpt',
        'transcript_full': 'raw transcript body',
        'transcript_turns_v1': {
          'builder_version': 'turns_v1',
          'status': 'fallback_builder_error',
          'turns': [],
        },
      },
    );

    expect(content.summary, 'raw excerpt');
    expect(content.full, 'raw transcript body');
  });

  test('audio detail can build turn view from legacy transcript segments', () {
    final content = resolveAttachmentDetailTextContent(
      const <String, Object?>{
        'mime_type': 'audio/mp4',
        'transcript_excerpt': 'raw excerpt',
        'transcript_segments': [
          {
            't_ms': 12000,
            'text': 'Hello everyone.',
          },
          {
            't_ms': 12600,
            'text': 'Thanks for joining.',
          },
        ],
      },
    );

    expect(
      content.full,
      '[00:12–00:12] Hello everyone. Thanks for joining.',
    );
    expect(content.summary, contains('[00:12–00:12]'));
  });

  test('audio turn view rechecks payload after turn data is added', () {
    final payload = <String, Object?>{
      'mime_type': 'audio/mp4',
      'transcript_full': 'raw transcript body',
    };

    expect(resolveAudioTranscriptTurnView(payload), isNull);

    payload['transcript_turns_v1'] = const <String, Object?>{
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
    };

    final turnView = resolveAudioTranscriptTurnView(payload);

    expect(turnView, isNotNull);
    expect(turnView!.turns.single.text, 'Hello everyone.');
  });

  test(
      'audio turn view refreshes cached value after persisted turn data changes',
      () {
    final payload = <String, Object?>{
      'mime_type': 'audio/mp4',
      'transcript_full': 'raw transcript body',
      'transcript_turns_v1': const <String, Object?>{
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
    };

    final first = resolveAudioTranscriptTurnView(payload);
    expect(first, isNotNull);
    expect(first!.turns.single.text, 'Hello everyone.');

    payload['transcript_turns_v1'] = const <String, Object?>{
      'builder_version': 'turns_v1',
      'status': 'ok',
      'turns': [
        {
          'start_ms': 12000,
          'end_ms': 24000,
          'text': 'Updated speaker text.',
          'segment_count': 1,
          'source_segment_start_index': 0,
          'source_segment_end_index': 0,
        },
      ],
    };

    final second = resolveAudioTranscriptTurnView(payload);
    expect(second, isNotNull);
    expect(second!.turns.single.text, 'Updated speaker text.');
  });
}

final class _TranscriptTurnPayloadReadTrackingMap
    extends MapBase<String, Object?> {
  _TranscriptTurnPayloadReadTrackingMap(
    this._values, {
    required Map<String, Object?> transcriptTurnView,
  }) : _transcriptTurnView = transcriptTurnView;

  final Map<String, Object?> _values;
  final Map<String, Object?> _transcriptTurnView;
  int transcriptTurnViewReadCount = 0;

  @override
  Object? operator [](Object? key) {
    if (key == 'transcript_turns_v1') {
      transcriptTurnViewReadCount += 1;
      return _transcriptTurnView;
    }
    return _values[key];
  }

  @override
  void operator []=(String key, Object? value) {
    _values[key] = value;
  }

  @override
  void clear() {
    _values.clear();
  }

  @override
  Iterable<String> get keys =>
      _values.keys.followedBy(const ['transcript_turns_v1']);

  @override
  Object? remove(Object? key) {
    if (key == 'transcript_turns_v1') {
      return null;
    }
    return _values.remove(key);
  }
}
