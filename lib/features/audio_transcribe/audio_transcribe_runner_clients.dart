part of 'audio_transcribe_runner.dart';

const MethodChannel _nativeAudioTranscodeChannel = MethodChannel(
  'secondloop/audio_transcode',
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
    this.modelName = 'base',
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
    final fields = <String, String>{
      'model': modelName.trim().isEmpty ? 'base' : modelName,
      'response_format': 'verbose_json',
      'timestamp_granularities[]': 'segment',
      'stream': 'true',
    };
    if (!isAutoAudioTranscribeLang(lang)) {
      fields['language'] = lang.trim();
    }

    final body = _buildMultipartBody(
      boundary: boundary,
      fields: fields,
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
      case 'audio/m4a':
      case 'audio/x-m4a':
        return 'm4a';
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
      case 'video/webm':
      case 'audio/webm':
        return 'webm';
      case 'video/x-matroska':
      case 'audio/x-matroska':
        return 'mkv';
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
    this.modelName = 'runtime-whisper-base',
    this.whisperModel = 'base',
    this.appDirProvider = getNativeAppDir,
    AudioTranscribeLocalRuntimeAudioDecode? decodeAudioToWav,
    AudioTranscribeLocalRuntimeRequest? requestLocalRuntimeTranscribe,
    AudioTranscribeLocalWhisperRequest? requestLocalWhisperTranscribe,
    AudioTranscribeEnsureLocalWhisperModel? ensureLocalWhisperModelAvailable,
  }) : _requestLocalRuntimeTranscribe = requestLocalRuntimeTranscribe ??
            _buildDefaultLocalRuntimeRequest(
              whisperModel: whisperModel,
              decodeAudioToWav:
                  decodeAudioToWav ?? _decodeAudioToWavForLocalRuntimeDefault,
              requestLocalWhisperTranscribe: requestLocalWhisperTranscribe ??
                  rust_audio_transcribe.audioTranscribeLocalWhisper,
              ensureLocalWhisperModelAvailable:
                  ensureLocalWhisperModelAvailable ??
                      _ensureLocalWhisperModelAvailableDefault,
            );

  @override
  final String modelName;
  final String whisperModel;
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

  static AudioTranscribeLocalRuntimeRequest _buildDefaultLocalRuntimeRequest({
    required String whisperModel,
    required AudioTranscribeLocalRuntimeAudioDecode decodeAudioToWav,
    required AudioTranscribeLocalWhisperRequest requestLocalWhisperTranscribe,
    required AudioTranscribeEnsureLocalWhisperModel
        ensureLocalWhisperModelAvailable,
  }) {
    final normalizedModelName = _normalizeRuntimeWhisperModel(whisperModel);
    return ({
      required String appDir,
      required String lang,
      required String mimeType,
      required Uint8List audioBytes,
    }) {
      return _requestLocalRuntimeWhisperDefault(
        appDir: appDir,
        whisperModel: normalizedModelName,
        lang: lang,
        mimeType: mimeType,
        audioBytes: audioBytes,
        decodeAudioToWav: decodeAudioToWav,
        requestLocalWhisperTranscribe: requestLocalWhisperTranscribe,
        ensureLocalWhisperModelAvailable: ensureLocalWhisperModelAvailable,
      );
    };
  }

  static String _normalizeRuntimeWhisperModel(String model) {
    final normalized = model.trim().toLowerCase();
    switch (normalized) {
      case 'tiny':
      case 'base':
      case 'small':
      case 'medium':
      case 'large-v3':
      case 'large-v3-turbo':
        return normalized;
      default:
        return 'base';
    }
  }

  static Future<String> _requestLocalRuntimeWhisperDefault({
    required String appDir,
    required String whisperModel,
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
    required AudioTranscribeLocalRuntimeAudioDecode decodeAudioToWav,
    required AudioTranscribeLocalWhisperRequest requestLocalWhisperTranscribe,
    required AudioTranscribeEnsureLocalWhisperModel
        ensureLocalWhisperModelAvailable,
  }) async {
    if (kIsWeb) {
      throw StateError('audio_transcribe_local_runtime_unavailable');
    }

    try {
      final trimmedMimeType = mimeType.trim();
      final normalizedMimeType = trimmedMimeType.isEmpty
          ? (sniffAudioMimeType(audioBytes) ?? '')
          : trimmedMimeType;
      final wavBytes = await decodeAudioToWav(
        mimeType: normalizedMimeType,
        audioBytes: audioBytes,
      );
      if (wavBytes.isEmpty) {
        throw StateError('audio_transcribe_local_runtime_empty');
      }

      final normalizedLang = isAutoAudioTranscribeLang(lang) ? '' : lang.trim();
      return await _requestLocalRuntimeWhisperWithModelRecovery(
        appDir: appDir,
        whisperModel: whisperModel,
        lang: normalizedLang,
        wavBytes: wavBytes,
        requestLocalWhisperTranscribe: requestLocalWhisperTranscribe,
        ensureLocalWhisperModelAvailable: ensureLocalWhisperModelAvailable,
      );
    } on StateError {
      rethrow;
    } catch (error) {
      if (error is StateError) rethrow;
      final detail = error.toString().trim();
      if (detail.isEmpty) {
        throw StateError('audio_transcribe_local_runtime_failed');
      }
      throw StateError('audio_transcribe_local_runtime_failed:$detail');
    }
  }

  static Future<String> _requestLocalRuntimeWhisperWithModelRecovery({
    required String appDir,
    required String whisperModel,
    required String lang,
    required List<int> wavBytes,
    required AudioTranscribeLocalWhisperRequest requestLocalWhisperTranscribe,
    required AudioTranscribeEnsureLocalWhisperModel
        ensureLocalWhisperModelAvailable,
  }) async {
    try {
      return await requestLocalWhisperTranscribe(
        appDir: appDir,
        modelName: whisperModel,
        lang: lang,
        wavBytes: wavBytes,
      );
    } on StateError catch (error) {
      if (!_isMissingLocalRuntimeModelError(error)) {
        rethrow;
      }

      try {
        await ensureLocalWhisperModelAvailable(modelName: whisperModel);
      } catch (downloadError) {
        final detail = downloadError.toString().trim();
        if (detail.isEmpty) {
          throw StateError(
            'audio_transcribe_local_runtime_model_download_failed:$whisperModel',
          );
        }
        throw StateError(
          'audio_transcribe_local_runtime_model_download_failed:'
          '$whisperModel:$detail',
        );
      }

      return requestLocalWhisperTranscribe(
        appDir: appDir,
        modelName: whisperModel,
        lang: lang,
        wavBytes: wavBytes,
      );
    }
  }

  static bool _isMissingLocalRuntimeModelError(StateError error) {
    final detail = error.toString().trim().toLowerCase();
    return detail.contains('audio_transcribe_local_runtime_model_missing');
  }

  static Future<void> _ensureLocalWhisperModelAvailableDefault({
    required String modelName,
  }) async {
    if (kIsWeb) return;
    final store = createAudioTranscribeWhisperModelStore();
    if (!store.supportsRuntimeDownload) {
      return;
    }
    await store.ensureModelAvailable(model: modelName);
  }
}

@visibleForTesting
bool shouldBypassLocalRuntimeDecodeForWav({
  required String mimeType,
  required Uint8List audioBytes,
}) {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  final isWavMimeType = normalizedMimeType == 'audio/wav' ||
      normalizedMimeType == 'audio/wave' ||
      normalizedMimeType == 'audio/x-wav';
  if (!isWavMimeType) {
    return false;
  }
  return isCanonicalPcm16Mono16kWavBytes(audioBytes);
}

@visibleForTesting
bool isCanonicalPcm16Mono16kWavBytes(Uint8List bytes) {
  if (bytes.lengthInBytes < 44) {
    return false;
  }

  bool hasAscii(int offset, String value) {
    final units = value.codeUnits;
    if (offset < 0 || offset + units.length > bytes.lengthInBytes) {
      return false;
    }
    for (var i = 0; i < units.length; i++) {
      if (bytes[offset + i] != units[i]) {
        return false;
      }
    }
    return true;
  }

  int readUint16Le(int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int readUint32Le(int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  if (!hasAscii(0, 'RIFF') || !hasAscii(8, 'WAVE')) {
    return false;
  }
  if (!hasAscii(12, 'fmt ') || !hasAscii(36, 'data')) {
    return false;
  }

  final fmtChunkSize = readUint32Le(16);
  if (fmtChunkSize < 16) {
    return false;
  }

  final audioFormat = readUint16Le(20);
  final channelCount = readUint16Le(22);
  final sampleRate = readUint32Le(24);
  final bitsPerSample = readUint16Le(34);
  if (audioFormat != 1 ||
      channelCount != 1 ||
      sampleRate != 16000 ||
      bitsPerSample != 16) {
    return false;
  }

  final dataLength = readUint32Le(40);
  const payloadOffset = 44;
  if (dataLength <= 0) {
    return false;
  }
  if (payloadOffset + dataLength > bytes.lengthInBytes) {
    return false;
  }

  return true;
}

Future<Uint8List> _decodeAudioToWavForLocalRuntimeDefault({
  required String mimeType,
  required Uint8List audioBytes,
}) async {
  final normalizedMimeType = mimeType.trim().toLowerCase();
  final effectiveMimeType = normalizedMimeType.isEmpty
      ? (sniffAudioMimeType(audioBytes) ?? '')
      : normalizedMimeType;

  if (shouldBypassLocalRuntimeDecodeForWav(
    mimeType: effectiveMimeType,
    audioBytes: audioBytes,
  )) {
    return audioBytes;
  }

  if (Platform.isAndroid || Platform.isIOS) {
    return _decodeAudioToWavWithNativeTranscode(
      mimeType: effectiveMimeType,
      audioBytes: audioBytes,
    );
  }

  return _decodeAudioToWavWithBundledFfmpeg(
    mimeType: effectiveMimeType,
    audioBytes: audioBytes,
  );
}

Future<Uint8List> _decodeAudioToWavWithNativeTranscode({
  required String mimeType,
  required Uint8List audioBytes,
}) async {
  Directory? tempDir;
  try {
    tempDir = await Directory.systemTemp
        .createTemp('secondloop-local-whisper-native-');
    final ext = CloudGatewayWhisperAudioTranscribeClient._fileExtByMimeType(
      mimeType,
    );
    final sourcePath = '${tempDir.path}/source.$ext';
    final wavPath = '${tempDir.path}/input.wav';
    await File(sourcePath).writeAsBytes(audioBytes, flush: true);

    final ok = await _nativeAudioTranscodeChannel.invokeMethod<bool>(
      'decodeToWavPcm16Mono16k',
      <String, Object?>{
        'input_path': sourcePath,
        'output_path': wavPath,
      },
    );
    if (ok != true) {
      throw StateError(
        'audio_transcribe_local_runtime_unavailable:audio_decode_failed',
      );
    }

    final wavFile = File(wavPath);
    if (!await wavFile.exists()) {
      throw StateError(
        'audio_transcribe_local_runtime_unavailable:audio_decode_missing',
      );
    }

    final wavBytes = await wavFile.readAsBytes();
    if (wavBytes.isEmpty) {
      throw StateError(
        'audio_transcribe_local_runtime_unavailable:audio_decode_empty',
      );
    }
    return wavBytes;
  } on MissingPluginException {
    throw StateError(
      'audio_transcribe_local_runtime_unavailable:audio_decode_plugin_missing',
    );
  } on PlatformException catch (error) {
    final detailParts = <String>[
      error.code.trim(),
      (error.message ?? '').trim(),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    final detail =
        detailParts.isEmpty ? 'audio_decode_failed' : detailParts.join(':');
    throw StateError('audio_transcribe_local_runtime_unavailable:$detail');
  } finally {
    if (tempDir != null && await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<Uint8List> _decodeAudioToWavWithBundledFfmpeg({
  required String mimeType,
  required Uint8List audioBytes,
}) async {
  final ffmpegPath =
      await _resolveBundledFfmpegExecutablePathForAudioTranscribe();
  if (ffmpegPath == null || ffmpegPath.trim().isEmpty) {
    throw StateError(
        'audio_transcribe_local_runtime_unavailable:ffmpeg_missing');
  }

  Directory? tempDir;
  try {
    tempDir =
        await Directory.systemTemp.createTemp('secondloop-local-whisper-');
    final ext = CloudGatewayWhisperAudioTranscribeClient._fileExtByMimeType(
      mimeType,
    );
    final sourcePath = '${tempDir.path}/source.$ext';
    final wavPath = '${tempDir.path}/input.wav';
    final sourceFile = File(sourcePath);
    final wavFile = File(wavPath);
    await sourceFile.writeAsBytes(audioBytes, flush: true);

    final ffmpegResult = await Process.run(
      ffmpegPath,
      <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        sourcePath,
        '-ac',
        '1',
        '-ar',
        '16000',
        '-c:a',
        'pcm_s16le',
        wavPath,
      ],
    );
    if (ffmpegResult.exitCode != 0 || !await wavFile.exists()) {
      final ffmpegError = [
        ffmpegResult.stderr?.toString().trim() ?? '',
        ffmpegResult.stdout?.toString().trim() ?? '',
      ].where((v) => v.isNotEmpty).join(' | ');
      final detail = ffmpegError.isEmpty
          ? 'ffmpeg_exit_${ffmpegResult.exitCode}'
          : ffmpegError;
      throw StateError('audio_transcribe_local_runtime_failed:$detail');
    }

    return wavFile.readAsBytes();
  } finally {
    if (tempDir != null && await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

AudioTranscribeLocalRuntimeRequest
    selectPlatformLocalRuntimeAudioTranscribeRequest({
  required AudioTranscribeLocalRuntimeRequest methodChannelRequest,
  required AudioTranscribeWindowsNativeSttRequest windowsNativeSttRequest,
  bool? isWindowsHost,
}) {
  final useWindowsNativeStt = isWindowsHost ?? (!kIsWeb && Platform.isWindows);
  if (!useWindowsNativeStt) return methodChannelRequest;
  return ({
    required String appDir,
    required String lang,
    required String mimeType,
    required Uint8List audioBytes,
  }) {
    return windowsNativeSttRequest(
      lang: lang,
      mimeType: mimeType,
      audioBytes: audioBytes,
    );
  };
}
