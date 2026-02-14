import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/platform_pdf_ocr.dart';
import 'package:secondloop/features/attachments/video_keyframe_ocr_worker.dart';

void main() {
  test('parseVideoManifestPayload parses valid video manifest', () {
    final manifest = Uint8List.fromList(
      '[{"not":"used"}]'.codeUnits,
    );
    expect(parseVideoManifestPayload(manifest), isNull);

    final valid = Uint8List.fromList(
      '{"schema":"secondloop.video_manifest.v1","original_sha256":"sha-x","original_mime_type":"video/mp4"}'
          .codeUnits,
    );
    final parsed = parseVideoManifestPayload(valid);
    expect(parsed, isNotNull);
    expect(parsed!.originalSha256, 'sha-x');
    expect(parsed.originalMimeType, 'video/mp4');
    expect(parsed.audioSha256, isNull);
    expect(parsed.audioMimeType, isNull);
    expect(parsed.segments.length, 1);
    expect(parsed.segments.first.sha256, 'sha-x');
    expect(parsed.segments.first.mimeType, 'video/mp4');

    final validV2 = Uint8List.fromList(
      '{"schema":"secondloop.video_manifest.v2","video_sha256":"sha-v2","video_mime_type":"video/mp4","audio_sha256":"sha-audio","audio_mime_type":"audio/mp4","video_segments":[{"index":0,"sha256":"sha-v2-seg0","mime_type":"video/mp4"},{"index":1,"sha256":"sha-v2-seg1","mime_type":"video/mp4"}]}'
          .codeUnits,
    );
    final parsedV2 = parseVideoManifestPayload(validV2);
    expect(parsedV2, isNotNull);
    expect(parsedV2!.originalSha256, 'sha-v2');
    expect(parsedV2.originalMimeType, 'video/mp4');
    expect(parsedV2.audioSha256, 'sha-audio');
    expect(parsedV2.audioMimeType, 'audio/mp4');
    expect(parsedV2.segments.length, 2);
    expect(parsedV2.segments.first.sha256, 'sha-v2-seg0');
    expect(parsedV2.segments[1].sha256, 'sha-v2-seg1');

    final v2SegmentsOnly = Uint8List.fromList(
      '{"schema":"secondloop.video_manifest.v2","video_segments":[{"index":0,"sha256":"sha-seg-0","mime_type":"video/mp4"}]}'
          .codeUnits,
    );
    final parsedV2SegmentsOnly = parseVideoManifestPayload(v2SegmentsOnly);
    expect(parsedV2SegmentsOnly, isNotNull);
    expect(parsedV2SegmentsOnly!.originalSha256, 'sha-seg-0');
    expect(parsedV2SegmentsOnly.originalMimeType, 'video/mp4');
    expect(parsedV2SegmentsOnly.segments.length, 1);
    expect(parsedV2SegmentsOnly.segments.first.sha256, 'sha-seg-0');
  });

  test('parseVideoManifestPayload parses preview and proxy fields', () {
    final payload = Uint8List.fromList(
      '{"schema":"secondloop.video_manifest.v2","video_sha256":"sha-video","video_mime_type":"video/mp4","video_kind":"screen_recording","video_kind_confidence":"0.8","poster_sha256":"sha-poster","poster_mime_type":"image/jpeg","video_proxy_sha256":"sha-proxy","video_proxy_max_duration_ms":"60000","video_proxy_max_bytes":"4096","keyframes":[{"index":2,"sha256":"sha-kf-2","mime_type":"image/jpeg","t_ms":"2000","kind":"slide"},{"index":1,"sha256":"sha-kf-1","mime_type":"image/jpeg","t_ms":1000}],"video_segments":[{"index":0,"sha256":"sha-seg-0","mime_type":"video/mp4"}]}'
          .codeUnits,
    );

    final parsed = parseVideoManifestPayload(payload);

    expect(parsed, isNotNull);
    expect(parsed!.videoKind, 'screen_recording');
    expect(parsed.videoKindConfidence, 0.8);
    expect(parsed.posterSha256, 'sha-poster');
    expect(parsed.posterMimeType, 'image/jpeg');
    expect(parsed.videoProxySha256, 'sha-proxy');
    expect(parsed.videoProxyMaxDurationMs, 60000);
    expect(parsed.videoProxyMaxBytes, 4096);
    expect(parsed.keyframes.length, 2);
    expect(parsed.keyframes[0].index, 1);
    expect(parsed.keyframes[0].sha256, 'sha-kf-1');
    expect(parsed.keyframes[0].kind, 'scene');
    expect(parsed.keyframes[1].index, 2);
    expect(parsed.keyframes[1].kind, 'slide');
  });

  test('VideoKeyframeOcrWorker returns null when ffmpeg is unavailable',
      () async {
    final result = await VideoKeyframeOcrWorker.runOnVideoBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      sourceMimeType: 'video/mp4',
      maxFrames: 3,
      frameIntervalSeconds: 5,
      languageHints: 'device_plus_en',
      ffmpegExecutableResolver: () async => null,
    );
    expect(result, isNull);
  });

  test('VideoKeyframeOcrWorker extracts frames and aggregates OCR text',
      () async {
    var ocrCalls = 0;
    final result = await VideoKeyframeOcrWorker.runOnVideoBytes(
      Uint8List.fromList(const <int>[1, 2, 3]),
      sourceMimeType: 'video/mp4',
      maxFrames: 4,
      frameIntervalSeconds: 5,
      languageHints: 'device_plus_en',
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        final outputPattern = arguments.last;
        final frame1 = File(outputPattern.replaceAll('%04d', '0001'));
        final frame2 = File(outputPattern.replaceAll('%04d', '0002'));
        await frame1.parent.create(recursive: true);
        await frame1.writeAsBytes(const <int>[7, 8, 9]);
        await frame2.writeAsBytes(const <int>[10, 11, 12]);
        return ProcessResult(0, 0, '', '');
      },
      ocrImageFn: (bytes, {required languageHints}) async {
        ocrCalls += 1;
        if (ocrCalls == 1) {
          return const PlatformPdfOcrResult(
            fullText: 'hello frame',
            excerpt: 'hello frame',
            engine: 'apple_vision',
            isTruncated: false,
            pageCount: 1,
            processedPages: 1,
          );
        }
        return const PlatformPdfOcrResult(
          fullText: 'world frame',
          excerpt: 'world frame',
          engine: 'apple_vision',
          isTruncated: false,
          pageCount: 1,
          processedPages: 1,
        );
      },
    );

    expect(result, isNotNull);
    expect(result!.engine, 'apple_vision');
    expect(result.frameCount, 2);
    expect(result.processedFrames, 2);
    expect(result.fullText, contains('[frame 1]'));
    expect(result.fullText, contains('hello frame'));
    expect(result.fullText, contains('world frame'));
    expect(ocrCalls, 2);
  });
}
