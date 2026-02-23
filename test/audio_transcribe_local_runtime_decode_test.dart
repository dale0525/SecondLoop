import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_runner.dart';

Uint8List _buildCanonicalMono16kWav(Uint8List pcmBytes) {
  final byteData = ByteData(44 + pcmBytes.lengthInBytes);

  void writeAscii(int offset, String value) {
    final units = value.codeUnits;
    for (var i = 0; i < units.length; i++) {
      byteData.setUint8(offset + i, units[i]);
    }
  }

  writeAscii(0, 'RIFF');
  byteData.setUint32(4, 36 + pcmBytes.lengthInBytes, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  byteData.setUint32(16, 16, Endian.little);
  byteData.setUint16(20, 1, Endian.little);
  byteData.setUint16(22, 1, Endian.little);
  byteData.setUint32(24, 16000, Endian.little);
  byteData.setUint32(28, 32000, Endian.little);
  byteData.setUint16(32, 2, Endian.little);
  byteData.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  byteData.setUint32(40, pcmBytes.lengthInBytes, Endian.little);

  final out = byteData.buffer.asUint8List();
  out.setRange(44, out.length, pcmBytes);
  return out;
}

void main() {
  test('detects canonical pcm16 mono 16k wav payload', () {
    final wavBytes = _buildCanonicalMono16kWav(
      Uint8List.fromList(const <int>[0x00, 0x00, 0x01, 0x01]),
    );

    expect(isCanonicalPcm16Mono16kWavBytes(wavBytes), isTrue);
    expect(
      shouldBypassLocalRuntimeDecodeForWav(
        mimeType: 'audio/wav',
        audioBytes: wavBytes,
      ),
      isTrue,
    );
  });

  test('does not bypass decode for non-wav mime hints', () {
    final wavBytes = _buildCanonicalMono16kWav(
      Uint8List.fromList(const <int>[0x00, 0x00, 0x01, 0x01]),
    );

    expect(
      shouldBypassLocalRuntimeDecodeForWav(
        mimeType: 'audio/mp4',
        audioBytes: wavBytes,
      ),
      isFalse,
    );
  });

  test('does not treat unsupported wav format as canonical passthrough', () {
    final wavBytes = _buildCanonicalMono16kWav(
      Uint8List.fromList(const <int>[0x00, 0x00, 0x01, 0x01]),
    );
    final malformed = Uint8List.fromList(wavBytes);

    const sampleRateOffset = 24;
    final sampleRateBytes = ByteData(4)..setUint32(0, 24000, Endian.little);
    malformed.setRange(
      sampleRateOffset,
      sampleRateOffset + 4,
      sampleRateBytes.buffer.asUint8List(),
    );

    expect(isCanonicalPcm16Mono16kWavBytes(malformed), isFalse);
    expect(
      shouldBypassLocalRuntimeDecodeForWav(
        mimeType: 'audio/wav',
        audioBytes: malformed,
      ),
      isFalse,
    );
  });
}
