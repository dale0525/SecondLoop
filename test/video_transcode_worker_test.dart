import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
}
