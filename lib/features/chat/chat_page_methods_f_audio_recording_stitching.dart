part of 'chat_page.dart';

const String _kWavAudioMimeType = 'audio/wav';
const Duration _kAudioInterruptionRetryInterval = Duration(seconds: 1);
const MethodChannel _kAudioTranscodeMethodChannel = MethodChannel(
  'secondloop/audio_transcode',
);

enum _AudioInterruptionRecoveryOutcome {
  resumed,
  restarted,
  pending,
}

typedef DecodeAudioSegmentToWavFn = Future<Uint8List> Function(
  Uint8List segmentBytes,
);

typedef TranscodeMergedWavToM4aFn = Future<Uint8List> Function(
  Uint8List mergedWavBytes,
);

final class _RecordedAudioSegmentFileTracker {
  final Set<String> _knownPaths = <String>{};
  final List<String> _orderedPaths = <String>[];

  List<String> get orderedPaths => List<String>.unmodifiable(_orderedPaths);

  void addPath(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (_knownPaths.add(trimmed)) {
      _orderedPaths.add(trimmed);
    }
  }
}

Uint8List extractPcm16Mono16kFromWav(Uint8List wavBytes) {
  if (wavBytes.lengthInBytes < 44) return Uint8List(0);

  String readChunkId(int offset) {
    if (offset + 4 > wavBytes.lengthInBytes) return '';
    return ascii.decode(
      wavBytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
  }

  final header = ByteData.sublistView(wavBytes);
  if (readChunkId(0) != 'RIFF' || readChunkId(8) != 'WAVE') {
    return Uint8List(0);
  }

  int? audioFormat;
  int? numChannels;
  int? sampleRate;
  int? bitsPerSample;
  Uint8List? pcmBytes;

  var offset = 12;
  while (offset + 8 <= wavBytes.lengthInBytes) {
    final chunkId = readChunkId(offset);
    final chunkSize = header.getUint32(offset + 4, Endian.little);
    final chunkDataOffset = offset + 8;
    final chunkDataEnd = chunkDataOffset + chunkSize;
    if (chunkDataEnd > wavBytes.lengthInBytes) {
      return Uint8List(0);
    }

    if (chunkId == 'fmt ' && chunkSize >= 16) {
      final fmt = ByteData.sublistView(
        wavBytes,
        chunkDataOffset,
        chunkDataOffset + 16,
      );
      audioFormat = fmt.getUint16(0, Endian.little);
      numChannels = fmt.getUint16(2, Endian.little);
      sampleRate = fmt.getUint32(4, Endian.little);
      bitsPerSample = fmt.getUint16(14, Endian.little);
    } else if (chunkId == 'data') {
      pcmBytes = Uint8List.fromList(
        wavBytes.sublist(chunkDataOffset, chunkDataEnd),
      );
    }

    final paddedChunkSize = chunkSize.isOdd ? chunkSize + 1 : chunkSize;
    offset = chunkDataOffset + paddedChunkSize;
  }

  final isExpectedFormat = audioFormat == 1 &&
      numChannels == 1 &&
      sampleRate == 16000 &&
      bitsPerSample == 16;
  if (!isExpectedFormat || pcmBytes == null || pcmBytes.isEmpty) {
    return Uint8List(0);
  }
  return pcmBytes;
}

Uint8List buildWavFromPcm16Mono16k(List<Uint8List> pcmChunks) {
  final combined = BytesBuilder(copy: false);
  for (final chunk in pcmChunks) {
    if (chunk.isEmpty) continue;
    combined.add(chunk);
  }
  final pcmBytes = combined.takeBytes();
  if (pcmBytes.isEmpty) return Uint8List(0);

  final dataSize = pcmBytes.lengthInBytes;
  const byteRate = 16000 * 1 * 16 ~/ 8;
  const blockAlign = 1 * 16 ~/ 8;

  final header = ByteData(44)
    ..setUint8(0, 0x52)
    ..setUint8(1, 0x49)
    ..setUint8(2, 0x46)
    ..setUint8(3, 0x46)
    ..setUint32(4, 36 + dataSize, Endian.little)
    ..setUint8(8, 0x57)
    ..setUint8(9, 0x41)
    ..setUint8(10, 0x56)
    ..setUint8(11, 0x45)
    ..setUint8(12, 0x66)
    ..setUint8(13, 0x6d)
    ..setUint8(14, 0x74)
    ..setUint8(15, 0x20)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, byteRate, Endian.little)
    ..setUint16(32, blockAlign, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint8(36, 0x64)
    ..setUint8(37, 0x61)
    ..setUint8(38, 0x74)
    ..setUint8(39, 0x61)
    ..setUint32(40, dataSize, Endian.little);

  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(pcmBytes);
  return out.takeBytes();
}

Future<Uint8List> stitchAudioRecordingSegmentsAsM4a(
  List<Uint8List> segmentBytes, {
  required DecodeAudioSegmentToWavFn decodeSegmentToWav,
  required TranscodeMergedWavToM4aFn transcodeMergedWavToM4a,
}) async {
  if (segmentBytes.isEmpty) return Uint8List(0);
  if (segmentBytes.length == 1) {
    return Uint8List.fromList(segmentBytes.first);
  }

  final pcmChunks = <Uint8List>[];
  for (final segment in segmentBytes) {
    if (segment.isEmpty) continue;
    final wavBytes = await decodeSegmentToWav(segment);
    final pcm = extractPcm16Mono16kFromWav(wavBytes);
    if (pcm.isNotEmpty) {
      pcmChunks.add(pcm);
    }
  }

  if (pcmChunks.isEmpty) return Uint8List(0);

  final mergedWav = buildWavFromPcm16Mono16k(pcmChunks);
  if (mergedWav.isEmpty) return Uint8List(0);

  return transcodeMergedWavToM4a(mergedWav);
}

extension _ChatPageStateMethodsFAudioRecordingStitching on _ChatPageState {
  Future<bool> _safeAudioRecorderIsRecording() async {
    try {
      return await _audioRecorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  Future<List<Uint8List>> _readRecordedAudioSegmentBytes(
    List<String> segmentPaths,
  ) async {
    final segments = <Uint8List>[];
    for (final path in segmentPaths) {
      if (path.trim().isEmpty) continue;
      try {
        final bytes = await File(path).readAsBytes();
        if (bytes.isNotEmpty) {
          segments.add(bytes);
        }
      } catch (_) {
        // Ignore unreadable segments and continue with remaining ones.
      }
    }
    return segments;
  }

  Future<Uint8List> _stitchRecordedAudioSegmentsToM4a(
    List<Uint8List> segmentBytes,
  ) async {
    if (segmentBytes.isEmpty) return Uint8List(0);
    if (segmentBytes.length == 1) {
      return Uint8List.fromList(segmentBytes.first);
    }

    return stitchAudioRecordingSegmentsAsM4a(
      segmentBytes,
      decodeSegmentToWav: _decodeRecordedSegmentToWavMono16k,
      transcodeMergedWavToM4a: _transcodeMergedWavToRecordedAudio,
    );
  }

  Future<Uint8List> _decodeRecordedSegmentToWavMono16k(
    Uint8List segmentBytes,
  ) async {
    if (segmentBytes.isEmpty) return Uint8List(0);

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('secondloop_record_');
      final sourcePath =
          '${tempDir.path}/segment.${_audioFileExt(_kRecordedAudioMimeType)}';
      final outputPath = '${tempDir.path}/segment.wav';

      await File(sourcePath).writeAsBytes(segmentBytes, flush: true);
      final ok = await _kAudioTranscodeMethodChannel.invokeMethod<bool>(
        'decodeToWavPcm16Mono16k',
        <String, Object?>{
          'input_path': sourcePath,
          'output_path': outputPath,
        },
      );

      if (ok != true) return Uint8List(0);

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) return Uint8List(0);
      final wavBytes = await outputFile.readAsBytes();
      if (wavBytes.isEmpty) return Uint8List(0);
      return wavBytes;
    } on MissingPluginException {
      return Uint8List(0);
    } on PlatformException {
      return Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // Ignore temp cleanup failures.
        }
      }
    }
  }

  Future<Uint8List> _transcodeMergedWavToRecordedAudio(
    Uint8List mergedWavBytes,
  ) async {
    if (mergedWavBytes.isEmpty) return Uint8List(0);
    final result = await AudioTranscodeWorker.transcodeToM4aProxy(
      mergedWavBytes,
      sourceMimeType: _kWavAudioMimeType,
    );
    return result.bytes;
  }

  String _audioFileExt(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    switch (normalized) {
      case 'audio/mp4':
      case 'audio/m4a':
      case 'audio/x-m4a':
        return 'm4a';
      case 'audio/wav':
      case 'audio/wave':
      case 'audio/x-wav':
        return 'wav';
      default:
        return 'bin';
    }
  }
}
