import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

Future<String> startAgentRecordedAudioCapture(
  AudioRecorder recorder, {
  required DateTime startedAt,
}) async {
  final tempDir = await getTemporaryDirectory();
  final filePath =
      '${tempDir.path}/secondloop_record_${startedAt.millisecondsSinceEpoch}.m4a';
  await recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 16000,
      numChannels: 1,
    ),
    path: filePath,
  );
  return filePath;
}

Future<Uint8List> readAgentRecordedAudioBytes(String path) {
  return File(path).readAsBytes();
}

Future<void> deleteAgentRecordedAudioFile(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;
  try {
    await File(trimmed).delete();
  } catch (_) {
    // Best-effort cleanup only.
  }
}
