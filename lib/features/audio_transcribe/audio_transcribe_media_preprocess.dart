import 'dart:convert';
import 'dart:typed_data';

const int kAudioTranscribePcmBytesPerSecond = 32000;
const int kAudioTranscribePcmBytesPerSample = 2;
const int kAudioTranscribeWavHeaderBytes = 44;
const int kRemoteTranscribeChunkMs = 10 * 60 * 1000;

final class AudioTranscribeWavChunk {
  const AudioTranscribeWavChunk({
    required this.wavBytes,
    required this.offsetMs,
    required this.durationMs,
  });

  final Uint8List wavBytes;
  final int offsetMs;
  final int durationMs;
}

bool shouldBypassLocalRuntimeDecodeForWav({
  required String mimeType,
  required Uint8List audioBytes,
}) {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  final isWavMimeType = normalizedMimeType == 'audio/wav' ||
      normalizedMimeType == 'audio/wave' ||
      normalizedMimeType == 'audio/x-wav';
  if (!isWavMimeType) {
    return false;
  }
  return isCanonicalPcm16Mono16kWavBytes(audioBytes);
}

bool isCanonicalPcm16Mono16kWavBytes(Uint8List bytes) {
  if (bytes.lengthInBytes < kAudioTranscribeWavHeaderBytes) {
    return false;
  }

  bool hasAscii(int offset, String value) {
    final units = value.codeUnits;
    if (offset < 0 || offset + units.length > bytes.lengthInBytes) {
      return false;
    }
    for (var i = 0; i < units.length; i++) {
      if (bytes[offset + i] != units[i]) {
        return false;
      }
    }
    return true;
  }

  int readUint16Le(int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int readUint32Le(int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  if (!hasAscii(0, 'RIFF') || !hasAscii(8, 'WAVE')) {
    return false;
  }
  if (!hasAscii(12, 'fmt ') || !hasAscii(36, 'data')) {
    return false;
  }

  final fmtChunkSize = readUint32Le(16);
  if (fmtChunkSize < 16) {
    return false;
  }

  final audioFormat = readUint16Le(20);
  final channelCount = readUint16Le(22);
  final sampleRate = readUint32Le(24);
  final bitsPerSample = readUint16Le(34);
  if (audioFormat != 1 ||
      channelCount != 1 ||
      sampleRate != 16000 ||
      bitsPerSample != 16) {
    return false;
  }

  final dataLength = readUint32Le(40);
  const payloadOffset = kAudioTranscribeWavHeaderBytes;
  if (dataLength <= 0) {
    return false;
  }
  if (payloadOffset + dataLength > bytes.lengthInBytes) {
    return false;
  }

  return true;
}

Uint8List extractPcm16Mono16kFromWav(Uint8List wavBytes) {
  if (wavBytes.lengthInBytes < kAudioTranscribeWavHeaderBytes) {
    return Uint8List(0);
  }

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
  if (pcmBytes.lengthInBytes.isOdd) {
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
  if (pcmBytes.isEmpty || pcmBytes.lengthInBytes.isOdd) {
    return Uint8List(0);
  }

  final dataSize = pcmBytes.lengthInBytes;
  const byteRate = 16000 * 1 * 16 ~/ 8;
  const blockAlign = 1 * 16 ~/ 8;

  final header = ByteData(kAudioTranscribeWavHeaderBytes)
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

List<AudioTranscribeWavChunk> splitNormalizedWavIntoChunks(
  Uint8List normalizedWavBytes, {
  int chunkMs = kRemoteTranscribeChunkMs,
  int? maxChunkBytes,
}) {
  final pcmBytes = extractPcm16Mono16kFromWav(normalizedWavBytes);
  if (pcmBytes.isEmpty) return const <AudioTranscribeWavChunk>[];

  final durationLimitedChunkBytes =
      (kAudioTranscribePcmBytesPerSecond * chunkMs) ~/ 1000;
  var payloadChunkBytes = durationLimitedChunkBytes <= 0
      ? pcmBytes.lengthInBytes
      : durationLimitedChunkBytes;

  if (maxChunkBytes != null && maxChunkBytes > kAudioTranscribeWavHeaderBytes) {
    final maxPayload = maxChunkBytes - kAudioTranscribeWavHeaderBytes;
    if (maxPayload < payloadChunkBytes) {
      payloadChunkBytes = maxPayload;
    }
  }

  if (payloadChunkBytes < kAudioTranscribePcmBytesPerSample) {
    payloadChunkBytes = kAudioTranscribePcmBytesPerSample;
  }
  if (payloadChunkBytes.isOdd) {
    payloadChunkBytes -= 1;
  }
  if (payloadChunkBytes <= 0) {
    payloadChunkBytes = kAudioTranscribePcmBytesPerSample;
  }

  final chunks = <AudioTranscribeWavChunk>[];
  for (var offset = 0; offset < pcmBytes.lengthInBytes;) {
    var end = offset + payloadChunkBytes;
    if (end > pcmBytes.lengthInBytes) {
      end = pcmBytes.lengthInBytes;
    }
    if ((end - offset).isOdd) {
      end -= 1;
    }
    if (end <= offset) {
      break;
    }

    final chunkPcm = Uint8List.fromList(pcmBytes.sublist(offset, end));
    final chunkWav = buildWavFromPcm16Mono16k(<Uint8List>[chunkPcm]);
    if (chunkWav.isEmpty) {
      break;
    }

    final offsetMs = (offset * 1000) ~/ kAudioTranscribePcmBytesPerSecond;
    final durationMs =
        ((end - offset) * 1000) ~/ kAudioTranscribePcmBytesPerSecond;
    chunks.add(
      AudioTranscribeWavChunk(
        wavBytes: chunkWav,
        offsetMs: offsetMs,
        durationMs: durationMs,
      ),
    );
    offset = end;
  }

  return chunks;
}
