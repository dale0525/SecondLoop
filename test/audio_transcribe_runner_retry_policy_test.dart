import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_runner.dart';

final class _RetryPolicyStore implements AudioTranscribeStore {
  _RetryPolicyStore({required this.jobs});

  final List<AudioTranscribeJob> jobs;
  final Map<String, int> failedNextRetryBySha = <String, int>{};
  final Map<String, int> failedAttemptsBySha = <String, int>{};

  @override
  Future<List<AudioTranscribeJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return jobs;
  }

  @override
  Future<Uint8List> readAttachmentBytes({required String attachmentSha256}) {
    return Future<Uint8List>.value(Uint8List.fromList(<int>[1, 2, 3, 4]));
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    failedNextRetryBySha[attachmentSha256] = nextRetryAtMs;
    failedAttemptsBySha[attachmentSha256] = attempts;
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) {
    throw UnimplementedError('unexpected success path');
  }
}

final class _FailingClient implements AudioTranscribeClient {
  _FailingClient(this.error);

  final Object error;

  @override
  String get engineName => 'test_engine';

  @override
  String get modelName => 'test_model';

  @override
  int? get maxInputBytes => null;

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) {
    throw error;
  }
}

AudioTranscribeJob _job({
  required String attachmentSha256,
  int attempts = 0,
}) {
  return AudioTranscribeJob(
    attachmentSha256: attachmentSha256,
    lang: 'en',
    status: 'pending',
    attempts: attempts,
    nextRetryAtMs: null,
    mimeTypeHint: 'audio/wav',
  );
}

void main() {
  test('schedules terminal failures with 30 day retry freeze', () async {
    const nowMs = 1000000;
    final store = _RetryPolicyStore(
      jobs: <AudioTranscribeJob>[
        _job(attachmentSha256: 'sha_terminal'),
      ],
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: _FailingClient(
        StateError('audio_transcribe_http_413:{"error":"payload_too_large"}'),
      ),
      nowMs: () => nowMs,
    );

    await runner.runOnce(limit: 1);

    expect(
      store.failedNextRetryBySha['sha_terminal'],
      nowMs + const Duration(days: 30).inMilliseconds,
    );
    expect(store.failedAttemptsBySha['sha_terminal'], 1);
  });

  test('schedules long backoff failures at 12 hours', () async {
    const nowMs = 2000000;
    final store = _RetryPolicyStore(
      jobs: <AudioTranscribeJob>[
        _job(attachmentSha256: 'sha_long_backoff'),
      ],
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client: _FailingClient(
        StateError('audio_transcribe_native_stt_missing_speech_pack:zh-CN'),
      ),
      nowMs: () => nowMs,
    );

    await runner.runOnce(limit: 1);

    expect(
      store.failedNextRetryBySha['sha_long_backoff'],
      nowMs + const Duration(hours: 12).inMilliseconds,
    );
    expect(store.failedAttemptsBySha['sha_long_backoff'], 1);
  });

  test('keeps exponential backoff for retryable failures', () async {
    const nowMs = 3000000;
    final store = _RetryPolicyStore(
      jobs: <AudioTranscribeJob>[
        _job(attachmentSha256: 'sha_retryable', attempts: 2),
      ],
    );
    final runner = AudioTranscribeRunner(
      store: store,
      client:
          _FailingClient(StateError('socket timeout while calling gateway')),
      nowMs: () => nowMs,
    );

    await runner.runOnce(limit: 1);

    expect(
      store.failedNextRetryBySha['sha_retryable'],
      nowMs + const Duration(seconds: 20).inMilliseconds,
    );
    expect(store.failedAttemptsBySha['sha_retryable'], 3);
  });
}
