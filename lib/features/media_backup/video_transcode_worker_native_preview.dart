part of 'video_transcode_worker.dart';

Future<VideoPreviewExtractResult> _extractPreviewWithNativePlatformApiInternal(
  Uint8List videoBytes, {
  required String sourceMimeType,
  VideoNativePreviewExtractor? nativePreviewExtractor,
}) async {
  final extractor = nativePreviewExtractor ??
      VideoTranscodeWorker._extractPreviewWithNativePlatformChannel;
  try {
    final result = await extractor(
      videoBytes,
      sourceMimeType: sourceMimeType,
    );
    final normalized = _ensurePosterBackedKeyframeInternal(
      _normalizeNativePreviewFramesInternal(result),
    );
    if (normalized.hasAnyPosterOrKeyframe) {
      return normalized;
    }
  } catch (_) {
    // Ignore native fallback errors.
  }

  return _kEmptyVideoPreviewExtractResult;
}

VideoPreviewExtractResult _normalizeNativePreviewFramesInternal(
  VideoPreviewExtractResult result,
) {
  final originalFrames = result.keyframes;
  if (originalFrames.length <= 1) {
    return result;
  }

  final acceptedFrames = <VideoPreviewFrame>[];
  final acceptedSignatures = <({int hash, double darkRatio})?>[];
  final seenFrameBytes = <String>{};

  for (final frame in originalFrames) {
    final frameBytes = frame.bytes;
    if (frameBytes.isEmpty) {
      continue;
    }

    final bytesSignature = base64.encode(frameBytes);
    if (!seenFrameBytes.add(bytesSignature)) {
      continue;
    }

    final visualSignature =
        VideoTranscodeWorker._buildFrameVisualSignature(frameBytes);
    if (acceptedFrames.isNotEmpty && visualSignature != null) {
      final previousSignature = acceptedSignatures.last;
      if (previousSignature != null &&
          VideoTranscodeWorker._areFramesNearDuplicate(
            previousSignature,
            visualSignature,
          )) {
        if (VideoTranscodeWorker._shouldPreferRicherFrame(
          previousSignature,
          visualSignature,
        )) {
          acceptedFrames[acceptedFrames.length - 1] = frame;
          acceptedSignatures[acceptedSignatures.length - 1] = visualSignature;
        }
        continue;
      }

      final globalDuplicateIndex =
          VideoTranscodeWorker._findNearDuplicateFrameIndex(
        acceptedSignatures,
        visualSignature,
        maxIndexExclusive: acceptedSignatures.length - 1,
        matcher: VideoTranscodeWorker._areFramesGlobalDuplicate,
      );
      if (globalDuplicateIndex != null) {
        continue;
      }
    }

    acceptedFrames.add(frame);
    acceptedSignatures.add(visualSignature);
  }

  final normalizedFrames = List<VideoPreviewFrame>.unmodifiable([
    for (var i = 0; i < acceptedFrames.length; i++)
      VideoPreviewFrame(
        index: i,
        bytes: acceptedFrames[i].bytes,
        mimeType: acceptedFrames[i].mimeType,
        tMs: acceptedFrames[i].tMs,
        kind: acceptedFrames[i].kind,
      ),
  ]);

  return VideoPreviewExtractResult(
    posterBytes: result.posterBytes,
    posterMimeType: result.posterMimeType,
    keyframes: normalizedFrames,
  );
}

VideoPreviewExtractResult _ensurePosterBackedKeyframeInternal(
  VideoPreviewExtractResult result,
) {
  final posterBytes = result.posterBytes;
  if (posterBytes == null || posterBytes.isEmpty) {
    return result;
  }
  if (result.keyframes.isNotEmpty) {
    return result;
  }

  return VideoPreviewExtractResult(
    posterBytes: posterBytes,
    posterMimeType: result.posterMimeType,
    keyframes: List<VideoPreviewFrame>.unmodifiable([
      VideoPreviewFrame(
        index: 0,
        bytes: posterBytes,
        mimeType: result.posterMimeType,
        tMs: 0,
        kind: 'scene',
      ),
    ]),
  );
}

Future<VideoPreviewExtractResult>
    _extractPreviewWithNativePlatformChannelInternal(
  Uint8List videoBytes, {
  required String sourceMimeType,
}) async {
  if (kIsWeb) {
    return _kEmptyVideoPreviewExtractResult;
  }
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return _kEmptyVideoPreviewExtractResult;
  }

  Directory? tempDir;
  try {
    tempDir = await Directory.systemTemp.createTemp(
      'secondloop_video_preview_native_',
    );
    final sourceExt =
        VideoTranscodeWorker._extensionForMimeType(sourceMimeType);
    final inputPath = '${tempDir.path}/input.$sourceExt';
    final outputDirPath = '${tempDir.path}/preview_frames';
    final outputDir = Directory(outputDirPath);
    await outputDir.create(recursive: true);
    await File(inputPath).writeAsBytes(videoBytes, flush: true);

    final framePayload = await VideoTranscodeWorker._videoTranscodeChannel
        .invokeMethod<Map<dynamic, dynamic>>(
      'extractPreviewFramesJpeg',
      <String, Object?>{
        'input_path': inputPath,
        'output_dir': outputDirPath,
        'max_keyframes': 24,
        'frame_interval_seconds': 8,
      },
    );

    final parsedFrames = await _parseNativePreviewFramesPayload(
      payload: framePayload,
      outputDirPath: outputDirPath,
    );
    if (parsedFrames != null && parsedFrames.hasAnyPosterOrKeyframe) {
      return parsedFrames;
    }

    final posterPath = '$outputDirPath/poster.jpg';
    final ok =
        await VideoTranscodeWorker._videoTranscodeChannel.invokeMethod<bool>(
      'extractPreviewPosterJpeg',
      <String, Object?>{
        'input_path': inputPath,
        'output_path': posterPath,
      },
    );
    if (ok != true) {
      return _kEmptyVideoPreviewExtractResult;
    }

    final posterBytes = await _readPreviewBytesIfExists(posterPath);
    if (posterBytes == null || posterBytes.isEmpty) {
      return _kEmptyVideoPreviewExtractResult;
    }

    return VideoPreviewExtractResult(
      posterBytes: posterBytes,
      posterMimeType: 'image/jpeg',
      keyframes: const <VideoPreviewFrame>[],
    );
  } on MissingPluginException {
    return _kEmptyVideoPreviewExtractResult;
  } on PlatformException {
    return _kEmptyVideoPreviewExtractResult;
  } catch (_) {
    return _kEmptyVideoPreviewExtractResult;
  } finally {
    if (tempDir != null) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore temp cleanup failures.
      }
    }
  }
}

Future<VideoPreviewExtractResult?> _parseNativePreviewFramesPayload({
  required Map<dynamic, dynamic>? payload,
  required String outputDirPath,
}) async {
  if (payload == null || payload.isEmpty) {
    return null;
  }

  String resolvePath(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';
    final file = File(value);
    if (file.isAbsolute) return file.path;
    return '$outputDirPath/$value';
  }

  final posterPath = resolvePath(payload['poster_path']);
  final posterBytes = await _readPreviewBytesIfExists(posterPath);

  final rawFrames = payload['keyframes'];
  final keyframes = <VideoPreviewFrame>[];
  final seen = <String>{};

  if (rawFrames is List) {
    for (final item in rawFrames) {
      if (item is! Map) continue;
      final framePath = resolvePath(item['path']);
      final frameBytes = await _readPreviewBytesIfExists(framePath);
      if (frameBytes == null || frameBytes.isEmpty) continue;

      final signature = base64.encode(frameBytes);
      if (!seen.add(signature)) continue;

      final rawTime = item['t_ms'];
      int tMs = 0;
      if (rawTime is int) {
        tMs = rawTime;
      } else if (rawTime is num) {
        tMs = rawTime.toInt();
      } else if (rawTime is String) {
        tMs = int.tryParse(rawTime.trim()) ?? 0;
      }
      if (tMs < 0) tMs = 0;

      keyframes.add(
        VideoPreviewFrame(
          index: keyframes.length,
          bytes: frameBytes,
          mimeType: 'image/jpeg',
          tMs: tMs,
          kind: 'scene',
        ),
      );
    }
  }

  return VideoPreviewExtractResult(
    posterBytes: posterBytes,
    posterMimeType: 'image/jpeg',
    keyframes: List<VideoPreviewFrame>.unmodifiable(keyframes),
  );
}

Future<Uint8List?> _readPreviewBytesIfExists(String path) async {
  final normalized = path.trim();
  if (normalized.isEmpty) return null;
  final file = File(normalized);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return null;
  return bytes;
}
