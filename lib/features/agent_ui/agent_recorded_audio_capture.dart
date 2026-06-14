import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:record/record.dart';

import 'agent_recorded_audio_capture_stub.dart'
    if (dart.library.io) 'agent_recorded_audio_capture_io.dart' as impl;

const String kAgentRecordedAudioMimeType = 'audio/mp4';

abstract interface class AgentRecordedAudioCapture {
  Future<bool> hasPermission();

  Future<String> start({required DateTime startedAt});

  Future<String?> stop();

  Future<Uint8List> readBytes(String path);

  Future<void> deleteFile(String path);

  Future<void> dispose();
}

final class RecordPackageAgentRecordedAudioCapture
    implements AgentRecordedAudioCapture {
  RecordPackageAgentRecordedAudioCapture({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<String> start({required DateTime startedAt}) {
    return startAgentRecordedAudioCapture(_recorder, startedAt: startedAt);
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<Uint8List> readBytes(String path) {
    return readAgentRecordedAudioBytes(path);
  }

  @override
  Future<void> deleteFile(String path) {
    return deleteAgentRecordedAudioFile(path);
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

@visibleForTesting
AgentRecordedAudioCapture? debugAgentRecordedAudioCaptureOverride;

AgentRecordedAudioCapture createAgentRecordedAudioCapture() {
  return debugAgentRecordedAudioCaptureOverride ??
      RecordPackageAgentRecordedAudioCapture();
}

Future<String> startAgentRecordedAudioCapture(
  AudioRecorder recorder, {
  required DateTime startedAt,
}) {
  return impl.startAgentRecordedAudioCapture(
    recorder,
    startedAt: startedAt,
  );
}

Future<Uint8List> readAgentRecordedAudioBytes(String path) {
  return impl.readAgentRecordedAudioBytes(path);
}

Future<void> deleteAgentRecordedAudioFile(String path) {
  return impl.deleteAgentRecordedAudioFile(path);
}
