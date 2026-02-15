import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:secondloop/features/media_backup/video_transcode_worker.dart';

void main() {
  test('VideoTranscodeWorker keeps original bytes when input is not video',
      () async {
    final input = Uint8List.fromList(const <int>[1, 2, 3]);
    final result = await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
      input,
      sourceMimeType: 'application/pdf',
    );

    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'application/pdf');
    expect(result.bytes, input);
    expect(result.segments.length, 1);
    expect(result.isStrictVideoProxy, isFalse);
    expect(result.segments.first.bytes, input);
  });

  test('VideoTranscodeWorker falls back when ffmpeg is unavailable', () async {
    final input = Uint8List.fromList(const <int>[7, 8, 9]);
    final result = await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
      input,
      sourceMimeType: 'video/mp4',
      ffmpegExecutableResolver: () async => null,
    );

    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'video/mp4');
    expect(result.bytes, input);
    expect(result.segments.length, 1);
    expect(result.isStrictVideoProxy, isFalse);
  });

  test('VideoTranscodeResult strict proxy requires transcoded mp4 segments',
      () {
    final valid = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/mp4',
      didTranscode: true,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1]),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(valid.isStrictVideoProxy, isTrue);

    final passthrough = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/mp4',
      didTranscode: false,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1]),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(passthrough.isStrictVideoProxy, isFalse);

    final wrongMime = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/quicktime',
      didTranscode: true,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1]),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(wrongMime.isStrictVideoProxy, isFalse);

    final emptySegment = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/mp4',
      didTranscode: true,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List(0),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(emptySegment.isStrictVideoProxy, isFalse);
  });

  test('VideoTranscodeResult bounded passthrough allows small mp4/mov only',
      () {
    final mp4Passthrough = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/mp4',
      didTranscode: false,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1, 2, 3]),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(
      mp4Passthrough.canUseBoundedPassthroughProxy(maxSegmentBytes: 4),
      isTrue,
    );

    final movPassthrough = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/quicktime',
      didTranscode: false,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1, 2, 3]),
          mimeType: 'video/quicktime',
        ),
      ],
    );
    expect(
      movPassthrough.canUseBoundedPassthroughProxy(maxSegmentBytes: 4),
      isTrue,
    );

    final tooLarge = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/mp4',
      didTranscode: false,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1, 2, 3, 4, 5]),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(
      tooLarge.canUseBoundedPassthroughProxy(maxSegmentBytes: 4),
      isFalse,
    );

    final unsupportedMime = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/webm',
      didTranscode: false,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1]),
          mimeType: 'video/webm',
        ),
      ],
    );
    expect(
      unsupportedMime.canUseBoundedPassthroughProxy(maxSegmentBytes: 4),
      isFalse,
    );

    final transcoded = VideoTranscodeResult(
      bytes: Uint8List.fromList(const <int>[1]),
      mimeType: 'video/mp4',
      didTranscode: true,
      segments: [
        VideoTranscodeSegment(
          index: 0,
          bytes: Uint8List.fromList(const <int>[1]),
          mimeType: 'video/mp4',
        ),
      ],
    );
    expect(
      transcoded.canUseBoundedPassthroughProxy(maxSegmentBytes: 4),
      isFalse,
    );
  });

  test('VideoTranscodeWorker returns segmented mp4 output when ffmpeg succeeds',
      () async {
    final input = Uint8List.fromList(const <int>[11, 12, 13]);

    final result = await VideoTranscodeWorker.transcodeToSegmentedMp4Proxy(
      input,
      sourceMimeType: 'video/quicktime',
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        final segmentPattern = arguments.last;
        final segment0 = File(segmentPattern.replaceAll('%03d', '000'));
        final segment1 = File(segmentPattern.replaceAll('%03d', '001'));

        await segment0.parent.create(recursive: true);
        await segment0.writeAsBytes(const <int>[21, 22, 23]);
        await segment1.writeAsBytes(const <int>[31, 32, 33]);

        return ProcessResult(0, 0, '', '');
      },
    );

    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'video/mp4');
    expect(result.bytes, Uint8List.fromList(const <int>[21, 22, 23]));
    expect(result.segments.length, 2);
    expect(
        result.segments[0].bytes, Uint8List.fromList(const <int>[21, 22, 23]));
    expect(
        result.segments[1].bytes, Uint8List.fromList(const <int>[31, 32, 33]));
    expect(result.isStrictVideoProxy, isTrue);
  });

  test('VideoTranscodeWorker extracts poster and keyframes for previews',
      () async {
    final input = Uint8List.fromList(const <int>[1, 3, 5, 7]);
    var sceneRunCount = 0;
    var fpsRunCount = 0;

    final result = await VideoTranscodeWorker.extractPreviewFrames(
      input,
      sourceMimeType: 'video/mp4',
      maxKeyframes: 3,
      frameIntervalSeconds: 6,
      keyframeKind: 'slide',
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        if (arguments.contains('null') && arguments.last == '-') {
          return ProcessResult(0, 0, '', 'Duration: 00:00:18.00');
        }
        final outputPath = arguments.last;
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);

        if (outputPath.endsWith('poster.jpg')) {
          await outputFile.writeAsBytes(const <int>[9, 9, 9]);
        } else if (outputPath.contains('keyframe_scene_')) {
          sceneRunCount += 1;
          final keyframe0 = File(outputPath.replaceAll('%03d', '000'));
          await keyframe0.writeAsBytes(const <int>[4, 5, 6]);
        } else {
          fpsRunCount += 1;
          final keyframe0 = File(outputPath.replaceAll('%03d', '000'));
          await keyframe0.writeAsBytes(const <int>[4, 5, 6]);
          final keyframe1 = File(outputPath.replaceAll('%03d', '001'));
          await keyframe1.writeAsBytes(const <int>[7, 8, 9]);
        }

        return ProcessResult(0, 0, '', '');
      },
    );

    expect(result.posterBytes, Uint8List.fromList(const <int>[9, 9, 9]));
    expect(result.posterMimeType, 'image/jpeg');
    expect(result.keyframes.length, 2);
    expect(result.keyframes[0].index, 0);
    expect(result.keyframes[0].tMs, 0);
    expect(result.keyframes[0].kind, 'slide');
    expect(result.keyframes[0].bytes, Uint8List.fromList(const <int>[4, 5, 6]));
    expect(result.keyframes[1].index, 1);
    expect(result.keyframes[1].tMs, 6000);
    expect(result.keyframes[1].kind, 'slide');
    expect(result.keyframes[1].bytes, Uint8List.fromList(const <int>[7, 8, 9]));
    expect(sceneRunCount, 1);
    expect(fpsRunCount, 1);
    expect(result.hasAnyPosterOrKeyframe, isTrue);
  });

  test(
      'VideoTranscodeWorker falls back to interval keyframes when scene run fails',
      () async {
    final input = Uint8List.fromList(const <int>[2, 4, 6, 8]);
    var sceneAttempted = false;

    final result = await VideoTranscodeWorker.extractPreviewFrames(
      input,
      sourceMimeType: 'video/mp4',
      maxKeyframes: 2,
      frameIntervalSeconds: 4,
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        if (arguments.contains('null') && arguments.last == '-') {
          return ProcessResult(0, 0, '', 'Duration: 00:08:00.00');
        }
        final filterIndex = arguments.indexOf('-vf');
        if (filterIndex >= 0 && arguments.last.contains('keyframe_fps_')) {
          expect(arguments[filterIndex + 1], 'fps=1/240');
        }
        final outputPath = arguments.last;
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);

        if (outputPath.endsWith('poster.jpg')) {
          await outputFile.writeAsBytes(const <int>[1, 1, 1]);
          return ProcessResult(0, 0, '', '');
        }
        if (outputPath.contains('keyframe_scene_')) {
          sceneAttempted = true;
          return ProcessResult(0, 1, '', 'scene failed');
        }

        final keyframe0 = File(outputPath.replaceAll('%03d', '000'));
        await keyframe0.writeAsBytes(const <int>[8, 8, 8]);
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(sceneAttempted, isTrue);
    expect(result.keyframes.length, 1);
    expect(result.keyframes[0].bytes, Uint8List.fromList(const <int>[8, 8, 8]));
  });

  test('VideoTranscodeWorker uses a larger auto frame budget for long videos',
      () async {
    final input = Uint8List.fromList(const <int>[3, 6, 9, 12]);
    var sawFpsPass = false;

    final result = await VideoTranscodeWorker.extractPreviewFrames(
      input,
      sourceMimeType: 'video/mp4',
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        if (arguments.contains('null') && arguments.last == '-') {
          return ProcessResult(0, 0, '', 'Duration: 00:08:00.00');
        }

        final outputPath = arguments.last;
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);
        if (outputPath.endsWith('poster.jpg')) {
          await outputFile.writeAsBytes(const <int>[1, 2, 3]);
          return ProcessResult(0, 0, '', '');
        }
        if (outputPath.contains('keyframe_scene_')) {
          return ProcessResult(0, 1, '', 'scene failed');
        }

        final filterIndex = arguments.indexOf('-vf');
        expect(filterIndex, greaterThanOrEqualTo(0));
        expect(arguments[filterIndex + 1], 'fps=1/15');
        sawFpsPass = true;
        final keyframe0 = File(outputPath.replaceAll('%03d', '000'));
        await keyframe0.writeAsBytes(const <int>[6, 6, 6]);
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(sawFpsPass, isTrue);
    expect(result.keyframes.length, 1);
  });

  test('VideoTranscodeWorker keeps later frame for incremental slide builds',
      () async {
    final input = Uint8List.fromList(const <int>[12, 13, 14]);
    final earlyFrameBytes = _buildSlideFrameBytes(hasExtraBullet: false);
    final lateFrameBytes = _buildSlideFrameBytes(hasExtraBullet: true);

    final result = await VideoTranscodeWorker.extractPreviewFrames(
      input,
      sourceMimeType: 'video/mp4',
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        if (arguments.contains('null') && arguments.last == '-') {
          return ProcessResult(0, 0, '', 'Duration: 00:08:00.00');
        }

        final outputPath = arguments.last;
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);
        if (outputPath.endsWith('poster.jpg')) {
          await outputFile.writeAsBytes(const <int>[1, 2, 3]);
          return ProcessResult(0, 0, '', '');
        }
        if (outputPath.contains('keyframe_scene_')) {
          return ProcessResult(0, 1, '', 'scene failed');
        }

        final keyframe0 = File(outputPath.replaceAll('%03d', '000'));
        final keyframe1 = File(outputPath.replaceAll('%03d', '001'));
        await keyframe0.writeAsBytes(earlyFrameBytes);
        await keyframe1.writeAsBytes(lateFrameBytes);
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(result.keyframes.length, 1);
    expect(result.keyframes.first.bytes, lateFrameBytes);
  });

  test('VideoTranscodeWorker deduplicates non-contiguous repeated slides',
      () async {
    final input = Uint8List.fromList(const <int>[21, 22, 23]);
    final earlyFrame = _buildSlideFrameBytes(hasExtraBullet: false);
    final frameB = _buildSlideVariantFrame(1);
    final richerRepeatFrame = _buildSlideFrameBytes(hasExtraBullet: true);

    final result = await VideoTranscodeWorker.extractPreviewFrames(
      input,
      sourceMimeType: 'video/mp4',
      ffmpegExecutableResolver: () async => '/tmp/ffmpeg',
      commandRunner: (executable, arguments) async {
        expect(executable, '/tmp/ffmpeg');
        if (arguments.contains('null') && arguments.last == '-') {
          return ProcessResult(0, 0, '', 'Duration: 00:08:00.00');
        }

        final outputPath = arguments.last;
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);
        if (outputPath.endsWith('poster.jpg')) {
          await outputFile.writeAsBytes(const <int>[1, 2, 3]);
          return ProcessResult(0, 0, '', '');
        }
        if (outputPath.contains('keyframe_scene_')) {
          return ProcessResult(0, 1, '', 'scene failed');
        }

        final keyframe0 = File(outputPath.replaceAll('%03d', '000'));
        final keyframe1 = File(outputPath.replaceAll('%03d', '001'));
        final keyframe2 = File(outputPath.replaceAll('%03d', '002'));
        await keyframe0.writeAsBytes(earlyFrame);
        await keyframe1.writeAsBytes(frameB);
        await keyframe2.writeAsBytes(richerRepeatFrame);
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(result.keyframes.length, 2);
    expect(result.keyframes[0].bytes, richerRepeatFrame);
    expect(result.keyframes[1].bytes, frameB);
  });

  test('VideoTranscodeWorker preview extraction returns empty without ffmpeg',
      () async {
    final result = await VideoTranscodeWorker.extractPreviewFrames(
      Uint8List.fromList(const <int>[1, 2, 3]),
      sourceMimeType: 'video/mp4',
      ffmpegExecutableResolver: () async => null,
    );

    expect(result.posterBytes, isNull);
    expect(result.keyframes, isEmpty);
    expect(result.hasAnyPosterOrKeyframe, isFalse);
  });
}

Uint8List _buildSlideFrameBytes({required bool hasExtraBullet}) {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    image,
    x1: 20,
    y1: 20,
    x2: 300,
    y2: 36,
    color: img.ColorRgb8(20, 20, 20),
  );
  img.fillRect(
    image,
    x1: 36,
    y1: 60,
    x2: 280,
    y2: 72,
    color: img.ColorRgb8(30, 30, 30),
  );
  if (hasExtraBullet) {
    img.fillRect(
      image,
      x1: 36,
      y1: 88,
      x2: 260,
      y2: 100,
      color: img.ColorRgb8(30, 30, 30),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

Uint8List _buildSlideVariantFrame(int variant) {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  switch (variant) {
    case 0:
      img.fillRect(
        image,
        x1: 20,
        y1: 20,
        x2: 300,
        y2: 36,
        color: img.ColorRgb8(20, 20, 20),
      );
      img.fillRect(
        image,
        x1: 36,
        y1: 70,
        x2: 280,
        y2: 82,
        color: img.ColorRgb8(30, 30, 30),
      );
      break;
    case 1:
      img.fillRect(
        image,
        x1: 24,
        y1: 24,
        x2: 160,
        y2: 150,
        color: img.ColorRgb8(10, 10, 10),
      );
      img.fillRect(
        image,
        x1: 190,
        y1: 44,
        x2: 300,
        y2: 58,
        color: img.ColorRgb8(30, 30, 30),
      );
      break;
    default:
      throw ArgumentError('Unsupported variant: $variant');
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
