import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_page.dart';

void main() {
  group('formatAudioRecordingElapsed', () {
    test('formats mm:ss for durations under one hour', () {
      expect(formatAudioRecordingElapsed(const Duration(seconds: 0)), '00:00');
      expect(
        formatAudioRecordingElapsed(const Duration(minutes: 4, seconds: 9)),
        '04:09',
      );
    });

    test('formats hh:mm:ss for durations over one hour', () {
      expect(
        formatAudioRecordingElapsed(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '01:02:03',
      );
    });
  });

  group('normalizeAudioRecordingAmplitude', () {
    test('clamps to [0, 1] from dbfs values', () {
      expect(normalizeAudioRecordingAmplitude(0), 1.0);
      expect(normalizeAudioRecordingAmplitude(-60), 0.0);
      expect(normalizeAudioRecordingAmplitude(-120), 0.0);
      expect(normalizeAudioRecordingAmplitude(5), 1.0);
      expect(normalizeAudioRecordingAmplitude(-30), closeTo(0.5, 0.0001));
    });
  });

  group('audio failure classification', () {
    test('classifies key error families', () {
      expect(
        classifyAudioRecordingFailure('permission_denied'),
        AudioRecordingFailureKind.permissionDenied,
      );
      expect(
        classifyAudioRecordingFailure('network timeout while uploading'),
        AudioRecordingFailureKind.network,
      );
      expect(
        classifyAudioRecordingFailure('microphone is busy'),
        AudioRecordingFailureKind.microphoneBusy,
      );
      expect(
        classifyAudioRecordingFailure('no input device found'),
        AudioRecordingFailureKind.noMicrophone,
      );
      expect(
        classifyAudioRecordingFailure('recording_bytes_empty'),
        AudioRecordingFailureKind.emptyRecording,
      );
    });

    test('exposes retry and settings suggestions', () {
      expect(
        canRetryAudioFailure(AudioRecordingFailureKind.network),
        isTrue,
      );
      expect(
        canRetryAudioFailure(AudioRecordingFailureKind.microphoneBusy),
        isTrue,
      );
      expect(
        canRetryAudioFailure(AudioRecordingFailureKind.permissionDenied),
        isFalse,
      );

      expect(
        shouldOpenMicrophoneSettings(
            AudioRecordingFailureKind.permissionDenied),
        isTrue,
      );
      expect(
        shouldOpenMicrophoneSettings(AudioRecordingFailureKind.noMicrophone),
        isTrue,
      );
      expect(
        shouldOpenMicrophoneSettings(AudioRecordingFailureKind.network),
        isFalse,
      );
    });
  });

  group('shouldKeepScreenAwakeDuringRecording', () {
    test('returns true for non-web environments', () {
      expect(
        shouldKeepScreenAwakeDuringRecording(isWeb: false),
        isTrue,
      );
    });

    test('returns false for web environments', () {
      expect(
        shouldKeepScreenAwakeDuringRecording(isWeb: true),
        isFalse,
      );
    });
  });

  group('audio interruption ui helpers', () {
    test('status hint prioritizes interruption recovery states', () {
      const defaultHint = 'default';
      const pausedHint = 'paused';
      const interruptionHint = 'interruption';
      const recoveringHint = 'recovering';

      expect(
        buildAudioRecordingStatusHint(
          interruptedBySystem: true,
          recoveringInterruption: true,
          paused: true,
          defaultHint: defaultHint,
          pausedHint: pausedHint,
          interruptionHint: interruptionHint,
          recoveringHint: recoveringHint,
        ),
        recoveringHint,
      );

      expect(
        buildAudioRecordingStatusHint(
          interruptedBySystem: true,
          recoveringInterruption: false,
          paused: false,
          defaultHint: defaultHint,
          pausedHint: pausedHint,
          interruptionHint: interruptionHint,
          recoveringHint: recoveringHint,
        ),
        interruptionHint,
      );

      expect(
        buildAudioRecordingStatusHint(
          interruptedBySystem: false,
          recoveringInterruption: false,
          paused: true,
          defaultHint: defaultHint,
          pausedHint: pausedHint,
          interruptionHint: interruptionHint,
          recoveringHint: recoveringHint,
        ),
        pausedHint,
      );

      expect(
        buildAudioRecordingStatusHint(
          interruptedBySystem: false,
          recoveringInterruption: false,
          paused: false,
          defaultHint: defaultHint,
          pausedHint: pausedHint,
          interruptionHint: interruptionHint,
          recoveringHint: recoveringHint,
        ),
        defaultHint,
      );
    });

    test('pause resume button disabled during recovery and system pause', () {
      expect(
        shouldDisableAudioPauseResumeButton(
          togglingPause: true,
          recoveringInterruption: false,
          interruptedBySystem: false,
          pausedByUser: false,
        ),
        isTrue,
      );

      expect(
        shouldDisableAudioPauseResumeButton(
          togglingPause: false,
          recoveringInterruption: true,
          interruptedBySystem: false,
          pausedByUser: false,
        ),
        isTrue,
      );

      expect(
        shouldDisableAudioPauseResumeButton(
          togglingPause: false,
          recoveringInterruption: false,
          interruptedBySystem: true,
          pausedByUser: false,
        ),
        isTrue,
      );

      expect(
        shouldDisableAudioPauseResumeButton(
          togglingPause: false,
          recoveringInterruption: false,
          interruptedBySystem: true,
          pausedByUser: true,
        ),
        isFalse,
      );
    });
  });

  group('wav stitching helpers', () {
    test('buildWavFromPcm16Mono16k and extractPcm16Mono16kFromWav roundtrip',
        () {
      final first = Uint8List.fromList(const <int>[1, 2, 3, 4]);
      final second = Uint8List.fromList(const <int>[9, 8, 7, 6]);

      final wav = buildWavFromPcm16Mono16k(<Uint8List>[first, second]);

      expect(wav, isNotEmpty);
      expect(
        extractPcm16Mono16kFromWav(wav),
        Uint8List.fromList(const <int>[1, 2, 3, 4, 9, 8, 7, 6]),
      );
    });

    test('extractPcm16Mono16kFromWav rejects invalid payload', () {
      final invalid = Uint8List.fromList(const <int>[1, 2, 3]);
      expect(extractPcm16Mono16kFromWav(invalid), isEmpty);
    });
  });

  group('stitchAudioRecordingSegmentsAsM4a', () {
    test('decodes each segment then transcodes merged wav once', () async {
      final decodedInputs = <int>[];
      Uint8List? mergedWavSeenByTranscoder;

      final result = await stitchAudioRecordingSegmentsAsM4a(
        <Uint8List>[
          Uint8List.fromList(const <int>[10]),
          Uint8List.fromList(const <int>[20]),
        ],
        decodeSegmentToWav: (segmentBytes) async {
          decodedInputs.add(segmentBytes.first);
          return buildWavFromPcm16Mono16k(
            <Uint8List>[
              Uint8List.fromList(
                  <int>[segmentBytes.first, segmentBytes.first + 1]),
            ],
          );
        },
        transcodeMergedWavToM4a: (mergedWavBytes) async {
          mergedWavSeenByTranscoder = mergedWavBytes;
          final pcm = extractPcm16Mono16kFromWav(mergedWavBytes);
          return Uint8List.fromList(<int>[0xEE, ...pcm]);
        },
      );

      expect(decodedInputs, const <int>[10, 20]);
      expect(mergedWavSeenByTranscoder, isNotNull);
      expect(
        extractPcm16Mono16kFromWav(mergedWavSeenByTranscoder!),
        Uint8List.fromList(const <int>[10, 11, 20, 21]),
      );
      expect(result, Uint8List.fromList(const <int>[0xEE, 10, 11, 20, 21]));
    });

    test('returns original bytes when only one segment is provided', () async {
      var decodeCalls = 0;
      var transcodeCalls = 0;
      final single = Uint8List.fromList(const <int>[4, 5, 6]);

      final result = await stitchAudioRecordingSegmentsAsM4a(
        <Uint8List>[single],
        decodeSegmentToWav: (segmentBytes) async {
          decodeCalls += 1;
          return segmentBytes;
        },
        transcodeMergedWavToM4a: (mergedWavBytes) async {
          transcodeCalls += 1;
          return mergedWavBytes;
        },
      );

      expect(decodeCalls, 0);
      expect(transcodeCalls, 0);
      expect(result, single);
    });

    test('returns empty when no segment can be decoded', () async {
      final result = await stitchAudioRecordingSegmentsAsM4a(
        <Uint8List>[
          Uint8List.fromList(const <int>[1]),
          Uint8List.fromList(const <int>[2]),
        ],
        decodeSegmentToWav: (_) async => Uint8List(0),
        transcodeMergedWavToM4a: (mergedWavBytes) async => mergedWavBytes,
      );

      expect(result, isEmpty);
    });
  });
}
