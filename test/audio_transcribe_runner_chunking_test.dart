import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_chunk_progress.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_media_preprocess.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_runner.dart';

final class _MemChunkStore implements AudioTranscribeStore {
  _MemChunkStore({
    required this.job,
    required this.bytes,
  });

  final AudioTranscribeJob job;
  final Uint8List bytes;

  String? okPayloadJson;
  String? failedError;
  int? failedAttempts;
  int? failedNextRetryAtMs;

  @override
  Future<List<AudioTranscribeJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return <AudioTranscribeJob>[job];
  }

  @override
  Future<Uint8List> readAttachmentBytes({
    required String attachmentSha256,
  }) async {
    return bytes;
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    failedError = error;
    failedAttempts = attempts;
    failedNextRetryAtMs = nextRetryAtMs;
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    okPayloadJson = payloadJson;
  }
}

typedef _ChunkTranscribeHandler = Future<AudioTranscribeResponse> Function({
  required int callIndex,
  required String lang,
  required String mimeType,
  required Uint8List audioBytes,
});

final class _ScriptedChunkClient implements AudioTranscribeClient {
  _ScriptedChunkClient({
    required this.handler,
  });

  final _ChunkTranscribeHandler handler;

  @override
  String get engineName => 'test_engine';

  @override
  String get modelName => 'test_model';

  @override
  int? get maxInputBytes => null;

  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  final List<String> mimeTypes = <String>[];

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    final callIndex = calls;
    calls += 1;
    inFlight += 1;
    if (inFlight > maxInFlight) {
      maxInFlight = inFlight;
    }
    mimeTypes.add(mimeType);
    try {
      return await handler(
        callIndex: callIndex,
        lang: lang,
        mimeType: mimeType,
        audioBytes: audioBytes,
      );
    } finally {
      inFlight -= 1;
    }
  }
}

Uint8List _buildThreeChunkPatternedWav() {
  final first = Uint8List(kAudioTranscribePcmBytesPerSecond * 10 * 60)
    ..fillRange(0, kAudioTranscribePcmBytesPerSecond * 10 * 60, 1);
  final second = Uint8List(kAudioTranscribePcmBytesPerSecond * 10 * 60)
    ..fillRange(0, kAudioTranscribePcmBytesPerSecond * 10 * 60, 2);
  final third = Uint8List(kAudioTranscribePcmBytesPerSecond * 2 * 60)
    ..fillRange(0, kAudioTranscribePcmBytesPerSecond * 2 * 60, 3);
  return buildWavFromPcm16Mono16k(<Uint8List>[first, second, third]);
}

int _chunkMarkerFromWav(Uint8List wavBytes) {
  if (wavBytes.lengthInBytes <= kAudioTranscribeWavHeaderBytes) return 0;
  return wavBytes[kAudioTranscribeWavHeaderBytes];
}

AudioTranscribeResponse _chunkResponse(String text) {
  return AudioTranscribeResponse(
    transcriptFull: text,
    segments: <AudioTranscriptSegment>[
      AudioTranscriptSegment(tMs: 0, text: 'segment:$text'),
    ],
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  int attempts = 80,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  test('runner chunks normalized wav and merges transcripts', () async {
    final wavBytes = _buildThreeChunkPatternedWav();
    final store = _MemChunkStore(
      job: const AudioTranscribeJob(
        attachmentSha256: 'sha-1',
        lang: 'und',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        mimeTypeHint: 'audio/wav',
      ),
      bytes: wavBytes,
    );
    final client = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        final marker = _chunkMarkerFromWav(audioBytes);
        return _chunkResponse('chunk-$marker');
      },
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 123456,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          audioBytes,
    );

    final result = await runner.runOnce(limit: 1);

    expect(result.processed, 1);
    expect(result.failed, 0);
    expect(store.failedError, isNull);
    expect(client.calls, 3);
    expect(client.mimeTypes, everyElement('audio/wav'));

    final payload = jsonDecode(store.okPayloadJson!) as Map<String, Object?>;
    expect(payload['transcript_full'], 'chunk-1\nchunk-2\nchunk-3');

    final segments = payload['transcript_segments'] as List<Object?>;
    expect(segments, hasLength(3));
    final first = Map<String, Object?>.from(segments[0]! as Map);
    final second = Map<String, Object?>.from(segments[1]! as Map);
    final third = Map<String, Object?>.from(segments[2]! as Map);
    expect(first['t_ms'], 0);
    expect(second['t_ms'], 600000);
    expect(third['t_ms'], 1200000);
  });

  test('runner executes chunk transcribe concurrently using runOnce limit',
      () async {
    final wavBytes = _buildThreeChunkPatternedWav();
    final store = _MemChunkStore(
      job: const AudioTranscribeJob(
        attachmentSha256: 'sha-2',
        lang: 'und',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        mimeTypeHint: 'audio/wav',
      ),
      bytes: wavBytes,
    );
    final gate = Completer<void>();
    final client = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        await gate.future;
        return _chunkResponse('chunk-${_chunkMarkerFromWav(audioBytes)}');
      },
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 2000,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          audioBytes,
    );

    final runFuture = runner.runOnce(limit: 3);
    await _waitUntil(() => client.calls >= 2);
    gate.complete();
    final result = await runFuture;

    expect(result.processed, 1);
    expect(result.failed, 0);
    expect(client.maxInFlight, greaterThan(1));
  });

  test(
      'runner saves partial chunk progress and backoff uses first real chunk error',
      () async {
    final wavBytes = _buildThreeChunkPatternedWav();
    const nowMs = 5000;
    final store = _MemChunkStore(
      job: const AudioTranscribeJob(
        attachmentSha256: 'sha-3',
        lang: 'und',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        mimeTypeHint: 'audio/wav',
      ),
      bytes: wavBytes,
    );
    final client = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        final marker = _chunkMarkerFromWav(audioBytes);
        if (marker == 2) {
          throw StateError('audio_transcribe_native_stt_missing_speech_pack');
        }
        return _chunkResponse('chunk-$marker');
      },
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => nowMs,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          audioBytes,
    );

    final result = await runner.runOnce(limit: 3);

    expect(result.processed, 0);
    expect(result.failed, 1);
    expect(
      store.failedError,
      startsWith(kAudioTranscribeChunkPartialErrorPrefix),
    );
    final progress = decodeAudioTranscribeChunkPartialProgress(
      store.failedError!,
    );
    expect(progress, isNotNull);
    expect(progress!.chunkCount, 3);
    expect(progress.failedChunkIndices, contains(1));
    expect(progress.completedResults.map((item) => item.index), contains(0));
    expect(progress.completedResults.map((item) => item.index), contains(2));
    expect(
      progress.retryError,
      contains('audio_transcribe_native_stt_missing_speech_pack'),
    );
    expect(
      store.failedNextRetryAtMs!,
      greaterThanOrEqualTo(
        nowMs + const Duration(hours: 12).inMilliseconds,
      ),
    );
  });

  test('runner retries only failed chunks when partial progress exists',
      () async {
    final wavBytes = _buildThreeChunkPatternedWav();

    final firstStore = _MemChunkStore(
      job: const AudioTranscribeJob(
        attachmentSha256: 'sha-4',
        lang: 'und',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        mimeTypeHint: 'audio/wav',
      ),
      bytes: wavBytes,
    );
    final firstClient = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        final marker = _chunkMarkerFromWav(audioBytes);
        if (marker == 2) {
          throw StateError('transient_network_failure');
        }
        return _chunkResponse('chunk-$marker');
      },
    );
    final firstRunner = AudioTranscribeRunner(
      store: firstStore,
      client: firstClient,
      nowMs: () => 7000,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          audioBytes,
    );
    final firstRun = await firstRunner.runOnce(limit: 3);
    expect(firstRun.processed, 0);
    expect(firstRun.failed, 1);
    final persistedPartialError = firstStore.failedError;
    expect(
      persistedPartialError,
      startsWith(kAudioTranscribeChunkPartialErrorPrefix),
    );

    final secondStore = _MemChunkStore(
      job: AudioTranscribeJob(
        attachmentSha256: 'sha-4',
        lang: 'und',
        status: 'failed',
        attempts: 1,
        nextRetryAtMs: null,
        mimeTypeHint: 'audio/wav',
        lastError: persistedPartialError,
      ),
      bytes: wavBytes,
    );
    final secondClient = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        final marker = _chunkMarkerFromWav(audioBytes);
        expect(marker, 2);
        return _chunkResponse('chunk-2-retry');
      },
    );
    final secondRunner = AudioTranscribeRunner(
      store: secondStore,
      client: secondClient,
      nowMs: () => 8000,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          audioBytes,
    );

    final secondRun = await secondRunner.runOnce(limit: 3);

    expect(secondRun.processed, 1);
    expect(secondRun.failed, 0);
    expect(secondClient.calls, 1);
    final payload =
        jsonDecode(secondStore.okPayloadJson!) as Map<String, Object?>;
    expect(payload['transcript_full'], 'chunk-1\nchunk-2-retry\nchunk-3');
  });

  test('video mime hint still goes through unified wav chunk runner', () async {
    final store = _MemChunkStore(
      job: const AudioTranscribeJob(
        attachmentSha256: 'sha-5',
        lang: 'und',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        mimeTypeHint: 'video/mp4',
      ),
      bytes: Uint8List.fromList(const <int>[0x00, 0x11, 0x22, 0x33]),
    );
    final client = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        final marker = _chunkMarkerFromWav(audioBytes);
        return _chunkResponse('video-chunk-$marker');
      },
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 9000,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          _buildThreeChunkPatternedWav(),
    );

    final result = await runner.runOnce(limit: 2);

    expect(result.processed, 1);
    expect(result.failed, 0);
    expect(client.calls, 3);
    expect(client.mimeTypes, everyElement('audio/wav'));
  });

  test('recording style audio hint goes through unified wav chunk runner',
      () async {
    final store = _MemChunkStore(
      job: const AudioTranscribeJob(
        attachmentSha256: 'sha-6',
        lang: 'und',
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        mimeTypeHint: 'audio/mp4',
      ),
      bytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
    );
    final client = _ScriptedChunkClient(
      handler: ({
        required callIndex,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        final marker = _chunkMarkerFromWav(audioBytes);
        return _chunkResponse('recording-chunk-$marker');
      },
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 9500,
      decodeAudioToWavForChunking: ({
        required mimeType,
        required audioBytes,
      }) async =>
          _buildThreeChunkPatternedWav(),
    );

    final result = await runner.runOnce(limit: 2);

    expect(result.processed, 1);
    expect(result.failed, 0);
    expect(client.calls, 3);
    expect(client.mimeTypes, everyElement('audio/wav'));
  });
}
