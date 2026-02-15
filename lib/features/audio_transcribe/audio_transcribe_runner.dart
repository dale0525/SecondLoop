import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/backend/native_app_dir.dart';
import '../../core/backend/native_backend.dart';
import '../../core/content_enrichment/audio_transcribe_failure_reason.dart';
import '../../src/rust/api/audio_transcribe.dart' as rust_audio_transcribe;

part 'audio_transcribe_runner_clients.dart';
part 'audio_transcribe_runner_protocol.dart';

const String kAudioTranscriptSchema = 'secondloop.audio_transcript.v1';

final class AudioTranscribeJob {
  const AudioTranscribeJob({
    required this.attachmentSha256,
    required this.lang,
    required this.status,
    required this.attempts,
    required this.nextRetryAtMs,
  });

  final String attachmentSha256;
  final String lang;
  final String status;
  final int attempts;
  final int? nextRetryAtMs;
}

abstract class AudioTranscribeStore {
  Future<List<AudioTranscribeJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  });

  Future<Uint8List> readAttachmentBytes({
    required String attachmentSha256,
  });

  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  });

  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  });
}

final class AudioTranscriptSegment {
  const AudioTranscriptSegment({
    required this.tMs,
    required this.text,
  });

  final int tMs;
  final String text;
}

final class AudioTranscribeResponse {
  const AudioTranscribeResponse({
    required this.transcriptFull,
    required this.segments,
    this.durationMs,
  });

  final String transcriptFull;
  final List<AudioTranscriptSegment> segments;
  final int? durationMs;
}

abstract class AudioTranscribeClient {
  String get engineName;
  String get modelName;

  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  });
}

final class AudioTranscribeRunResult {
  const AudioTranscribeRunResult({
    required this.processed,
  });

  final int processed;
  bool get didEnrichAny => processed > 0;
}

typedef AudioTranscribeNowMs = int Function();
typedef AudioTranscribeByokRequest = Future<String> Function({
  required String appDir,
  required List<int> key,
  required String profileId,
  required String localDay,
  required String lang,
  required String mimeType,
  required List<int> audioBytes,
});
typedef AudioTranscribeByokMultimodalRequest = Future<String> Function({
  required String appDir,
  required List<int> key,
  required String profileId,
  required String localDay,
  required String lang,
  required String mimeType,
  required List<int> audioBytes,
});
typedef AudioTranscribeCloudMultimodalRequest = Future<String> Function({
  required String gatewayBaseUrl,
  required String idToken,
  required String modelName,
  required String lang,
  required String mimeType,
  required Uint8List audioBytes,
});
typedef AudioTranscribeLocalRuntimeRequest = Future<String> Function({
  required String appDir,
  required String lang,
  required String mimeType,
  required Uint8List audioBytes,
});
typedef AudioTranscribeNativeSttRequest = Future<String> Function({
  required String lang,
  required String mimeType,
  required Uint8List audioBytes,
});

String normalizeAudioTranscribeEngine(String engine) {
  final normalized = engine.trim();
  if (normalized == 'multimodal_llm') return 'multimodal_llm';
  if (normalized == 'local_runtime') return 'local_runtime';
  return 'whisper';
}

bool isAutoAudioTranscribeLang(String lang) {
  final normalized = lang.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'auto' ||
      normalized == 'und' ||
      normalized == 'unknown';
}

bool looksLikeAudioMimeType(String mimeType) {
  return mimeType.trim().toLowerCase().startsWith('audio/');
}

bool isByokAudioTranscribeEngine(String engine) {
  final normalized = normalizeAudioTranscribeEngine(engine);
  return normalized == 'whisper' || normalized == 'multimodal_llm';
}

String _formatLocalDayKey(DateTime value) {
  final dt = value.toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String? sniffAudioMimeType(Uint8List bytes) {
  if (bytes.lengthInBytes >= 3 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    return 'audio/mpeg';
  }

  if (bytes.lengthInBytes >= 2 &&
      bytes[0] == 0xFF &&
      (bytes[1] & 0xE0) == 0xE0) {
    return 'audio/mpeg';
  }

  if (bytes.lengthInBytes >= 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4C &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43) {
    return 'audio/flac';
  }

  if (bytes.lengthInBytes >= 4 &&
      bytes[0] == 0x4F &&
      bytes[1] == 0x67 &&
      bytes[2] == 0x67 &&
      bytes[3] == 0x53) {
    return 'audio/ogg';
  }

  if (bytes.lengthInBytes >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45) {
    return 'audio/wav';
  }

  if (bytes.lengthInBytes >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return 'audio/mp4';
  }

  return null;
}

final class AudioTranscribeRunner {
  AudioTranscribeRunner({
    required this.store,
    required this.client,
    AudioTranscribeNowMs? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AudioTranscribeStore store;
  final AudioTranscribeClient client;
  final AudioTranscribeNowMs _nowMs;

  Future<AudioTranscribeRunResult> runOnce({int limit = 5}) async {
    final nowMs = _nowMs();
    final due = await store.listDueJobs(nowMs: nowMs, limit: limit);
    if (due.isEmpty) return const AudioTranscribeRunResult(processed: 0);

    var processed = 0;
    for (final job in due) {
      if (job.status == 'ok') continue;
      try {
        final bytes = await store.readAttachmentBytes(
          attachmentSha256: job.attachmentSha256,
        );
        final mimeType = sniffAudioMimeType(bytes);
        if (mimeType == null) continue;

        final response = await client.transcribe(
          lang: job.lang,
          mimeType: mimeType,
          audioBytes: bytes,
        );

        final payload = _buildPayload(
          response: response,
          engineName: client.engineName,
          modelName: client.modelName,
        );
        await store.markAnnotationOk(
          attachmentSha256: job.attachmentSha256,
          lang: job.lang,
          modelName: client.modelName,
          payloadJson: jsonEncode(payload),
          nowMs: nowMs,
        );
        processed += 1;
      } catch (e) {
        final attempts = job.attempts + 1;
        final nextRetryAtMs = nowMs + _backoffMs(attempts);
        await store.markAnnotationFailed(
          attachmentSha256: job.attachmentSha256,
          error: e.toString(),
          attempts: attempts,
          nextRetryAtMs: nextRetryAtMs,
          nowMs: nowMs,
        );
      }
    }

    return AudioTranscribeRunResult(processed: processed);
  }

  static int _backoffMs(int attempts) {
    final clamped = attempts.clamp(1, 10);
    final seconds = 5 * (1 << (clamped - 1));
    return Duration(seconds: seconds).inMilliseconds;
  }

  static Map<String, Object?> _buildPayload({
    required AudioTranscribeResponse response,
    required String engineName,
    required String modelName,
  }) {
    final full = response.transcriptFull.trim();
    final segments = response.segments
        .map(
          (s) => <String, Object?>{
            't_ms': s.tMs,
            'text': s.text.trim(),
          },
        )
        .toList(growable: false);

    return <String, Object?>{
      'schema': kAudioTranscriptSchema,
      if (response.durationMs != null) 'duration_ms': response.durationMs,
      'transcript_engine': engineName,
      'transcript_model_name': modelName,
      'transcript_segments': segments,
      'transcript_full': full,
      'transcript_excerpt': _excerpt(full),
    };
  }

  static String _excerpt(String text) {
    final v = text.trim();
    if (v.isEmpty) return '';
    const maxChars = 280;
    if (v.length <= maxChars) return v;
    return '${v.substring(0, maxChars)}...';
  }
}

final class BackendAudioTranscribeStore implements AudioTranscribeStore {
  BackendAudioTranscribeStore({
    required this.backend,
    required Uint8List sessionKey,
  }) : _sessionKey = Uint8List.fromList(sessionKey);

  final NativeAppBackend backend;
  final Uint8List _sessionKey;

  @override
  Future<List<AudioTranscribeJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    final rows = await backend.listDueAttachmentAnnotations(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => AudioTranscribeJob(
            attachmentSha256: r.attachmentSha256,
            lang: r.lang,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Uint8List> readAttachmentBytes({
    required String attachmentSha256,
  }) {
    return backend.readAttachmentBytes(
      _sessionKey,
      sha256: attachmentSha256,
    );
  }

  @override
  Future<void> markAnnotationOk({
    required String attachmentSha256,
    required String lang,
    required String modelName,
    required String payloadJson,
    required int nowMs,
  }) {
    return backend.markAttachmentAnnotationOkJson(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      lang: lang,
      modelName: modelName,
      payloadJson: payloadJson,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markAnnotationFailed({
    required String attachmentSha256,
    required String error,
    required int attempts,
    required int nextRetryAtMs,
    required int nowMs,
  }) {
    return backend.markAttachmentAnnotationFailed(
      _sessionKey,
      attachmentSha256: attachmentSha256,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: error,
      nowMs: nowMs,
    );
  }
}
