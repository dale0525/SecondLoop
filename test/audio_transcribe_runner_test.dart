import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  Object failError = StateError('transcribe_failed');
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
    if (shouldFail) throw failError;
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
  test('supports platform local runtime audio transcribe on desktop and mobile',
      () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(supportsPlatformLocalRuntimeAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(supportsPlatformLocalRuntimeAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(supportsPlatformLocalRuntimeAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(supportsPlatformLocalRuntimeAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(supportsPlatformLocalRuntimeAudioTranscribe(), isFalse);
  });

  test('supports platform local audio transcribe on desktop and mobile', () {
    final previous = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = previous;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(supportsPlatformLocalAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(supportsPlatformLocalAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(supportsPlatformLocalAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(supportsPlatformLocalAudioTranscribe(), isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(supportsPlatformLocalAudioTranscribe(), isFalse);
  });

  test(
      'selectPlatformLocalRuntimeAudioTranscribeRequest uses windows native stt when windows host',
      () async {
    var methodChannelCalls = 0;
    var windowsNativeCalls = 0;
    final request = selectPlatformLocalRuntimeAudioTranscribeRequest(
      methodChannelRequest: ({
        required appDir,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        methodChannelCalls += 1;
        return jsonEncode(<String, Object?>{'text': 'from_method_channel'});
      },
      windowsNativeSttRequest: ({
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        windowsNativeCalls += 1;
        return jsonEncode(<String, Object?>{'text': 'from_windows_native'});
      },
      isWindowsHost: true,
    );

    final raw = await request(
      appDir: '/tmp/secondloop-test',
      lang: 'en',
      mimeType: 'audio/wav',
      audioBytes: Uint8List.fromList(const <int>[0x52, 0x49, 0x46, 0x46]),
    );

    expect(methodChannelCalls, 0);
    expect(windowsNativeCalls, 1);
    expect((jsonDecode(raw) as Map<String, dynamic>)['text'],
        'from_windows_native');
  });

  test(
      'selectPlatformLocalRuntimeAudioTranscribeRequest uses method channel on non-windows host',
      () async {
    var methodChannelCalls = 0;
    var windowsNativeCalls = 0;
    final request = selectPlatformLocalRuntimeAudioTranscribeRequest(
      methodChannelRequest: ({
        required appDir,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        methodChannelCalls += 1;
        return jsonEncode(<String, Object?>{'text': 'from_method_channel'});
      },
      windowsNativeSttRequest: ({
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        windowsNativeCalls += 1;
        return jsonEncode(<String, Object?>{'text': 'from_windows_native'});
      },
      isWindowsHost: false,
    );

    final raw = await request(
      appDir: '/tmp/secondloop-test',
      lang: 'en',
      mimeType: 'audio/mpeg',
      audioBytes: Uint8List.fromList(const <int>[0x49, 0x44, 0x33]),
    );

    expect(methodChannelCalls, 1);
    expect(windowsNativeCalls, 0);
    expect((jsonDecode(raw) as Map<String, dynamic>)['text'],
        'from_method_channel');
  });

  test('local runtime fallback is disabled when platform support is missing',
      () {
    final enabled = shouldEnableLocalRuntimeAudioFallback(
      supportsLocalRuntime: false,
      cloudEnabled: true,
      hasByokProfile: true,
      effectiveEngine: 'local_runtime',
    );

    expect(enabled, isFalse);
  });

  test('local runtime fallback is enabled on supported platform', () {
    final enabled = shouldEnableLocalRuntimeAudioFallback(
      supportsLocalRuntime: true,
      cloudEnabled: false,
      hasByokProfile: false,
      effectiveEngine: 'local_runtime',
    );

    expect(enabled, isTrue);
  });

  test('normalizeAudioTranscribeEngine allows local runtime and byok modes',
      () {
    expect(normalizeAudioTranscribeEngine('whisper'), 'whisper');
    expect(normalizeAudioTranscribeEngine('multimodal_llm'), 'multimodal_llm');
    expect(normalizeAudioTranscribeEngine('local_runtime'), 'local_runtime');
    expect(normalizeAudioTranscribeEngine('auto'), 'whisper');
    expect(normalizeAudioTranscribeEngine('unknown'), 'whisper');
  });

  test('isAutoAudioTranscribeLang detects auto language hints', () {
    expect(isAutoAudioTranscribeLang(''), isTrue);
    expect(isAutoAudioTranscribeLang('auto'), isTrue);
    expect(isAutoAudioTranscribeLang('und'), isTrue);
    expect(isAutoAudioTranscribeLang('unknown'), isTrue);
    expect(isAutoAudioTranscribeLang('zh-CN'), isFalse);
    expect(isAutoAudioTranscribeLang('en'), isFalse);
  });

  test('fallback client uses next client when cloud and byok fail', () async {
    final cloud = _MemClient(engineName: 'cloud_gateway', modelName: 'cloud')
      ..shouldFail = true;
    final byok = _MemClient(engineName: 'whisper', modelName: 'byok-whisper')
      ..shouldFail = true;
    final local =
        _MemClient(engineName: 'local_runtime', modelName: 'local-runtime');

    final client = FallbackAudioTranscribeClient(
      chain: [cloud, byok, local],
    );

    final response = await client.transcribe(
      lang: 'en',
      mimeType: 'audio/mpeg',
      audioBytes: Uint8List.fromList(const <int>[0x49, 0x44, 0x33]),
    );

    expect(cloud.calls, 1);
    expect(byok.calls, 1);
    expect(local.calls, 1);
    expect(client.engineName, 'local_runtime');
    expect(client.modelName, 'local-runtime');
    expect(response.transcriptFull, contains('hello world'));
  });

  test('local runtime client can decode with injected audio decoder', () async {
    final client = LocalRuntimeAudioTranscribeClient(
      modelName: 'runtime-whisper-tiny',
      whisperModel: 'tiny',
      appDirProvider: () async => '/tmp/secondloop-test',
      decodeAudioToWav: ({
        required mimeType,
        required audioBytes,
      }) async {
        expect(mimeType, 'audio/mp4');
        expect(audioBytes, isNotEmpty);
        return Uint8List.fromList(const <int>[1, 2, 3]);
      },
      requestLocalWhisperTranscribe: ({
        required appDir,
        required modelName,
        required lang,
        required wavBytes,
      }) async {
        expect(appDir, '/tmp/secondloop-test');
        expect(modelName, 'tiny');
        expect(lang, 'zh');
        expect(wavBytes, Uint8List.fromList(const <int>[1, 2, 3]));
        return jsonEncode(<String, Object?>{'text': 'tiny runtime'});
      },
    );

    final response = await client.transcribe(
      lang: 'zh',
      mimeType: 'audio/mp4',
      audioBytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
    );

    expect(response.transcriptFull, 'tiny runtime');
    expect(client.engineName, 'local_runtime');
    expect(client.modelName, 'runtime-whisper-tiny');
  });

  test('local runtime client parses transcript payload', () async {
    final client = LocalRuntimeAudioTranscribeClient(
      modelName: 'runtime-whisper-small',
      appDirProvider: () async => '/tmp/secondloop-test',
      requestLocalRuntimeTranscribe: ({
        required appDir,
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        expect(appDir, '/tmp/secondloop-test');
        expect(lang, 'zh');
        expect(mimeType, 'audio/mp4');
        expect(audioBytes, isNotEmpty);
        return jsonEncode({
          'text': 'hello from local runtime',
          'duration': 8.5,
          'segments': [
            {'start': 0.0, 'text': 'hello'},
            {'start': 0.7, 'text': 'from local runtime'},
          ],
        });
      },
    );

    final result = await client.transcribe(
      lang: 'zh',
      mimeType: 'audio/mp4',
      audioBytes: Uint8List.fromList(const <int>[0x00, 0x00, 0x00, 0x18]),
    );

    expect(client.engineName, 'local_runtime');
    expect(client.modelName, 'runtime-whisper-small');
    expect(result.transcriptFull, 'hello from local runtime');
    expect(result.durationMs, 8500);
    expect(result.segments.length, 2);
    expect(result.segments.last.tMs, 700);
  });

  test('windows native stt client parses payload response', () async {
    final client = WindowsNativeSttAudioTranscribeClient(
      modelName: 'windows_native_stt',
      requestWindowsNativeSttTranscribe: ({
        required lang,
        required mimeType,
        required audioBytes,
      }) async {
        expect(lang, 'en');
        expect(mimeType, 'audio/wav');
        expect(audioBytes, isNotEmpty);
        return jsonEncode({
          'text': 'hello from windows native stt',
          'duration': 2.3,
          'segments': [
            {'t_ms': 0, 'text': 'hello'},
            {'t_ms': 900, 'text': 'from windows native stt'},
          ],
        });
      },
    );

    final result = await client.transcribe(
      lang: 'en',
      mimeType: 'audio/wav',
      audioBytes: Uint8List.fromList(const <int>[0x52, 0x49, 0x46, 0x46]),
    );

    expect(client.engineName, 'native_stt');
    expect(client.modelName, 'windows_native_stt');
    expect(result.transcriptFull, 'hello from windows native stt');
    expect(result.durationMs, 2300);
    expect(result.segments.length, 2);
  });

  test('windows native stt temp paths keep source/output distinct for wav', () {
    final paths = buildWindowsNativeSttTempPaths(
      tempDirPath: '/tmp/secondloop-native-stt',
      mimeType: 'audio/wav',
    );
    expect(paths.sourcePath, isNot(paths.wavPath));
    expect(paths.sourcePath, endsWith('/source.wav'));
    expect(paths.wavPath, endsWith('/output.wav'));
  });

  test('detects windows native stt missing speech pack errors', () {
    expect(
      isWindowsNativeSttSpeechPackMissingError(
        'audio_transcribe_native_stt_missing_speech_pack',
      ),
      isTrue,
    );
    expect(
      isWindowsNativeSttSpeechPackMissingError(
        'audio_transcribe_native_stt_failed:speech_recognizer_unavailable',
      ),
      isTrue,
    );
    expect(
      isWindowsNativeSttSpeechPackMissingError(
        'audio_transcribe_native_stt_failed:speech_recognizer_lang_missing:zh-cn',
      ),
      isTrue,
    );
    expect(
      isWindowsNativeSttSpeechPackMissingError(
        'audio_transcribe_native_stt_failed:ffmpeg_exit_1',
      ),
      isFalse,
    );
  });

  test('normalizes windows speech recognizer language tags', () {
    expect(normalizeWindowsSpeechRecognizerLang('zh-Hans-CN'), 'zh-cn');
    expect(normalizeWindowsSpeechRecognizerLang('zh_Hans_CN'), 'zh-cn');
    expect(normalizeWindowsSpeechRecognizerLang('en-US'), 'en-us');
    expect(normalizeWindowsSpeechRecognizerLang('zh-Hant'), 'zh');
    expect(normalizeWindowsSpeechRecognizerLang('auto'), '');
    expect(normalizeWindowsSpeechRecognizerLang(''), '');
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
    expect(result.failed, 0);
    expect(result.didMutateAny, isTrue);
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

  test('sniffAudioMimeType detects webm and matroska containers', () {
    final webm = Uint8List.fromList(
      <int>[0x1A, 0x45, 0xDF, 0xA3, ...'webm'.codeUnits],
    );
    final matroska = Uint8List.fromList(
      const <int>[0x1A, 0x45, 0xDF, 0xA3, 0x42, 0x82, 0x84],
    );

    expect(sniffAudioMimeType(webm), 'video/webm');
    expect(sniffAudioMimeType(matroska), 'video/x-matroska');
  });

  test('runner falls back to mime type hints when sniffing is unavailable',
      () async {
    final store = _MemStore(
      jobs: const [
        AudioTranscribeJob(
          attachmentSha256: 'hinted-video',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          mimeTypeHint: 'video/webm',
        ),
      ],
      bytesBySha: {
        'hinted-video': Uint8List.fromList(
          const <int>[0x00, 0x11, 0x22, 0x33, 0x44],
        ),
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
    expect(result.failed, 0);
    expect(client.calls, 1);
    expect(client.lastMimeType, 'video/webm');
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
    expect(result.failed, 0);
    expect(result.didMutateAny, isFalse);
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
    expect(result.failed, 1);
    expect(result.didMutateAny, isTrue);
    expect(client.calls, 1);
    expect(store.failedBySha['c1'], contains('transcribe_failed'));
    expect(store.failedAttemptsBySha['c1'], 2);
    expect(store.failedNextRetryBySha['c1'], greaterThan(5000));
  });

  test('runner uses longer retry delay for missing speech pack errors',
      () async {
    final store = _MemStore(
      jobs: const [
        AudioTranscribeJob(
          attachmentSha256: 'd1',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'd1': Uint8List.fromList(const <int>[0x49, 0x44, 0x33, 0x03]),
      },
    );
    final client = _MemClient(engineName: 'native_stt', modelName: 'windows')
      ..shouldFail = true
      ..failError =
          StateError('audio_transcribe_native_stt_missing_speech_pack');
    const nowMs = 5000;
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => nowMs,
    );

    final result = await runner.runOnce(limit: 5);
    expect(result.processed, 0);
    expect(result.failed, 1);
    expect(result.didMutateAny, isTrue);
    expect(client.calls, 1);
    expect(
      store.failedNextRetryBySha['d1'],
      greaterThanOrEqualTo(
        nowMs + const Duration(hours: 12).inMilliseconds,
      ),
    );
  });

  test('runner uses longer retry delay for missing local whisper model',
      () async {
    final store = _MemStore(
      jobs: const [
        AudioTranscribeJob(
          attachmentSha256: 'd2',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
        ),
      ],
      bytesBySha: {
        'd2': Uint8List.fromList(const <int>[0x49, 0x44, 0x33, 0x03]),
      },
    );
    final client = _MemClient(
      engineName: 'local_runtime',
      modelName: 'runtime-whisper-base',
    )
      ..shouldFail = true
      ..failError =
          StateError('audio_transcribe_local_runtime_model_missing:base');
    const nowMs = 6000;
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => nowMs,
    );

    final result = await runner.runOnce(limit: 5);
    expect(result.processed, 0);
    expect(result.failed, 1);
    expect(result.didMutateAny, isTrue);
    expect(client.calls, 1);
    expect(
      store.failedNextRetryBySha['d2'],
      greaterThanOrEqualTo(
        nowMs + const Duration(hours: 12).inMilliseconds,
      ),
    );
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
