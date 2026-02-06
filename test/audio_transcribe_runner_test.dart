import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/audio_transcribe/audio_transcribe_runner.dart';

final class _MemStore implements AudioTranscribeStore {
  _MemStore({
    required this.jobs,
    required this.bytesBySha,
  });

  final List<AudioTranscribeJob> jobs;
  final Map<String, Uint8List> bytesBySha;

  final Map<String, String> okPayloadBySha = <String, String>{};
  final Map<String, String> failedBySha = <String, String>{};
  final Map<String, int> failedAttemptsBySha = <String, int>{};
  final Map<String, int> failedNextRetryBySha = <String, int>{};

  @override
  Future<List<AudioTranscribeJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return jobs
        .where((i) => i.nextRetryAtMs == null || i.nextRetryAtMs! <= nowMs)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Uint8List> readAttachmentBytes(
      {required String attachmentSha256}) async {
    final bytes = bytesBySha[attachmentSha256];
    if (bytes == null) {
      throw StateError('missing_bytes:$attachmentSha256');
    }
    return bytes;
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) async {
    okPayloadBySha[attachmentSha256] = payloadJson;
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    failedBySha[attachmentSha256] = error;
    failedAttemptsBySha[attachmentSha256] = attempts;
    failedNextRetryBySha[attachmentSha256] = nextRetryAtMs;
  }
}

final class _MemClient implements AudioTranscribeClient {
  _MemClient({
    required this.engineName,
    required this.modelName,
  });

  @override
  final String engineName;
  @override
  final String modelName;

  bool shouldFail = false;
  int calls = 0;
  String? lastMimeType;

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    calls += 1;
    lastMimeType = mimeType;
    if (shouldFail) throw StateError('transcribe_failed');
    return const AudioTranscribeResponse(
      durationMs: 12345,
      transcriptFull: 'hello world from audio',
      segments: [
        AudioTranscriptSegment(tMs: 0, text: 'hello'),
        AudioTranscriptSegment(tMs: 900, text: 'world'),
      ],
    );
  }
}

void main() {
  test('normalizeAudioTranscribeEngine only allows whisper or multimodal', () {
    expect(normalizeAudioTranscribeEngine('whisper'), 'whisper');
    expect(normalizeAudioTranscribeEngine('multimodal_llm'), 'multimodal_llm');
    expect(normalizeAudioTranscribeEngine('auto'), 'whisper');
    expect(normalizeAudioTranscribeEngine('unknown'), 'whisper');
  });

  test('runner transcribes pending audio and writes transcript payload',
      () async {
    final store = _MemStore(
      jobs: const [
        AudioTranscribeJob(
          attachmentSha256: 'a1',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'a1': Uint8List.fromList(const <int>[0x49, 0x44, 0x33, 0x04, 0x00]),
      },
    );
    final client = _MemClient(engineName: 'whisper', modelName: 'whisper-1');
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(limit: 5);
    expect(result.processed, 1);
    expect(client.calls, 1);
    expect(client.lastMimeType, 'audio/mpeg');

    final rawPayload = store.okPayloadBySha['a1'];
    expect(rawPayload, isNotNull);
    final payload = jsonDecode(rawPayload!) as Map<String, Object?>;
    expect(payload['transcript_engine'], 'whisper');
    expect(payload['transcript_model_name'], 'whisper-1');
    expect(payload['duration_ms'], 12345);
    expect(payload['transcript_full'], contains('hello world'));
    expect(payload['transcript_excerpt'], contains('hello world'));

    final segments = payload['transcript_segments'] as List<Object?>;
    expect(segments.length, 2);
    expect((segments.first as Map)['t_ms'], 0);
  });

  test('runner skips non-audio attachments', () async {
    final store = _MemStore(
      jobs: const [
        AudioTranscribeJob(
          attachmentSha256: 'b1',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'b1': Uint8List.fromList('%PDF-1.7'.codeUnits),
      },
    );
    final client = _MemClient(engineName: 'whisper', modelName: 'whisper-1');
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 1000,
    );

    final result = await runner.runOnce(limit: 5);
    expect(result.processed, 0);
    expect(client.calls, 0);
    expect(store.okPayloadBySha, isEmpty);
    expect(store.failedBySha, isEmpty);
  });

  test('runner marks failed with backoff when transcribe throws', () async {
    final store = _MemStore(
      jobs: const [
        AudioTranscribeJob(
          attachmentSha256: 'c1',
          lang: 'en',
          status: 'pending',
          attempts: 1,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'c1': Uint8List.fromList(const <int>[0x49, 0x44, 0x33, 0x03]),
      },
    );
    final client = _MemClient(engineName: 'whisper', modelName: 'whisper-1')
      ..shouldFail = true;
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 5000,
    );

    final result = await runner.runOnce(limit: 5);
    expect(result.processed, 0);
    expect(client.calls, 1);
    expect(store.failedBySha['c1'], contains('transcribe_failed'));
    expect(store.failedAttemptsBySha['c1'], 2);
    expect(store.failedNextRetryBySha['c1'], greaterThan(5000));
  });

  test('byok whisper client parses verbose json response', () async {
    final client = ByokWhisperAudioTranscribeClient(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 3)),
      profileId: 'p1',
      modelName: 'whisper-1',
      appDirProvider: () async => '/tmp/secondloop-test',
      requestByokTranscribe: ({
        required appDir,
        required key,
        required profileId,
        required localDay,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        expect(appDir, '/tmp/secondloop-test');
        expect(profileId, 'p1');
        expect(mimeType, 'audio/mp4');
        return jsonEncode({
          'text': 'hello from byok',
          'duration': 12.3,
          'segments': [
            {'start': 0.1, 'text': 'hello'},
            {'start': 0.8, 'text': 'from byok'},
          ],
        });
      },
    );

    final res = await client.transcribe(
      lang: 'en',
      mimeType: 'audio/mp4',
      audioBytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
    );

    expect(client.engineName, 'whisper');
    expect(client.modelName, 'whisper-1');
    expect(res.transcriptFull, 'hello from byok');
    expect(res.durationMs, 12300);
    expect(res.segments.length, 2);
    expect(res.segments.first.tMs, 100);
  });

  test('byok whisper client throws when response text is empty', () async {
    final client = ByokWhisperAudioTranscribeClient(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 3)),
      profileId: 'p1',
      modelName: 'whisper-1',
      appDirProvider: () async => '/tmp/secondloop-test',
      requestByokTranscribe: ({
        required appDir,
        required key,
        required profileId,
        required localDay,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        return jsonEncode(<String, Object?>{'segments': const []});
      },
    );

    await expectLater(
      () => client.transcribe(
        lang: 'en',
        mimeType: 'audio/mp4',
        audioBytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('cloud multimodal client parses chat-completions transcript payload',
      () async {
    final client = CloudGatewayMultimodalAudioTranscribeClient(
      gatewayBaseUrl: 'https://gateway.test',
      idToken: 'token',
      modelName: 'cloud',
      requestCloudGatewayMultimodal: ({
        required gatewayBaseUrl,
        required idToken,
        required modelName,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        expect(gatewayBaseUrl, 'https://gateway.test');
        expect(idToken, 'token');
        expect(modelName, 'cloud');
        expect(lang, 'en');
        expect(mimeType, 'audio/mp4');
        expect(audioBytes, isNotEmpty);
        return jsonEncode({
          'choices': [
            {
              'message': {'content': 'hello from multimodal'}
            }
          ],
        });
      },
    );

    final result = await client.transcribe(
      lang: 'en',
      mimeType: 'audio/mp4',
      audioBytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
    );

    expect(client.engineName, 'multimodal_llm');
    expect(client.modelName, 'cloud');
    expect(result.transcriptFull, 'hello from multimodal');
  });

  test('byok multimodal client parses chat-completions transcript payload',
      () async {
    final client = ByokMultimodalAudioTranscribeClient(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 3)),
      profileId: 'p1',
      modelName: 'gpt-4o-mini',
      appDirProvider: () async => '/tmp/secondloop-test',
      requestByokMultimodalTranscribe: ({
        required appDir,
        required key,
        required profileId,
        required localDay,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        expect(appDir, '/tmp/secondloop-test');
        expect(profileId, 'p1');
        expect(lang, 'en');
        expect(mimeType, 'audio/mp4');
        return jsonEncode({'text': 'hello from byok multimodal'});
      },
    );

    final result = await client.transcribe(
      lang: 'en',
      mimeType: 'audio/mp4',
      audioBytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
    );

    expect(client.engineName, 'multimodal_llm');
    expect(client.modelName, 'gpt-4o-mini');
    expect(result.transcriptFull, 'hello from byok multimodal');
  });
}
