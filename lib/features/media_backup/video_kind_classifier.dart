import 'dart:typed_data';

import '../attachments/platform_pdf_ocr.dart';
import 'video_transcode_worker.dart';

typedef VideoKindOcrImageFn = Future<PlatformPdfOcrResult?> Function(
  Uint8List bytes, {
  required String languageHints,
});

final class VideoKindClassification {
  const VideoKindClassification({
    required this.kind,
    required this.confidence,
  });

  final String kind;
  final double confidence;

  String get keyframeKind => kind == 'screen_recording' ? 'slide' : 'scene';
}

const VideoKindClassification kDefaultVideoKindClassification =
    VideoKindClassification(kind: 'vlog', confidence: 0.55);

Future<VideoKindClassification> classifyVideoKind({
  String? filename,
  required String sourceMimeType,
  Uint8List? posterBytes,
  List<VideoPreviewFrame> keyframes = const <VideoPreviewFrame>[],
  String languageHints = 'device_plus_en',
  VideoKindOcrImageFn? ocrImageFn,
}) async {
  final normalizedMime = sourceMimeType.trim().toLowerCase();
  if (!normalizedMime.startsWith('video/')) {
    return const VideoKindClassification(kind: 'unknown', confidence: 0.0);
  }

  final filenameHit = _classifyFromFilename(filename ?? '');
  if (filenameHit != null) return filenameHit;

  final samples = <Uint8List>[];
  if (posterBytes != null && posterBytes.isNotEmpty) {
    samples.add(posterBytes);
  }
  for (final frame in keyframes.take(3)) {
    if (frame.bytes.isNotEmpty) {
      samples.add(frame.bytes);
    }
  }
  if (samples.isEmpty) {
    return kDefaultVideoKindClassification;
  }

  final runOcr = ocrImageFn ?? PlatformPdfOcr.tryOcrImageBytes;
  final hints = languageHints.trim().isEmpty ? 'device_plus_en' : languageHints;

  var recognizedSamples = 0;
  var totalChars = 0;
  var maxChars = 0;
  var lowDensitySamples = 0;

  for (final sample in samples) {
    PlatformPdfOcrResult? ocr;
    try {
      ocr = await runOcr(sample, languageHints: hints);
    } catch (_) {
      ocr = null;
    }
    if (ocr == null) continue;

    final text = _normalizeWhitespace(ocr.fullText);
    final charCount = _countMeaningfulChars(text);
    if (charCount <= 0) continue;

    recognizedSamples += 1;
    totalChars += charCount;
    if (charCount > maxChars) {
      maxChars = charCount;
    }
    if (charCount >= 18) {
      lowDensitySamples += 1;
    }
  }

  if (recognizedSamples <= 0) {
    return kDefaultVideoKindClassification;
  }

  final averageChars = totalChars / recognizedSamples;

  if (maxChars >= 180 || averageChars >= 96 || totalChars >= 280) {
    return const VideoKindClassification(
      kind: 'screen_recording',
      confidence: 0.86,
    );
  }

  if (maxChars >= 96 || totalChars >= 160) {
    return const VideoKindClassification(
      kind: 'screen_recording',
      confidence: 0.74,
    );
  }

  if (recognizedSamples >= 3 && lowDensitySamples >= 3 && totalChars >= 96) {
    return const VideoKindClassification(
      kind: 'screen_recording',
      confidence: 0.7,
    );
  }

  if (recognizedSamples >= 3 &&
      lowDensitySamples >= 3 &&
      totalChars >= 56 &&
      maxChars >= 18) {
    return const VideoKindClassification(
      kind: 'screen_recording',
      confidence: 0.66,
    );
  }

  if (totalChars <= 24) {
    return const VideoKindClassification(kind: 'vlog', confidence: 0.72);
  }

  return const VideoKindClassification(kind: 'vlog', confidence: 0.62);
}

VideoKindClassification? _classifyFromFilename(String filename) {
  final normalized = filename.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  const screenTokens = <String>{
    'screen recording',
    'screen_recording',
    'screenrecording',
    'screencast',
    'screen capture',
    '录屏',
    '屏幕录制',
    '荧幕录制',
  };
  for (final token in screenTokens) {
    if (normalized.contains(token)) {
      return const VideoKindClassification(
        kind: 'screen_recording',
        confidence: 0.98,
      );
    }
  }

  final cameraRollPattern = RegExp(
    r'(^|[^a-z])(?:vid|mov|img|dji|gopr)_[0-9]{6,}',
    caseSensitive: false,
  );
  if (cameraRollPattern.hasMatch(normalized)) {
    return const VideoKindClassification(kind: 'vlog', confidence: 0.84);
  }

  return null;
}

String _normalizeWhitespace(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _countMeaningfulChars(String text) {
  if (text.isEmpty) return 0;
  final matches = RegExp(
    r'[A-Za-z0-9\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]',
  ).allMatches(text);
  return matches.length;
}
