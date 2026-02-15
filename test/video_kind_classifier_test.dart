import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/features/media_backup/video_kind_classifier.dart';
import 'package:secondloop/features/media_backup/video_transcode_worker.dart';

void main() {
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

  test('classifies screen recording when OCR text density is high', () async {
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

    expect(result.kind, 'screen_recording');
    expect(result.confidence, greaterThanOrEqualTo(0.7));
    expect(result.keyframeKind, 'slide');
  });

  test('classifies screen recording for sparse slide text across samples',
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
          'Agenda Q1 milestones',
          'Demo architecture flow',
          'Summary next actions',
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
    expect(result.confidence, greaterThanOrEqualTo(0.6));
    expect(result.keyframeKind, 'slide');
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
