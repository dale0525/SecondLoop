import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/audio_transcribe/audio_transcribe_runner.dart';

final class _PreflightStore implements AudioTranscribeStore {
  _PreflightStore({
    required this.jobs,
    required this.bytesBySha,
  });

  final List<AudioTranscribeJob> jobs;
  final Map<String, Uint8List> bytesBySha;

  final Map<String, String> failedErrorBySha = <String, String>{};
  final Map<String, String> okPayloadBySha = <String, String>{};

  @override
  Future<List<AudioTranscribeJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    return jobs;
  }

  @override
  Future<Uint8List> readAttachmentBytes({required String attachmentSha256}) {
    return Future<Uint8List>.value(
      bytesBySha[attachmentSha256] ?? Uint8List(0),
    );
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) async {
    failedErrorBySha[attachmentSha256] = error;
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
}

final class _PreflightClient implements AudioTranscribeClient {
  _PreflightClient({
    this.maxBytes,
  });

  final int? maxBytes;

  int callCount = 0;

  @override
  String get engineName => 'test_engine';

  @override
  String get modelName => 'test_model';

  @override
  int? get maxInputBytes => maxBytes;

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    callCount += 1;
    return const AudioTranscribeResponse(
      transcriptFull: 'ok',
      segments: <AudioTranscriptSegment>[],
    );
  }
}

void main() {
  test('fails before transcribe when audio exceeds client maxInputBytes',
      () async {
    final store = _PreflightStore(
      jobs: const <AudioTranscribeJob>[
        AudioTranscribeJob(
          attachmentSha256: 'sha_oversized',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          mimeTypeHint: 'audio/wav',
        ),
      ],
      bytesBySha: <String, Uint8List>{
        'sha_oversized': Uint8List.fromList(List<int>.filled(32, 1)),
      },
    );
    final client = _PreflightClient(maxBytes: 16);
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 123456,
    );

    final result = await runner.runOnce(limit: 1);

    expect(result.processed, 0);
    expect(result.failed, 1);
    expect(client.callCount, 0);
    expect(
      store.failedErrorBySha['sha_oversized'] ?? '',
      contains('audio_transcribe_payload_too_large_local_check'),
    );
  });

  test('does not precheck when client maxInputBytes is null', () async {
    final store = _PreflightStore(
      jobs: const <AudioTranscribeJob>[
        AudioTranscribeJob(
          attachmentSha256: 'sha_unlimited',
          lang: 'en',
          status: 'pending',
          attempts: 0,
          nextRetryAtMs: null,
          mimeTypeHint: 'audio/wav',
        ),
      ],
      bytesBySha: <String, Uint8List>{
        'sha_unlimited': Uint8List.fromList(List<int>.filled(32, 1)),
      },
    );
    final client = _PreflightClient(maxBytes: null);
    final runner = AudioTranscribeRunner(
      store: store,
      client: client,
      nowMs: () => 123456,
    );

    final result = await runner.runOnce(limit: 1);

    expect(result.processed, 1);
    expect(result.failed, 0);
    expect(client.callCount, 1);
    expect(store.okPayloadBySha['sha_unlimited'], isNotEmpty);
  });
}
