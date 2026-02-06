import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/backend/native_app_dir.dart';
import '../../core/backend/native_backend.dart';
import '../../src/rust/api/audio_transcribe.dart' as rust_audio_transcribe;

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

String normalizeAudioTranscribeEngine(String engine) {
  final normalized = engine.trim();
  if (normalized == 'multimodal_llm') return 'multimodal_llm';
  return 'whisper';
}

bool looksLikeAudioMimeType(String mimeType) {
  return mimeType.trim().toLowerCase().startsWith('audio/');
}

String _formatLocalDayKey(DateTime value) {
  final dt = value.toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _audioInputFormatByMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  switch (normalized) {
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/wav':
    case 'audio/wave':
    case 'audio/x-wav':
      return 'wav';
    case 'audio/ogg':
    case 'audio/opus':
      return 'ogg';
    case 'audio/flac':
      return 'flac';
    case 'audio/aac':
      return 'aac';
    case 'audio/mp4':
    case 'audio/m4a':
    case 'audio/x-m4a':
      return 'm4a';
    default:
      return 'mp3';
  }
}

String _multimodalTranscribePrompt(String lang) {
  final trimmed = lang.trim();
  if (trimmed.isEmpty) {
    return 'Transcribe the provided audio and return plain text only.';
  }
  return 'Transcribe the provided audio in language "$trimmed" and return plain text only.';
}

String _normalizeTranscriptText(String text) {
  var trimmed = text.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('```')) {
    trimmed = trimmed
        .replaceFirst(RegExp(r'^```[^\n]*\n?'), '')
        .replaceFirst(RegExp(r'\n?```$'), '')
        .trim();
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is String) return decoded.trim();
    if (decoded is Map) {
      final textCandidate = decoded['text']?.toString().trim();
      if ((textCandidate ?? '').isNotEmpty) return textCandidate!;
      final transcriptCandidate = decoded['transcript']?.toString().trim();
      if ((transcriptCandidate ?? '').isNotEmpty) return transcriptCandidate!;
    }
  } catch (_) {
    // Not JSON, keep text as-is.
  }

  return trimmed;
}

String _chatMessageContentToText(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is! Map) continue;
      final text = item['text']?.toString() ?? '';
      if (text.trim().isNotEmpty) {
        parts.add(text);
      }
    }
    return parts.join('\n');
  }
  if (content is Map) {
    final text = content['text']?.toString() ?? '';
    if (text.trim().isNotEmpty) return text;
  }
  return content.toString();
}

String extractAudioTranscriptText(Map<String, Object?> decoded) {
  final directText = decoded['text']?.toString() ?? '';
  final directTranscript = decoded['transcript']?.toString() ?? '';
  var text = _normalizeTranscriptText(
    directText.trim().isNotEmpty ? directText : directTranscript,
  );
  if (text.isNotEmpty) return text;

  final choicesRaw = decoded['choices'];
  if (choicesRaw is List && choicesRaw.isNotEmpty) {
    final first = choicesRaw.first;
    if (first is Map) {
      final message = first['message'];
      if (message is Map) {
        final content = _chatMessageContentToText(message['content']);
        text = _normalizeTranscriptText(content);
      } else {
        final content = _chatMessageContentToText(first['content']);
        text = _normalizeTranscriptText(content);
      }
    }
  }
  if (text.isNotEmpty) return text;
  throw StateError('audio_transcribe_empty_text');
}

List<AudioTranscriptSegment> _parseTranscriptSegments(Object? segmentsRaw) {
  final segments = <AudioTranscriptSegment>[];
  if (segmentsRaw is! List) return segments;
  for (final item in segmentsRaw) {
    if (item is! Map) continue;
    final segText = (item['text'] ?? '').toString().trim();
    if (segText.isEmpty) continue;
    final tMsRaw = item['t_ms'];
    if (tMsRaw is num) {
      segments.add(AudioTranscriptSegment(tMs: tMsRaw.round(), text: segText));
      continue;
    }
    final start = item['start'];
    final tMs = start is num ? (start * 1000).round() : 0;
    segments.add(AudioTranscriptSegment(tMs: tMs, text: segText));
  }
  return segments;
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

final class CloudGatewayWhisperAudioTranscribeClient
    implements AudioTranscribeClient {
  CloudGatewayWhisperAudioTranscribeClient({
    required this.gatewayBaseUrl,
    required this.idToken,
    this.modelName = 'cloud',
  });

  final String gatewayBaseUrl;
  final String idToken;
  @override
  final String modelName;

  @override
  String get engineName => 'cloud_gateway';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (gatewayBaseUrl.trim().isEmpty) {
      throw StateError('missing_gateway_base_url');
    }
    if (idToken.trim().isEmpty) {
      throw StateError('missing_id_token');
    }
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }

    final uri = Uri.parse(
      '${gatewayBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/audio/transcriptions',
    );
    final boundary =
        'secondloop-audio-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final ext = _fileExtByMimeType(mimeType);
    final body = _buildMultipartBody(
      boundary: boundary,
      fields: <String, String>{
        'model': modelName.trim().isEmpty ? 'cloud' : modelName,
        'response_format': 'verbose_json',
        'language': lang,
        'timestamp_granularities[]': 'segment',
      },
      fileFieldName: 'file',
      fileName: 'audio.$ext',
      fileMimeType: mimeType,
      fileBytes: audioBytes,
    );

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${idToken.trim()}');
      req.headers.set('x-secondloop-purpose', 'audio_transcribe');
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      req.contentLength = body.length;
      req.add(body);

      final resp = await req.close();
      final raw = await utf8.decodeStream(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw StateError(
          'audio_transcribe_http_${resp.statusCode}:${raw.trim()}',
        );
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw StateError('audio_transcribe_invalid_json');
      }
      final map = Map<String, Object?>.from(decoded);
      final text = extractAudioTranscriptText(map);

      final duration = map['duration'];
      final durationMs = duration is num ? (duration * 1000).round() : null;
      final segments = _parseTranscriptSegments(map['segments']);

      return AudioTranscribeResponse(
        durationMs: durationMs,
        transcriptFull: text,
        segments: segments,
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _fileExtByMimeType(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    switch (normalized) {
      case 'audio/mp4':
        return 'm4a';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/wav':
      case 'audio/wave':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/flac':
        return 'flac';
      case 'audio/ogg':
      case 'audio/opus':
        return 'ogg';
      case 'audio/aac':
        return 'aac';
      default:
        return 'bin';
    }
  }

  static Uint8List _buildMultipartBody({
    required String boundary,
    required Map<String, String> fields,
    required String fileFieldName,
    required String fileName,
    required String fileMimeType,
    required Uint8List fileBytes,
  }) {
    final builder = BytesBuilder(copy: false);
    for (final entry in fields.entries) {
      builder.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'
          '${entry.value}\r\n',
        ),
      );
    }

    builder.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$fileFieldName"; filename="$fileName"\r\n'
        'Content-Type: $fileMimeType\r\n\r\n',
      ),
    );
    builder.add(fileBytes);
    builder.add(utf8.encode('\r\n--$boundary--\r\n'));
    return builder.takeBytes();
  }
}

final class ByokWhisperAudioTranscribeClient implements AudioTranscribeClient {
  ByokWhisperAudioTranscribeClient({
    required Uint8List sessionKey,
    required this.profileId,
    required this.modelName,
    this.appDirProvider = getNativeAppDir,
    AudioTranscribeByokRequest? requestByokTranscribe,
  })  : _sessionKey = Uint8List.fromList(sessionKey),
        _requestByokTranscribe = requestByokTranscribe ??
            rust_audio_transcribe.audioTranscribeByokProfile;

  final Uint8List _sessionKey;
  final String profileId;
  @override
  final String modelName;
  final Future<String> Function() appDirProvider;
  final AudioTranscribeByokRequest _requestByokTranscribe;

  @override
  String get engineName => 'whisper';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }
    if (profileId.trim().isEmpty) {
      throw StateError('missing_profile_id');
    }
    final appDir = await appDirProvider();
    final raw = await _requestByokTranscribe(
      appDir: appDir,
      key: _sessionKey,
      profileId: profileId,
      localDay: _formatLocalDayKey(DateTime.now()),
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('audio_transcribe_invalid_json');
    }
    final text =
        (decoded['text'] ?? decoded['transcript'] ?? '').toString().trim();
    if (text.isEmpty) {
      throw StateError('audio_transcribe_empty_text');
    }

    final duration = decoded['duration'];
    final durationMs = duration is num ? (duration * 1000).round() : null;
    final segments = _parseTranscriptSegments(decoded['segments']);

    return AudioTranscribeResponse(
      durationMs: durationMs,
      transcriptFull: text,
      segments: segments,
    );
  }
}

final class CloudGatewayMultimodalAudioTranscribeClient
    implements AudioTranscribeClient {
  CloudGatewayMultimodalAudioTranscribeClient({
    required this.gatewayBaseUrl,
    required this.idToken,
    this.modelName = 'cloud',
    AudioTranscribeCloudMultimodalRequest? requestCloudGatewayMultimodal,
  }) : _requestCloudGatewayMultimodal = requestCloudGatewayMultimodal ??
            _requestCloudGatewayMultimodalDefault;

  final String gatewayBaseUrl;
  final String idToken;
  @override
  final String modelName;
  final AudioTranscribeCloudMultimodalRequest _requestCloudGatewayMultimodal;

  @override
  String get engineName => 'multimodal_llm';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (gatewayBaseUrl.trim().isEmpty) {
      throw StateError('missing_gateway_base_url');
    }
    if (idToken.trim().isEmpty) {
      throw StateError('missing_id_token');
    }
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }

    final raw = await _requestCloudGatewayMultimodal(
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('audio_transcribe_invalid_json');
    }
    final map = Map<String, Object?>.from(decoded);
    final transcript = extractAudioTranscriptText(map);
    final duration = map['duration'];
    final durationMs = duration is num ? (duration * 1000).round() : null;
    final segments = _parseTranscriptSegments(map['segments']);

    return AudioTranscribeResponse(
      durationMs: durationMs,
      transcriptFull: transcript,
      segments: segments,
    );
  }

  static Future<String> _requestCloudGatewayMultimodalDefault({
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    final uri = Uri.parse(
      '${gatewayBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/chat/completions',
    );
    final payload = <String, Object?>{
      'model': modelName.trim().isEmpty ? 'cloud' : modelName,
      'messages': <Object?>[
        {
          'role': 'user',
          'content': <Object?>[
            {
              'type': 'text',
              'text': _multimodalTranscribePrompt(lang),
            },
            {
              'type': 'input_audio',
              'input_audio': <String, Object?>{
                'data': base64Encode(audioBytes),
                'format': _audioInputFormatByMimeType(mimeType),
              },
            },
          ],
        },
      ],
      'stream': false,
    };

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${idToken.trim()}');
      req.headers.set('x-secondloop-purpose', 'audio_transcribe');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final body = utf8.encode(jsonEncode(payload));
      req.contentLength = body.length;
      req.add(body);

      final resp = await req.close();
      final raw = await utf8.decodeStream(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw StateError(
          'audio_transcribe_http_${resp.statusCode}:${raw.trim()}',
        );
      }
      return raw;
    } finally {
      client.close(force: true);
    }
  }
}

final class ByokMultimodalAudioTranscribeClient
    implements AudioTranscribeClient {
  ByokMultimodalAudioTranscribeClient({
    required Uint8List sessionKey,
    required this.profileId,
    required this.modelName,
    this.appDirProvider = getNativeAppDir,
    AudioTranscribeByokMultimodalRequest? requestByokMultimodalTranscribe,
  })  : _sessionKey = Uint8List.fromList(sessionKey),
        _requestByokMultimodalTranscribe = requestByokMultimodalTranscribe ??
            rust_audio_transcribe.audioTranscribeByokProfileMultimodal;

  final Uint8List _sessionKey;
  final String profileId;
  @override
  final String modelName;
  final Future<String> Function() appDirProvider;
  final AudioTranscribeByokMultimodalRequest _requestByokMultimodalTranscribe;

  @override
  String get engineName => 'multimodal_llm';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }
    if (profileId.trim().isEmpty) {
      throw StateError('missing_profile_id');
    }

    final appDir = await appDirProvider();
    final raw = await _requestByokMultimodalTranscribe(
      appDir: appDir,
      key: _sessionKey,
      profileId: profileId,
      localDay: _formatLocalDayKey(DateTime.now()),
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('audio_transcribe_invalid_json');
    }

    final map = Map<String, Object?>.from(decoded);
    final transcript = extractAudioTranscriptText(map);
    final duration = map['duration'];
    final durationMs = duration is num ? (duration * 1000).round() : null;
    final segments = _parseTranscriptSegments(map['segments']);

    return AudioTranscribeResponse(
      durationMs: durationMs,
      transcriptFull: transcript,
      segments: segments,
    );
  }
}
