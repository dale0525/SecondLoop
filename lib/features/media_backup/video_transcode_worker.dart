import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class VideoTranscodeSegment {
  const VideoTranscodeSegment({
    required this.index,
    required this.bytes,
    required this.mimeType,
  });

  final int index;
  final Uint8List bytes;
  final String mimeType;
}

final class VideoTranscodeResult {
  const VideoTranscodeResult({
    required this.bytes,
    required this.mimeType,
    required this.didTranscode,
    required this.segments,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool didTranscode;
  final List<VideoTranscodeSegment> segments;

  bool get isStrictVideoProxy {
    if (!didTranscode) return false;
    if (mimeType.trim().toLowerCase() != VideoTranscodeWorker.targetMimeType) {
      return false;
    }
    if (segments.isEmpty) return false;
    for (final segment in segments) {
      if (segment.bytes.isEmpty) return false;
      if (segment.mimeType.trim().toLowerCase() !=
          VideoTranscodeWorker.targetMimeType) {
        return false;
      }
    }
    return true;
  }

  bool canUseBoundedPassthroughProxy({
    required int maxSegmentBytes,
    Set<String> allowedMimeTypes = const {
      'video/mp4',
      'video/quicktime',
    },
  }) {
    if (didTranscode) return false;
    if (maxSegmentBytes <= 0) return false;
    if (segments.isEmpty) return false;

    final allowed = allowedMimeTypes
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (allowed.isEmpty) return false;

    if (!allowed.contains(mimeType.trim().toLowerCase())) {
      return false;
    }

    for (final segment in segments) {
      if (segment.bytes.isEmpty) return false;
      if (segment.bytes.lengthInBytes > maxSegmentBytes) return false;
      if (!allowed.contains(segment.mimeType.trim().toLowerCase())) {
        return false;
      }
    }
    return true;
  }
}

final class VideoPreviewFrame {
  const VideoPreviewFrame({
    required this.index,
    required this.bytes,
    required this.mimeType,
    required this.tMs,
    required this.kind,
  });

  final int index;
  final Uint8List bytes;
  final String mimeType;
  final int tMs;
  final String kind;
}

final class VideoPreviewExtractResult {
  const VideoPreviewExtractResult({
    required this.posterBytes,
    required this.posterMimeType,
    required this.keyframes,
  });

  final Uint8List? posterBytes;
  final String posterMimeType;
  final List<VideoPreviewFrame> keyframes;

  bool get hasAnyPosterOrKeyframe =>
      (posterBytes != null && posterBytes!.isNotEmpty) || keyframes.isNotEmpty;
}

typedef VideoTranscodeCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef VideoFfmpegExecutableResolver = Future<String?> Function();

final class VideoTranscodeWorker {
  static const String targetMimeType = 'video/mp4';
  static const int _defaultMaxSegmentDurationSeconds = 20 * 60;
  static const int _defaultMaxSegmentBytes = 50 * 1024 * 1024;

  static String? _cachedBundledFfmpegExecutablePath;

  @visibleForTesting
  static VideoFfmpegExecutableResolver? debugFfmpegExecutableResolver;

  static Future<VideoTranscodeResult> transcodeToSegmentedMp4Proxy(
    Uint8List originalBytes, {
    required String sourceMimeType,
    int maxSegmentDurationSeconds = _defaultMaxSegmentDurationSeconds,
    int maxSegmentBytes = _defaultMaxSegmentBytes,
    VideoTranscodeCommandRunner? commandRunner,
    VideoFfmpegExecutableResolver? ffmpegExecutableResolver,
  }) async {
    final normalizedMime = sourceMimeType.trim().toLowerCase();
    if (!normalizedMime.startsWith('video/')) {
      return _fallback(originalBytes, sourceMimeType);
    }
    if (originalBytes.isEmpty) {
      return _fallback(originalBytes, sourceMimeType);
    }

    final run = commandRunner ?? Process.run;
    final ffmpegResolver = ffmpegExecutableResolver ??
        debugFfmpegExecutableResolver ??
        _resolveBundledFfmpegExecutablePath;
    final ffmpegPath = await ffmpegResolver();
    if (ffmpegPath == null || ffmpegPath.trim().isEmpty) {
      return _fallback(originalBytes, sourceMimeType);
    }

    final safeSegmentDuration = maxSegmentDurationSeconds.clamp(60, 20 * 60);
    final safeSegmentBytes =
        maxSegmentBytes.clamp(1 * 1024 * 1024, 50 * 1024 * 1024);

    Directory? tempDir;
    try {
      tempDir =
          await Directory.systemTemp.createTemp('secondloop_video_transcode_');
      final sourceExt = _extensionForMimeType(normalizedMime);
      final inputPath = '${tempDir.path}/input.$sourceExt';
      final segmentPattern = '${tempDir.path}/segment_%03d.mp4';

      await File(inputPath).writeAsBytes(originalBytes, flush: true);

      final transcodeArgs = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-map',
        '0:a?',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-b:v',
        '220k',
        '-maxrate',
        '260k',
        '-bufsize',
        '520k',
        '-vf',
        'scale=-2:480',
        '-c:a',
        'aac',
        '-b:a',
        '32k',
        '-ar',
        '24000',
        '-ac',
        '1',
        '-movflags',
        '+faststart',
        '-f',
        'segment',
        '-segment_time',
        '$safeSegmentDuration',
        '-reset_timestamps',
        '1',
        segmentPattern,
      ];

      final ffmpegResult = await run(ffmpegPath, transcodeArgs);
      if (ffmpegResult.exitCode != 0) {
        return _fallback(originalBytes, sourceMimeType);
      }

      final segmentFiles = await _listSegmentFiles(tempDir.path);
      if (segmentFiles.isEmpty) {
        return _fallback(originalBytes, sourceMimeType);
      }

      final segments = <VideoTranscodeSegment>[];
      for (var i = 0; i < segmentFiles.length; i++) {
        final segmentBytes = await segmentFiles[i].readAsBytes();
        if (segmentBytes.isEmpty) continue;

        Uint8List bestBytes = segmentBytes;
        if (bestBytes.lengthInBytes > safeSegmentBytes) {
          final compressed = await _reencodeSegmentWithinSize(
            ffmpegPath,
            run,
            segmentFiles[i].path,
            tempDir.path,
            safeSegmentBytes,
            i,
          );
          if (compressed != null && compressed.isNotEmpty) {
            bestBytes = compressed;
          }
        }

        if (bestBytes.lengthInBytes > safeSegmentBytes) {
          return _fallback(originalBytes, sourceMimeType);
        }

        segments.add(
          VideoTranscodeSegment(
            index: i,
            bytes: bestBytes,
            mimeType: targetMimeType,
          ),
        );
      }

      if (segments.isEmpty) {
        return _fallback(originalBytes, sourceMimeType);
      }

      return VideoTranscodeResult(
        bytes: segments.first.bytes,
        mimeType: targetMimeType,
        didTranscode: true,
        segments: List<VideoTranscodeSegment>.unmodifiable(segments),
      );
    } catch (_) {
      return _fallback(originalBytes, sourceMimeType);
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

  static Future<VideoPreviewExtractResult> extractPreviewFrames(
    Uint8List videoBytes, {
    required String sourceMimeType,
    int maxKeyframes = 4,
    int frameIntervalSeconds = 8,
    String keyframeKind = 'scene',
    VideoTranscodeCommandRunner? commandRunner,
    VideoFfmpegExecutableResolver? ffmpegExecutableResolver,
  }) async {
    final normalizedMime = sourceMimeType.trim().toLowerCase();
    if (videoBytes.isEmpty || !normalizedMime.startsWith('video/')) {
      return const VideoPreviewExtractResult(
        posterBytes: null,
        posterMimeType: 'image/jpeg',
        keyframes: <VideoPreviewFrame>[],
      );
    }

    final run = commandRunner ?? Process.run;
    final ffmpegResolver = ffmpegExecutableResolver ??
        debugFfmpegExecutableResolver ??
        _resolveBundledFfmpegExecutablePath;
    final ffmpegPath = await ffmpegResolver();
    if (ffmpegPath == null || ffmpegPath.trim().isEmpty) {
      return const VideoPreviewExtractResult(
        posterBytes: null,
        posterMimeType: 'image/jpeg',
        keyframes: <VideoPreviewFrame>[],
      );
    }

    final safeMaxKeyframes = maxKeyframes.clamp(1, 8);
    final safeInterval = frameIntervalSeconds.clamp(1, 30);
    final normalizedKind = keyframeKind.trim().isEmpty
        ? 'scene'
        : keyframeKind.trim().toLowerCase();

    Directory? tempDir;
    try {
      tempDir =
          await Directory.systemTemp.createTemp('secondloop_video_preview_');
      final sourceExt = _extensionForMimeType(normalizedMime);
      final inputPath = '${tempDir.path}/input.$sourceExt';
      final posterPath = '${tempDir.path}/poster.jpg';
      final scenePattern = '${tempDir.path}/keyframe_scene_%03d.jpg';
      final fpsPattern = '${tempDir.path}/keyframe_fps_%03d.jpg';
      await File(inputPath).writeAsBytes(videoBytes, flush: true);

      final posterArgs = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        inputPath,
        '-vf',
        'select=eq(n\\,0)',
        '-frames:v',
        '1',
        posterPath,
      ];
      final posterResult = await run(ffmpegPath, posterArgs);
      Uint8List? posterBytes;
      if (posterResult.exitCode == 0) {
        final posterFile = File(posterPath);
        if (await posterFile.exists()) {
          final bytes = await posterFile.readAsBytes();
          if (bytes.isNotEmpty) {
            posterBytes = bytes;
          }
        }
      }

      final sceneResult = await _extractFramesWithFilter(
        ffmpegPath: ffmpegPath,
        run: run,
        inputPath: inputPath,
        filter: "select='eq(n\\,0)+gt(scene\\,0.08)'",
        maxFrames: safeMaxKeyframes,
        outputPattern: scenePattern,
        useVariableFrameRateSync: true,
      );
      final sceneFiles = sceneResult
          ? await _listPreviewFrameFiles(tempDir.path,
              prefix: 'keyframe_scene_')
          : const <File>[];

      final remainingFrames = (safeMaxKeyframes - sceneFiles.length).clamp(
        0,
        safeMaxKeyframes,
      );
      final fpsResult = remainingFrames > 0
          ? await _extractFramesWithFilter(
              ffmpegPath: ffmpegPath,
              run: run,
              inputPath: inputPath,
              filter: 'fps=1/$safeInterval',
              maxFrames: remainingFrames,
              outputPattern: fpsPattern,
            )
          : true;

      final keyframes = <VideoPreviewFrame>[];
      if (sceneResult || fpsResult) {
        final fpsFiles = fpsResult
            ? await _listPreviewFrameFiles(tempDir.path,
                prefix: 'keyframe_fps_')
            : const <File>[];
        final seenFrames = <String>{};
        final frameFiles = <File>[...sceneFiles, ...fpsFiles];
        for (final frameFile in frameFiles) {
          final frameBytes = await frameFile.readAsBytes();
          if (frameBytes.isEmpty) continue;
          final frameSignature = base64.encode(frameBytes);
          if (!seenFrames.add(frameSignature)) {
            continue;
          }
          final frameIndex = keyframes.length;
          keyframes.add(
            VideoPreviewFrame(
              index: frameIndex,
              bytes: frameBytes,
              mimeType: 'image/jpeg',
              tMs: frameIndex * safeInterval * 1000,
              kind: normalizedKind,
            ),
          );
        }
      }

      return VideoPreviewExtractResult(
        posterBytes: posterBytes,
        posterMimeType: 'image/jpeg',
        keyframes: List<VideoPreviewFrame>.unmodifiable(keyframes),
      );
    } catch (_) {
      return const VideoPreviewExtractResult(
        posterBytes: null,
        posterMimeType: 'image/jpeg',
        keyframes: <VideoPreviewFrame>[],
      );
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

  static VideoTranscodeResult _fallback(Uint8List bytes, String mimeType) {
    final normalizedMime = mimeType.trim();
    final fallbackMime =
        normalizedMime.isEmpty ? targetMimeType : normalizedMime;
    final data = Uint8List.fromList(bytes);
    return VideoTranscodeResult(
      bytes: data,
      mimeType: fallbackMime,
      didTranscode: false,
      segments: List<VideoTranscodeSegment>.unmodifiable([
        VideoTranscodeSegment(index: 0, bytes: data, mimeType: fallbackMime),
      ]),
    );
  }

  static Future<bool> _extractFramesWithFilter({
    required String ffmpegPath,
    required VideoTranscodeCommandRunner run,
    required String inputPath,
    required String filter,
    required int maxFrames,
    required String outputPattern,
    bool useVariableFrameRateSync = false,
  }) async {
    if (maxFrames <= 0) return true;
    final args = <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      inputPath,
      '-vf',
      filter,
      if (useVariableFrameRateSync) '-vsync',
      if (useVariableFrameRateSync) 'vfr',
      '-frames:v',
      '$maxFrames',
      outputPattern,
    ];
    final result = await run(ffmpegPath, args);
    return result.exitCode == 0;
  }

  static Future<List<File>> _listPreviewFrameFiles(
    String dirPath, {
    String prefix = 'keyframe_',
  }) async {
    final files = <File>[];
    await for (final entity in Directory(dirPath).list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.jpg')) continue;
      files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static Future<List<File>> _listSegmentFiles(String dirPath) async {
    final files = <File>[];
    await for (final entity in Directory(dirPath).list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      if (!name.startsWith('segment_') || !name.endsWith('.mp4')) continue;
      files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static Future<Uint8List?> _reencodeSegmentWithinSize(
    String ffmpegPath,
    VideoTranscodeCommandRunner run,
    String segmentPath,
    String tempDir,
    int maxBytes,
    int segmentIndex,
  ) async {
    const profiles = <({int height, int videoKbps, int audioKbps})>[
      (height: 480, videoKbps: 180, audioKbps: 24),
      (height: 360, videoKbps: 140, audioKbps: 24),
      (height: 360, videoKbps: 100, audioKbps: 16),
      (height: 240, videoKbps: 80, audioKbps: 16),
    ];

    for (var i = 0; i < profiles.length; i++) {
      final profile = profiles[i];
      final outputPath = '$tempDir/segment_${segmentIndex}_retry_$i.mp4';
      final args = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        segmentPath,
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-b:v',
        '${profile.videoKbps}k',
        '-maxrate',
        '${(profile.videoKbps * 1.2).round()}k',
        '-bufsize',
        '${profile.videoKbps * 2}k',
        '-vf',
        'scale=-2:${profile.height}',
        '-c:a',
        'aac',
        '-b:a',
        '${profile.audioKbps}k',
        '-ar',
        '24000',
        '-ac',
        '1',
        '-movflags',
        '+faststart',
        outputPath,
      ];

      final result = await run(ffmpegPath, args);
      if (result.exitCode != 0) continue;

      final output = File(outputPath);
      if (!await output.exists()) continue;

      final bytes = await output.readAsBytes();
      if (bytes.isEmpty) continue;
      if (bytes.lengthInBytes <= maxBytes) {
        return bytes;
      }
    }

    return null;
  }

  static Future<String?> _resolveBundledFfmpegExecutablePath() async {
    final cachedPath = _cachedBundledFfmpegExecutablePath;
    if (cachedPath != null) {
      try {
        if (await File(cachedPath).exists()) return cachedPath;
      } catch (_) {
        // ignore
      }
      _cachedBundledFfmpegExecutablePath = null;
    }

    if (kIsWeb) return null;
    final assetPath = _bundledFfmpegAssetPathForCurrentPlatform();
    if (assetPath == null) return null;

    try {
      final data = await rootBundle.load(assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isEmpty) return null;

      final tempDir =
          Directory('${Directory.systemTemp.path}/secondloop_ffmpeg_bundle');
      await tempDir.create(recursive: true);
      final executableName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final executable = File('${tempDir.path}/$executableName');
      await executable.writeAsBytes(bytes, flush: true);

      if (!Platform.isWindows) {
        final chmodResult =
            await Process.run('chmod', ['755', executable.path]);
        if (chmodResult.exitCode != 0) return null;
      }

      _cachedBundledFfmpegExecutablePath = executable.path;
      return executable.path;
    } catch (_) {
      return null;
    }
  }

  static String? _bundledFfmpegAssetPathForCurrentPlatform() {
    if (kIsWeb) return null;
    if (Platform.isMacOS) return 'assets/bin/ffmpeg/macos/ffmpeg';
    if (Platform.isLinux) return 'assets/bin/ffmpeg/linux/ffmpeg';
    if (Platform.isWindows) return 'assets/bin/ffmpeg/windows/ffmpeg.exe';
    return null;
  }

  static String _extensionForMimeType(String sourceMimeType) {
    switch (sourceMimeType) {
      case 'video/mp4':
        return 'mp4';
      case 'video/x-m4v':
        return 'm4v';
      case 'video/quicktime':
        return 'mov';
      case 'video/webm':
        return 'webm';
      case 'video/x-matroska':
        return 'mkv';
      case 'video/x-msvideo':
        return 'avi';
      default:
        return 'mp4';
    }
  }
}
