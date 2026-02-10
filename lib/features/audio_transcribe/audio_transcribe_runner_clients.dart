part of 'audio_transcribe_runner.dart';

const MethodChannel _nativeAudioTranscribeChannel = MethodChannel(
  'secondloop/audio_transcribe',
);

final class FallbackAudioTranscribeClient implements AudioTranscribeClient {
  FallbackAudioTranscribeClient({
    required List<AudioTranscribeClient> chain,
  }) : _chain = List<AudioTranscribeClient>.unmodifiable(
          chain,
        ) {
    if (_chain.isEmpty) {
      throw ArgumentError.value(chain, 'chain', 'must not be empty');
    }
  }

  final List<AudioTranscribeClient> _chain;
  AudioTranscribeClient? _lastSuccessfulClient;

  @override
  String get engineName => (_lastSuccessfulClient ?? _chain.first).engineName;

  @override
  String get modelName => (_lastSuccessfulClient ?? _chain.first).modelName;

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    final errors = <String>[];

    for (final candidate in _chain) {
      try {
        final response = await candidate.transcribe(
          lang: lang,
          mimeType: mimeType,
          audioBytes: audioBytes,
        );
        _lastSuccessfulClient = candidate;
        return response;
      } catch (error) {
        errors.add('${candidate.engineName}:${error.toString()}');
      }
    }

    final joined = errors.join(' | ');
    throw StateError('audio_transcribe_fallback_exhausted:$joined');
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
        'stream': 'true',
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

      final map = _decodeAudioTranscribeResponseMap(raw);
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

    final map = _decodeAudioTranscribeResponseMap(raw);
    final text = extractAudioTranscriptText(map);
    final duration = map['duration'];
    final durationMs = duration is num ? (duration * 1000).round() : null;
    final segments = _parseTranscriptSegments(map['segments']);

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

    final map = _decodeAudioTranscribeResponseMap(raw);
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
      'stream': true,
      'stream_options': <String, Object?>{
        'include_usage': true,
      },
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
    final map = _decodeAudioTranscribeResponseMap(raw);
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

final class LocalRuntimeAudioTranscribeClient implements AudioTranscribeClient {
  LocalRuntimeAudioTranscribeClient({
    this.modelName = 'local_runtime',
    this.appDirProvider = getNativeAppDir,
    AudioTranscribeLocalRuntimeRequest? requestLocalRuntimeTranscribe,
  }) : _requestLocalRuntimeTranscribe =
            requestLocalRuntimeTranscribe ?? _requestLocalRuntimeDefault;

  @override
  final String modelName;
  final Future<String> Function() appDirProvider;
  final AudioTranscribeLocalRuntimeRequest _requestLocalRuntimeTranscribe;

  @override
  String get engineName => 'local_runtime';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }

    final appDir = await appDirProvider();
    final raw = await _requestLocalRuntimeTranscribe(
      appDir: appDir,
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );

    final map = _decodeAudioTranscribeResponseMap(raw);
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

  static Future<String> _requestLocalRuntimeDefault({
    required String appDir,
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    throw StateError('audio_transcribe_local_runtime_unavailable');
  }
}

final class NativeSttAudioTranscribeClient implements AudioTranscribeClient {
  NativeSttAudioTranscribeClient({
    this.modelName = 'native_stt',
    AudioTranscribeNativeSttRequest? requestNativeSttTranscribe,
  }) : _requestNativeSttTranscribe =
            requestNativeSttTranscribe ?? _requestNativeSttDefault;

  @override
  final String modelName;
  final AudioTranscribeNativeSttRequest _requestNativeSttTranscribe;

  @override
  String get engineName => 'native_stt';

  @override
  Future<AudioTranscribeResponse> transcribe({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (audioBytes.isEmpty) {
      throw StateError('audio_bytes_empty');
    }

    final raw = await _requestNativeSttTranscribe(
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );

    final map = _decodeAudioTranscribeResponseMap(raw);
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

  static Future<String> _requestNativeSttDefault({
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) async {
    if (kIsWeb) {
      throw StateError('audio_transcribe_native_stt_unavailable');
    }

    final tempDir =
        await Directory.systemTemp.createTemp('secondloop-native-stt-');
    final ext = CloudGatewayWhisperAudioTranscribeClient._fileExtByMimeType(
      mimeType,
    );
    final audioFile = File('${tempDir.path}/input.$ext');

    try {
      await audioFile.writeAsBytes(audioBytes, flush: true);
      final raw = await _nativeAudioTranscribeChannel.invokeMethod<dynamic>(
        'nativeSttTranscribe',
        <String, Object?>{
          'file_path': audioFile.path,
          'lang': lang.trim(),
          'mime_type': mimeType,
        },
      );

      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          throw StateError('audio_transcribe_native_stt_empty');
        }
        return trimmed;
      }
      if (raw is! Map) {
        throw StateError('audio_transcribe_native_stt_invalid_payload');
      }

      final payload = <String, Object?>{};
      raw.forEach((key, value) {
        payload[key.toString()] = value;
      });

      final text = (payload['text'] ??
              payload['transcript'] ??
              payload['transcript_full'] ??
              '')
          .toString()
          .trim();
      if (text.isEmpty) {
        throw StateError('audio_transcribe_native_stt_empty');
      }
      payload['text'] = text;

      final durationMs = payload['duration_ms'];
      if (payload['duration'] == null && durationMs is num) {
        payload['duration'] = durationMs / 1000;
      }

      return jsonEncode(payload);
    } on MissingPluginException {
      throw StateError('audio_transcribe_native_stt_unavailable');
    } on PlatformException catch (error) {
      final code = error.code.trim();
      final message = (error.message ?? '').trim();
      final detail = [
        if (code.isNotEmpty) code,
        if (message.isNotEmpty) message,
      ].join(':');
      if (detail.isEmpty) {
        throw StateError('audio_transcribe_native_stt_failed');
      }
      throw StateError('audio_transcribe_native_stt_failed:$detail');
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
