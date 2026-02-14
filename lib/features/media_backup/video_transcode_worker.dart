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
