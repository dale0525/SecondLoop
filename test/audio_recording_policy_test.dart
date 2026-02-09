import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/audio_recording_policy.dart';

void main() {
  test('duration shorter than 30 seconds is transcribed as text', () {
    final dispatch = decideAudioRecordingDispatch(
      const Duration(seconds: 29, milliseconds: 999),
    );

    expect(dispatch, AudioRecordingDispatch.transcribeAsText);
  });

  test('duration of 30 seconds or more is sent as audio file', () {
    final atThreshold = decideAudioRecordingDispatch(
      const Duration(seconds: 30),
    );
    final aboveThreshold = decideAudioRecordingDispatch(
      const Duration(seconds: 45),
    );

    expect(atThreshold, AudioRecordingDispatch.sendAsAudioFile);
    expect(aboveThreshold, AudioRecordingDispatch.sendAsAudioFile);
  });
}
