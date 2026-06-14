import 'dart:typed_data';

import 'package:record/record.dart';

Future<String> startAgentRecordedAudioCapture(
  AudioRecorder recorder, {
  required DateTime startedAt,
}) {
  throw UnsupportedError('agent_audio_recording_not_supported');
}

Future<Uint8List> readAgentRecordedAudioBytes(String path) {
  throw UnsupportedError('agent_audio_recording_not_supported');
}

Future<void> deleteAgentRecordedAudioFile(String path) async {}
