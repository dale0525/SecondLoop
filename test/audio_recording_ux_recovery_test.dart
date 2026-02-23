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
}
