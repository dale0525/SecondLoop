import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_media_preprocess.dart';

Uint8List _wavFromDurationSeconds(int seconds) {
  final pcmBytes = Uint8List(kAudioTranscribePcmBytesPerSecond * seconds);
  return buildWavFromPcm16Mono16k(<Uint8List>[pcmBytes]);
}

void main() {
  test('splitNormalizedWavIntoChunks uses 10-minute default chunk size', () {
    final wavBytes = _wavFromDurationSeconds(22 * 60);

    final chunks = splitNormalizedWavIntoChunks(wavBytes);

    expect(kRemoteTranscribeChunkMs, 600000);
    expect(chunks, hasLength(3));
    expect(chunks[0].offsetMs, 0);
    expect(chunks[1].offsetMs, 600000);
    expect(chunks[2].offsetMs, 1200000);
  });

  test('splitNormalizedWavIntoChunks keeps chunk payload 2-byte aligned', () {
    final wavBytes = _wavFromDurationSeconds(4);

    final chunks = splitNormalizedWavIntoChunks(
      wavBytes,
      chunkMs: 1 * 1000,
      maxChunkBytes: 53,
    );

    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      final pcmBytes = extractPcm16Mono16kFromWav(chunk.wavBytes);
      expect(pcmBytes.lengthInBytes.isEven, isTrue);
    }
  });

  test('extract and build wav helpers roundtrip pcm bytes', () {
    final source = Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6]);

    final wav = buildWavFromPcm16Mono16k(<Uint8List>[source]);
    final extracted = extractPcm16Mono16kFromWav(wav);

    expect(extracted, source);
  });
}
