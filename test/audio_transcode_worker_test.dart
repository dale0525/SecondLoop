import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/media_backup/audio_transcode_worker.dart';

void main() {
  tearDown(() {
    AudioTranscodeWorker.debugUseNativeTranscodeOverride = null;
    AudioTranscodeWorker.debugPreferVideoManifestWavProxyOverride = null;
    AudioTranscodeWorker.debugNativeTranscodeOverride = null;
    AudioTranscodeWorker.debugNativeDecodeToWavOverride = null;
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

  test('AudioTranscodeWorker stops retrying when transcode call times out',
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
        throw TimeoutException('native transcode timed out');
      },
    );

    expect(attempts, 1);
    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, original);
  });

  test('AudioTranscodeWorker aligns audio/mp4 extension with local decode path',
      () {
    expect(AudioTranscodeWorker.debugExtensionForMimeType('audio/mp4'), 'm4a');
    expect(AudioTranscodeWorker.debugExtensionForMimeType('audio/m4a'), 'm4a');
    expect(
        AudioTranscodeWorker.debugExtensionForMimeType('audio/x-m4a'), 'm4a');
    expect(AudioTranscodeWorker.debugExtensionForMimeType('video/mp4'), 'mp4');
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

  test(
      'AudioTranscodeWorker falls back to native wav extraction for video when m4a transcode fails',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 2));
    final wavBytes = Uint8List.fromList(const <int>[0x52, 0x49, 0x46, 0x46]);
    var transcodeAttempts = 0;
    var decodeAttempts = 0;

    AudioTranscodeWorker.debugUseNativeTranscodeOverride = true;
    AudioTranscodeWorker.debugNativeTranscodeOverride = (
      bytes, {
      required sourceMimeType,
      required targetSampleRateHz,
      required targetBitrateKbps,
      required mono,
    }) async {
      transcodeAttempts += 1;
      return Uint8List(0);
    };
    AudioTranscodeWorker.debugNativeDecodeToWavOverride = (
      bytes, {
      required sourceMimeType,
      maxDecodedWavBytes,
    }) async {
      decodeAttempts += 1;
      expect(sourceMimeType, 'video/mp4');
      return wavBytes;
    };

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'video/mp4',
    );

    expect(transcodeAttempts, 3);
    expect(decodeAttempts, 1);
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, wavBytes);
  });

  test(
      'AudioTranscodeWorker can prefer direct wav extraction for mobile video manifests',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 3));
    final primarySegment = Uint8List.fromList(List<int>.filled(24, 5));
    final wavFallback = Uint8List.fromList(const <int>[0x52, 0x49, 0x46, 0x46]);
    var transcodeCalls = 0;
    final decodeSources = <String>[];

    AudioTranscodeWorker.debugUseNativeTranscodeOverride = true;
    AudioTranscodeWorker.debugPreferVideoManifestWavProxyOverride = true;
    AudioTranscodeWorker.debugNativeTranscodeOverride = (
      bytes, {
      required sourceMimeType,
      required targetSampleRateHz,
      required targetBitrateKbps,
      required mono,
    }) async {
      transcodeCalls += 1;
      return Uint8List(0);
    };
    AudioTranscodeWorker.debugNativeDecodeToWavOverride = (
      bytes, {
      required sourceMimeType,
      maxDecodedWavBytes,
    }) async {
      decodeSources.add(sourceMimeType);
      if (sourceMimeType == 'video/mp4' && identical(bytes, primarySegment)) {
        return wavFallback;
      }
      return Uint8List(0);
    };

    final result = await AudioTranscodeWorker.transcodeVideoAudioForManifest(
      original,
      originalMimeType: 'video/mp4',
      primarySegmentBytes: primarySegment,
      primarySegmentMimeType: 'video/mp4',
    );

    expect(transcodeCalls, 0);
    expect(decodeSources, ['video/mp4']);
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, wavFallback);
  });

  test(
      'AudioTranscodeWorker uses unlimited decode limit when falling back to original video',
      () async {
    final original = Uint8List.fromList(List<int>.filled(80, 9));
    final primarySegment = Uint8List.fromList(List<int>.filled(24, 5));
    final wavFromOriginal =
        Uint8List.fromList(const <int>[0x52, 0x49, 0x46, 0x46, 0x00]);
    final decodeLimits = <({String sourceMimeType, int? maxDecodedWavBytes})>[];

    AudioTranscodeWorker.debugUseNativeTranscodeOverride = true;
    AudioTranscodeWorker.debugPreferVideoManifestWavProxyOverride = true;
    AudioTranscodeWorker.debugNativeDecodeToWavOverride = (
      bytes, {
      required sourceMimeType,
      maxDecodedWavBytes,
    }) async {
      decodeLimits.add(
        (
          sourceMimeType: sourceMimeType,
          maxDecodedWavBytes: maxDecodedWavBytes,
        ),
      );
      if (identical(bytes, primarySegment)) {
        return Uint8List(0);
      }
      if (identical(bytes, original)) {
        return wavFromOriginal;
      }
      return Uint8List(0);
    };

    final result = await AudioTranscodeWorker.transcodeVideoAudioForManifest(
      original,
      originalMimeType: 'video/quicktime',
      primarySegmentBytes: primarySegment,
      primarySegmentMimeType: 'video/mp4',
    );

    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, wavFromOriginal);
    expect(decodeLimits, [
      (sourceMimeType: 'video/mp4', maxDecodedWavBytes: null),
      (sourceMimeType: 'video/quicktime', maxDecodedWavBytes: 0),
    ]);
  });

  test(
      'AudioTranscodeWorker prefers primary video segment for audio extraction',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 3));
    final primarySegment = Uint8List.fromList(List<int>.filled(24, 5));
    final extracted = Uint8List.fromList(const <int>[9, 8, 7]);
    final attemptedSources = <String>[];

    final result = await AudioTranscodeWorker.transcodeVideoAudioForManifest(
      original,
      originalMimeType: 'video/quicktime',
      primarySegmentBytes: primarySegment,
      primarySegmentMimeType: 'video/mp4',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        attemptedSources.add(sourceMimeType);
        if (!identical(bytes, primarySegment)) {
          fail(
              'should not attempt original bytes when primary segment succeeds');
        }
        return extracted;
      },
    );

    expect(attemptedSources, ['video/mp4']);
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, extracted);
  });

  test(
      'AudioTranscodeWorker falls back to wav when transcoded proxy is not decodable',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 3));
    final primarySegment = Uint8List.fromList(List<int>.filled(24, 5));
    final transcoded = Uint8List.fromList(const <int>[9, 8, 7, 6]);
    final wavFallback = Uint8List.fromList(const <int>[0x52, 0x49, 0x46, 0x46]);
    var transcodeCalls = 0;
    final decodeSources = <String>[];

    AudioTranscodeWorker.debugUseNativeTranscodeOverride = true;
    AudioTranscodeWorker.debugNativeTranscodeOverride = (
      bytes, {
      required sourceMimeType,
      required targetSampleRateHz,
      required targetBitrateKbps,
      required mono,
    }) async {
      transcodeCalls += 1;
      return transcoded;
    };
    AudioTranscodeWorker.debugNativeDecodeToWavOverride = (
      bytes, {
      required sourceMimeType,
      maxDecodedWavBytes,
    }) async {
      decodeSources.add(sourceMimeType);
      if (sourceMimeType == 'audio/mp4') {
        return Uint8List(0);
      }
      if (sourceMimeType == 'video/mp4') {
        return wavFallback;
      }
      return Uint8List(0);
    };

    final result = await AudioTranscodeWorker.transcodeVideoAudioForManifest(
      original,
      originalMimeType: 'video/mp4',
      primarySegmentBytes: primarySegment,
      primarySegmentMimeType: 'video/mp4',
    );

    expect(transcodeCalls, 1);
    expect(decodeSources, ['audio/mp4', 'video/mp4']);
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, wavFallback);
  });

  test(
      'AudioTranscodeWorker retries original video when primary segment extract fails',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 3));
    final primarySegment = Uint8List.fromList(List<int>.filled(24, 5));
    final extractedFromOriginal = Uint8List.fromList(const <int>[4, 5, 6]);
    final attemptedSources = <String>[];

    final result = await AudioTranscodeWorker.transcodeVideoAudioForManifest(
      original,
      originalMimeType: 'video/quicktime',
      primarySegmentBytes: primarySegment,
      primarySegmentMimeType: 'video/mp4',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        attemptedSources.add(sourceMimeType);
        if (identical(bytes, primarySegment)) {
          return Uint8List(0);
        }
        if (identical(bytes, original)) {
          return extractedFromOriginal;
        }
        fail('unexpected source bytes');
      },
    );

    expect(
      attemptedSources,
      ['video/mp4', 'video/mp4', 'video/mp4', 'video/quicktime'],
    );
    expect(result.didTranscode, isTrue);
    expect(result.mimeType, 'audio/mp4');
    expect(result.bytes, extractedFromOriginal);
  });

  test(
      'AudioTranscodeWorker avoids duplicate extraction when primary segment equals original source',
      () async {
    final source = Uint8List.fromList(List<int>.filled(48, 3));
    var attempts = 0;

    final result = await AudioTranscodeWorker.transcodeVideoAudioForManifest(
      source,
      originalMimeType: 'video/mp4',
      primarySegmentBytes: source,
      primarySegmentMimeType: 'video/mp4',
      transcode: (
        bytes, {
        required sourceMimeType,
        required targetSampleRateHz,
        required targetBitrateKbps,
        required mono,
      }) async {
        attempts += 1;
        return Uint8List(0);
      },
    );

    expect(attempts, 3);
    expect(result.didTranscode, isFalse);
  });

  test(
      'AudioTranscodeWorker skips wav fallback extraction for non-video sources',
      () async {
    final original = Uint8List.fromList(List<int>.filled(48, 2));
    var decodeAttempts = 0;

    AudioTranscodeWorker.debugUseNativeTranscodeOverride = true;
    AudioTranscodeWorker.debugNativeTranscodeOverride = (
      bytes, {
      required sourceMimeType,
      required targetSampleRateHz,
      required targetBitrateKbps,
      required mono,
    }) async {
      return Uint8List(0);
    };
    AudioTranscodeWorker.debugNativeDecodeToWavOverride = (
      bytes, {
      required sourceMimeType,
      maxDecodedWavBytes,
    }) async {
      decodeAttempts += 1;
      return Uint8List.fromList(const <int>[1, 2, 3]);
    };

    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      original,
      sourceMimeType: 'audio/wav',
    );

    expect(decodeAttempts, 0);
    expect(result.didTranscode, isFalse);
    expect(result.mimeType, 'audio/wav');
    expect(result.bytes, original);
  });
}
