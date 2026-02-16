import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/features/media_backup/video_kind_classifier.dart';
import 'package:secondloop/features/media_backup/video_transcode_worker.dart';

void main() {
  test('normalizes predefined common video kinds and aliases', () {
    expect(normalizeVideoKind('MEETING'), 'meeting');
    expect(normalizeVideoKind(' Tutorial '), 'tutorial');
    expect(normalizeVideoKind('screenrecording'), 'screen_recording');
    expect(normalizeVideoKind('walkthrough'), 'tutorial');
    expect(normalizeVideoKind('slides'), 'presentation');
    expect(normalizeVideoKind('unknown_kind'), 'unknown');
  });

  test('classifies screen recording from filename keyword', () async {
    final result = await classifyVideoKind(
      filename: 'Screen Recording 2026-02-14 at 10.00.00.mov',
      sourceMimeType: 'video/quicktime',
    );

    expect(result.kind, 'screen_recording');
    expect(result.confidence, greaterThanOrEqualTo(0.95));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies vlog from camera roll naming pattern', () async {
    final result = await classifyVideoKind(
      filename: 'VID_20260214_100001.MP4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'vlog');
    expect(result.confidence, greaterThanOrEqualTo(0.8));
    expect(result.keyframeKind, 'scene');
  });

  test('classifies tutorial from filename keywords', () async {
    final result = await classifyVideoKind(
      filename: 'flutter_setup_tutorial_part1.mp4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'tutorial');
    expect(result.confidence, greaterThanOrEqualTo(0.85));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies lecture from filename keywords', () async {
    final result = await classifyVideoKind(
      filename: 'CS101_lecture_week03.mov',
      sourceMimeType: 'video/quicktime',
    );

    expect(result.kind, 'lecture');
    expect(result.confidence, greaterThanOrEqualTo(0.8));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies meeting from filename keywords', () async {
    final result = await classifyVideoKind(
      filename: 'weekly_standup_meeting_2026_02_16.mp4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'meeting');
    expect(result.confidence, greaterThanOrEqualTo(0.85));
    expect(result.keyframeKind, 'scene');
  });

  test('classifies interview from filename keywords', () async {
    final result = await classifyVideoKind(
      filename: 'candidate_interview_round2.mp4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'interview');
    expect(result.confidence, greaterThanOrEqualTo(0.88));
    expect(result.keyframeKind, 'scene');
  });

  test('classifies gameplay from filename keywords', () async {
    final result = await classifyVideoKind(
      filename: 'bossfight_gameplay_speedrun.webm',
      sourceMimeType: 'video/webm',
    );

    expect(result.kind, 'gameplay');
    expect(result.confidence, greaterThanOrEqualTo(0.9));
    expect(result.keyframeKind, 'scene');
  });

  test('classifies presentation from filename keywords', () async {
    final result = await classifyVideoKind(
      filename: 'quarterly_keynote_presentation.mp4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'presentation');
    expect(result.confidence, greaterThanOrEqualTo(0.82));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies meeting from OCR agenda and action-item cues', () async {
    final result = await classifyVideoKind(
      filename: 'clip.mp4',
      sourceMimeType: 'video/mp4',
      posterBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      ocrImageFn: (bytes, {required languageHints}) async {
        return const PlatformPdfOcrResult(
          fullText:
              'Meeting agenda\nAction items\nOwner: Alex\nDue date: Friday\nNext steps',
          excerpt: 'Meeting agenda',
          engine: 'fake',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result.kind, 'meeting');
    expect(result.confidence, greaterThanOrEqualTo(0.75));
    expect(result.keyframeKind, 'scene');
  });

  test('classifies interview from OCR Q/A cues', () async {
    final result = await classifyVideoKind(
      filename: 'clip.mp4',
      sourceMimeType: 'video/mp4',
      posterBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      ocrImageFn: (bytes, {required languageHints}) async {
        return const PlatformPdfOcrResult(
          fullText:
              'Q: Tell me about a challenge.\nA: I reduced latency by 40%.\nInterviewer feedback',
          excerpt: 'Q/A',
          engine: 'fake',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result.kind, 'interview');
    expect(result.confidence, greaterThanOrEqualTo(0.75));
    expect(result.keyframeKind, 'scene');
  });

  test('classifies lecture when OCR lecture cues are strong', () async {
    final result = await classifyVideoKind(
      filename: 'lecture_clip.mp4',
      sourceMimeType: 'video/mp4',
      posterBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      keyframes: <VideoPreviewFrame>[
        VideoPreviewFrame(
          index: 0,
          bytes: Uint8List(0),
          mimeType: 'image/jpeg',
          tMs: 0,
          kind: 'scene',
        ),
      ],
      ocrImageFn: (bytes, {required languageHints}) async {
        return const PlatformPdfOcrResult(
          fullText:
              'Chapter 3: Attention Is All You Need\nTransformer architecture\nencoder decoder\nself-attention\nfeed-forward\nresidual\nlayer norm\n',
          excerpt: 'Chapter 3',
          engine: 'fake',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result.kind, 'lecture');
    expect(result.confidence, greaterThanOrEqualTo(0.75));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies screen recording for sparse desktop text across samples',
      () async {
    var callIndex = 0;
    final result = await classifyVideoKind(
      filename: 'weekly_update.mp4',
      sourceMimeType: 'video/mp4',
      posterBytes: Uint8List.fromList(const <int>[4, 4, 4]),
      keyframes: <VideoPreviewFrame>[
        VideoPreviewFrame(
          index: 0,
          bytes: Uint8List.fromList(const <int>[5, 5, 5]),
          mimeType: 'image/jpeg',
          tMs: 0,
          kind: 'scene',
        ),
        VideoPreviewFrame(
          index: 1,
          bytes: Uint8List.fromList(const <int>[6, 6, 6]),
          mimeType: 'image/jpeg',
          tMs: 8000,
          kind: 'scene',
        ),
      ],
      ocrImageFn: (bytes, {required languageHints}) async {
        callIndex += 1;
        const texts = <String>[
          'Terminal window command history',
          'Browser tab source repository',
          'File explorer and cursor focus',
        ];
        return PlatformPdfOcrResult(
          fullText: texts[callIndex - 1],
          excerpt: texts[callIndex - 1],
          engine: 'fake',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result.kind, 'screen_recording');
    expect(result.confidence, greaterThanOrEqualTo(0.7));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies meeting from Spanish filename keyword', () async {
    final result = await classifyVideoKind(
      filename: 'reunion_equipo_semanal.mp4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'meeting');
    expect(result.confidence, greaterThanOrEqualTo(0.84));
  });

  test('classifies tutorial from French filename keyword', () async {
    final result = await classifyVideoKind(
      filename: 'guide_tutoriel_installation.mp4',
      sourceMimeType: 'video/mp4',
    );

    expect(result.kind, 'tutorial');
    expect(result.confidence, greaterThanOrEqualTo(0.8));
  });

  test('classifies interview from German OCR keyword', () async {
    final result = await classifyVideoKind(
      filename: 'clip.mp4',
      sourceMimeType: 'video/mp4',
      posterBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      ocrImageFn: (bytes, {required languageHints}) async {
        return const PlatformPdfOcrResult(
          fullText:
              'Vorstellungsgespräch Kandidat Frage Antwort Gesprächsnotizen',
          excerpt: 'Vorstellungsgespräch',
          engine: 'fake',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result.kind, 'interview');
    expect(result.confidence, greaterThanOrEqualTo(0.72));
  });

  test('adapts OCR language hints from Spanish filename when using default',
      () async {
    var seenHints = '';
    await classifyVideoKind(
      filename: 'equipo_notes.mp4',
      sourceMimeType: 'video/mp4',
      posterBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      ocrImageFn: (bytes, {required languageHints}) async {
        seenHints = languageHints;
        return null;
      },
    );

    expect(seenHints, 'es_en');
  });

  test('keeps custom OCR language hints without override', () async {
    var seenHints = '';
    await classifyVideoKind(
      filename: 'clip.mp4',
      sourceMimeType: 'video/mp4',
      languageHints: 'ja_en',
      posterBytes: Uint8List.fromList(const <int>[1, 2, 3]),
      ocrImageFn: (bytes, {required languageHints}) async {
        seenHints = languageHints;
        return null;
      },
    );

    expect(seenHints, 'ja_en');
  });

  test('defaults to vlog when no strong signal is available', () async {
    final result = await classifyVideoKind(
      filename: 'clip.mp4',
      sourceMimeType: 'video/mp4',
      ocrImageFn: (bytes, {required languageHints}) async => null,
    );

    expect(result.kind, 'vlog');
    expect(result.confidence, greaterThanOrEqualTo(0.5));
    expect(result.keyframeKind, 'scene');
  });
}
