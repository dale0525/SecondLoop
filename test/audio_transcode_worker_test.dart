import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/media_backup/audio_transcode_worker.dart';

void main() {
  tearDown(() {
    AudioTranscodeWorker.debugUseNativeTranscodeOverride = null;
    AudioTranscodeWorker.debugNativeTranscodeOverride = null;
    AudioTranscodeWorker.debugFfmpegExecutableResolver = null;
  });

  test('AudioTranscodeWorker transcodes audio to m4a proxy', () async {
    final original = Uint8List.fromList(List<int>.filled(256, 7));
    final transcoded = Uint8List.fromList(<int>[
      0x00, 0x00, 0x00, 0x18, // ftyp box size
      0x66, 0x74, 0x79, 0x70, // ftyp
      0x4D, 0x34, 0x41, 0x20, // M4A
      0x69, 0x73, 0x6F, 0x6D,
    ]);

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/mpeg',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        expect(sourceMimeType, 'audio/mpeg');
        expect(targetSampleRateHz, 24000);
        expect(targetBitrateKbps, 48);
        expect(mono, isTrue);
        return transcoded;
      },
    );

    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, transcoded);
  });

  test(
      'AudioTranscodeWorker retries local transcode and keeps original when all attempts fail',
      () async {
    final original = Uint8List.fromList(List<int>.filled(64, 9));
    var attempts = 0;

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        attempts += 1;
        throw StateError('transcode_failed');
      },
    );

    expect(attempts, 3);
    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, original);
  });

  test(
      'AudioTranscodeWorker retries local transcode and succeeds on later attempt',
      () async {
    final original = Uint8List.fromList(List<int>.filled(64, 9));
    var attempts = 0;
    final transcoded = Uint8List.fromList(const <int>[9, 8, 7, 6]);

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        attempts += 1;
        if (attempts < 3) return Uint8List(0);
        return transcoded;
      },
    );

    expect(attempts, 3);
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, transcoded);
  });

  test('AudioTranscodeWorker normalizes audio MIME aliases on fallback',
      () async {
    final original = Uint8List.fromList(List<int>.filled(64, 9));

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/x-m4a',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        throw StateError('transcode_failed');
      },
    );

    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, original);
  });

  test('AudioTranscodeWorker skips non audio/video mime types', () async {
    final original = Uint8List.fromList(List<int>.filled(16, 3));
    var called = false;

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'application/pdf',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        called = true;
        return Uint8List(0);
      },
    );

    expect(called, isFalse);
    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'application/pdf');
    expect(result.bytes, original);
  });

  test(
      'AudioTranscodeWorker default path executes bundled ffmpeg command runner',
      () async {
    final original = Uint8List.fromList(List<int>.filled(96, 5));
    final expected = Uint8List.fromList(<int>[
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

    String? capturedExecutable;
    List<String>? capturedArgs;
    AudioTranscodeWorker.debugUseNativeTranscodeOverride = false;
    AudioTranscodeWorker.debugFfmpegExecutableResolver =
        () async => '/tmp/secondloop/ffmpeg';
    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
      commandRunner: (executable, arguments) async {
        capturedExecutable = executable;
        capturedArgs = List<String>.from(arguments);
        final outputPath = arguments.last;
        await File(outputPath).writeAsBytes(expected);
        return ProcessResult(123, 0, '', '');
      },
    );

    expect(capturedExecutable, '/tmp/secondloop/ffmpeg');
    expect(capturedArgs, isNotNull);
    expect(capturedArgs, containsAllInOrder(['-i']));
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, expected);
  });

  test('AudioTranscodeWorker default path falls back on ffmpeg failure',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 2));
    AudioTranscodeWorker.debugUseNativeTranscodeOverride = false;
    AudioTranscodeWorker.debugFfmpegExecutableResolver =
        () async => '/tmp/secondloop/ffmpeg';

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
      commandRunner: (executable, arguments) async {
        return ProcessResult(123, 1, '', 'boom');
      },
    );

    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, original);
  });

  test('AudioTranscodeWorker keeps original when bundled ffmpeg is unavailable',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 2));
    var called = false;
    AudioTranscodeWorker.debugUseNativeTranscodeOverride = false;
    AudioTranscodeWorker.debugFfmpegExecutableResolver = () async => null;

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
      commandRunner: (executable, arguments) async {
        called = true;
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(called, isFalse);
    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, original);
  });

  test('AudioTranscodeWorker uses native transcode path when enabled',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 2));
    final transcoded = Uint8List.fromList(const <int>[9, 8, 7, 6]);
    AudioTranscodeWorker.debugUseNativeTranscodeOverride = true;
    AudioTranscodeWorker.debugNativeTranscodeOverride = (
      bytes, {
      required sourceMimeType,
      required targetSampleRateHz,
      required targetBitrateKbps,
      required mono,
    }) async {
      expect(sourceMimeType, 'audio/wav');
      expect(targetSampleRateHz, 24000);
      expect(targetBitrateKbps, 48);
      expect(mono, isTrue);
      return transcoded;
    };

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
      commandRunner: (executable, arguments) async {
        fail('command runner should not be called in native mode');
      },
    );

    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, transcoded);
  });
}
