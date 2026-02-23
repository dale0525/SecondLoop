import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/ai/audio_transcribe_whisper_model_store.dart';
import '../../core/backend/native_app_dir.dart';
import '../../core/backend/native_backend.dart';
import '../../src/rust/api/audio_transcribe.dart' as rust_audio_transcribe;

part 'audio_transcribe_runner_clients.dart';
part 'audio_transcribe_runner_protocol.dart';
part 'audio_transcribe_runner_windows_stt.dart';

const String kAudioTranscriptSchema = 'secondloop.audio_transcript.v1';

final class AudioTranscribeJob {
  const AudioTranscribeJob({
    required this.attachmentSha256,
    required this.lang,
    required this.status,
    required this.attempts,
    required this.nextRetryAtMs,
    this.mimeTypeHint = '',
  });

  final String attachmentSha256;
  final String lang;
  final String status;
  final int attempts;
  final int? nextRetryAtMs;
  final String mimeTypeHint;
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
    this.failed = 0,
  });

  final int processed;
  final int failed;
  bool get didEnrichAny => processed > 0;
  bool get didMutateAny => processed > 0 || failed > 0;
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
typedef AudioTranscribeLocalWhisperRequest = Future<String> Function({
  required String appDir,
  required String modelName,
  required String lang,
  required List<int> wavBytes,
});
typedef AudioTranscribeEnsureLocalWhisperModel = Future<void> Function({
  required String modelName,
});
typedef AudioTranscribeWindowsNativeSttRequest = Future<String> Function({
  required String lang,
  required String mimeType,
  required Uint8List audioBytes,
});
typedef AudioTranscribeLocalRuntimeAudioDecode = Future<Uint8List> Function({
  required String mimeType,
  required Uint8List audioBytes,
});

String normalizeAudioTranscribeEngine(String engine) {
  final normalized = engine.trim();
  if (normalized == 'multimodal_llm') return 'multimodal_llm';
  if (normalized == 'local_runtime') return 'local_runtime';
  return 'whisper';
}

bool supportsPlatformLocalRuntimeAudioTranscribe() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

bool supportsPlatformLocalAudioTranscribe() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

bool shouldEnableLocalRuntimeAudioFallback({
  required bool supportsLocalRuntime,
  required bool cloudEnabled,
  required bool hasByokProfile,
  required String effectiveEngine,
}) {
  if (!supportsLocalRuntime) return false;
  final normalizedEngine = normalizeAudioTranscribeEngine(effectiveEngine);
  return normalizedEngine == 'local_runtime' ||
      isByokAudioTranscribeEngine(normalizedEngine) ||
      hasByokProfile ||
      cloudEnabled;
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

  if (bytes.lengthInBytes >= 4 &&
      bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3) {
    final probeLen = bytes.lengthInBytes < 96 ? bytes.lengthInBytes : 96;
    final probe = utf8.decode(
      bytes.sublist(0, probeLen),
      allowMalformed: true,
    );
    if (probe.toLowerCase().contains('webm')) {
      return 'video/webm';
    }
    return 'video/x-matroska';
  }

  return null;
}

String? resolveAudioTranscribeMimeType({
  required Uint8List bytes,
  required String mimeTypeHint,
}) {
  final normalizedHint = mimeTypeHint.trim().toLowerCase();
  final hasExplicitHint = normalizedHint.startsWith('audio/') ||
      normalizedHint.startsWith('video/');

  final sniffedMimeType = sniffAudioMimeType(bytes)?.trim().toLowerCase();
  if (sniffedMimeType != null && sniffedMimeType.isNotEmpty) {
    if (hasExplicitHint) {
      final hintIsAudio = normalizedHint.startsWith('audio/');
      final hintIsVideo = normalizedHint.startsWith('video/');
      final sniffedIsAudio = sniffedMimeType.startsWith('audio/');
      final sniffedIsVideo = sniffedMimeType.startsWith('video/');
      final hasContainerFamilyConflict =
          (hintIsAudio && sniffedIsVideo) || (hintIsVideo && sniffedIsAudio);
      if (hasContainerFamilyConflict) {
        return normalizedHint;
      }
    }

    return sniffedMimeType;
  }

  if (hasExplicitHint) {
    return normalizedHint;
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
    final processLimit = limit < 1 ? 1 : limit;
    const scanLimit = 500;
    final nowMs = _nowMs();
    final due = await store.listDueJobs(nowMs: nowMs, limit: scanLimit);
    if (due.isEmpty) {
      return const AudioTranscribeRunResult(
        processed: 0,
        failed: 0,
      );
    }

    var processed = 0;
    var failed = 0;
    var handled = 0;
    for (final job in due) {
      if (handled >= processLimit) break;
      if (job.status == 'ok') continue;

      final normalizedMimeTypeHint = job.mimeTypeHint.trim().toLowerCase();
      if (normalizedMimeTypeHint.isNotEmpty &&
          !normalizedMimeTypeHint.startsWith('audio/') &&
          !normalizedMimeTypeHint.startsWith('video/')) {
        continue;
      }

      try {
        final bytes = await store.readAttachmentBytes(
          attachmentSha256: job.attachmentSha256,
        );
        final mimeType = resolveAudioTranscribeMimeType(
          bytes: bytes,
          mimeTypeHint: job.mimeTypeHint,
        );
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
        handled += 1;
      } catch (e) {
        final attempts = job.attempts + 1;
        final nextRetryAtMs = _nextRetryAtMsForError(
          nowMs: nowMs,
          attempts: attempts,
          error: e,
        );
        await store.markAnnotationFailed(
          attachmentSha256: job.attachmentSha256,
          error: e.toString(),
          attempts: attempts,
          nextRetryAtMs: nextRetryAtMs,
          nowMs: nowMs,
        );
        failed += 1;
        handled += 1;
      }
    }

    return AudioTranscribeRunResult(
      processed: processed,
      failed: failed,
    );
  }

  static int _backoffMs(int attempts) {
    final clamped = attempts.clamp(1, 10);
    final seconds = 5 * (1 << (clamped - 1));
    return Duration(seconds: seconds).inMilliseconds;
  }

  static int _nextRetryAtMsForError({
    required int nowMs,
    required int attempts,
    required Object error,
  }) {
    if (_isLongBackoffError(error)) {
      return nowMs + const Duration(hours: 12).inMilliseconds;
    }
    return nowMs + _backoffMs(attempts);
  }

  static bool _isLongBackoffError(Object error) {
    final detail = error.toString().trim().toLowerCase();
    if (detail.isEmpty) return false;
    return detail.contains('audio_transcribe_native_stt_missing_speech_pack') ||
        detail.contains('speech_recognizer_unavailable') ||
        detail.contains('audio_transcribe_local_runtime_model_missing');
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
    if (rows.isEmpty) return const <AudioTranscribeJob>[];

    final mimeTypeBySha = <String, String>{};
    try {
      final recent = await backend.listRecentAttachments(
        _sessionKey,
        limit: limit.clamp(20, 120) * 8,
      );
      for (final attachment in recent) {
        final sha = attachment.sha256.trim();
        if (sha.isEmpty || mimeTypeBySha.containsKey(sha)) continue;
        mimeTypeBySha[sha] = attachment.mimeType.trim().toLowerCase();
      }
    } catch (_) {
      // Best-effort hint loading.
    }

    return rows
        .map(
          (r) => AudioTranscribeJob(
            attachmentSha256: r.attachmentSha256,
            lang: r.lang,
            status: r.status,
            attempts: r.attempts,
            nextRetryAtMs: r.nextRetryAtMs,
            mimeTypeHint: mimeTypeBySha[r.attachmentSha256] ?? '',
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
