import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_pdf_ocr.dart';

const String kSecondLoopVideoManifestMimeType =
    'application/x.secondloop.video+json';
const String kSecondLoopVideoManifestSchema = 'secondloop.video_manifest.v1';

const int _kVideoOcrMaxFullBytes = 256 * 1024;
const int _kVideoOcrMaxExcerptBytes = 8 * 1024;

typedef VideoOcrCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef VideoOcrFfmpegResolver = Future<String?> Function();

typedef VideoOcrImageRunner = Future<PlatformPdfOcrResult?> Function(
  Uint8List bytes, {
  required String languageHints,
});

final class ParsedVideoManifest {
  const ParsedVideoManifest({
    required this.originalSha256,
    required this.originalMimeType,
  });

  final String originalSha256;
  final String originalMimeType;
}

final class VideoKeyframeOcrResult {
  const VideoKeyframeOcrResult({
    required this.fullText,
    required this.excerpt,
    required this.engine,
    required this.isTruncated,
    required this.frameCount,
    required this.processedFrames,
  });

  final String fullText;
  final String excerpt;
  final String engine;
  final bool isTruncated;
  final int frameCount;
  final int processedFrames;
}

ParsedVideoManifest? parseVideoManifestPayload(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    final decoded = String.fromCharCodes(bytes);
    final payload = jsonDecode(decoded);
    if (payload is! Map) return null;

    final schema = payload['schema']?.toString().trim() ?? '';
    if (schema != kSecondLoopVideoManifestSchema) return null;

    final originalSha256 = payload['original_sha256']?.toString().trim() ?? '';
    final originalMimeType =
        payload['original_mime_type']?.toString().trim() ?? '';
    if (originalSha256.isEmpty || originalMimeType.isEmpty) return null;

    return ParsedVideoManifest(
      originalSha256: originalSha256,
      originalMimeType: originalMimeType,
    );
  } catch (_) {
    return null;
  }
}

final class VideoKeyframeOcrWorker {
  static Future<VideoKeyframeOcrResult?> runOnVideoBytes(
    Uint8List videoBytes, {
    required String sourceMimeType,
    required int maxFrames,
    required int frameIntervalSeconds,
    required String languageHints,
    VideoOcrCommandRunner? commandRunner,
    VideoOcrFfmpegResolver? ffmpegExecutableResolver,
    VideoOcrImageRunner? ocrImageFn,
  }) async {
    if (videoBytes.isEmpty) return null;
    final normalizedMime = sourceMimeType.trim().toLowerCase();
    if (!normalizedMime.startsWith('video/')) return null;

    final ffmpegResolver =
        ffmpegExecutableResolver ?? _resolveBundledFfmpegExecutablePath;
    final ffmpegPath = await ffmpegResolver();
    if (ffmpegPath == null || ffmpegPath.trim().isEmpty) return null;

    final run = commandRunner ?? Process.run;
    final imageOcr = ocrImageFn ?? PlatformPdfOcr.tryOcrImageBytes;
    final safeMaxFrames = maxFrames.clamp(1, 120);
    final safeInterval = frameIntervalSeconds.clamp(1, 60);
    final hints =
        languageHints.trim().isEmpty ? 'device_plus_en' : languageHints.trim();

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('secondloop_video_ocr_');
      final sourceExt = _extensionForMimeType(normalizedMime);
      final inputPath = '${tempDir.path}/input.$sourceExt';
      final framesPattern = '${tempDir.path}/frame_%04d.jpg';
      await File(inputPath).writeAsBytes(videoBytes, flush: true);

      final args = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        inputPath,
        '-vf',
        'fps=1/$safeInterval',
        '-frames:v',
        '$safeMaxFrames',
        framesPattern,
      ];
      final ffmpegResult = await run(ffmpegPath, args);
      if (ffmpegResult.exitCode != 0) return null;

      final frames = await _listExtractedFrames(tempDir.path);
      if (frames.isEmpty) return null;

      var processedFrames = 0;
      final blocks = <String>[];
      final engines = <String>[];
      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i];
        final frameBytes = await frame.readAsBytes();
        if (frameBytes.isEmpty) continue;
        final ocr = await imageOcr(frameBytes, languageHints: hints);
        if (ocr == null) continue;

        processedFrames += 1;
        final text = ocr.fullText.trim();
        final engine = ocr.engine.trim();
        if (engine.isNotEmpty) {
          engines.add(engine);
        }
        if (text.isEmpty) continue;
        blocks.add('[frame ${i + 1}]\n$text');
      }

      final full = blocks.join('\n\n').trim();
      final fullTruncated = _truncateUtf8(full, _kVideoOcrMaxFullBytes);
      final excerpt = _truncateUtf8(fullTruncated, _kVideoOcrMaxExcerptBytes);
      final engine = _dominantEngine(engines);
      if (engine.isEmpty) return null;

      final isTruncated =
          fullTruncated != full || processedFrames < frames.length;

      return VideoKeyframeOcrResult(
        fullText: fullTruncated,
        excerpt: excerpt,
        engine: engine,
        isTruncated: isTruncated,
        frameCount: frames.length,
        processedFrames: processedFrames,
      );
    } catch (_) {
      return null;
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
}

Future<List<File>> _listExtractedFrames(String dirPath) async {
  final files = <File>[];
  await for (final entity in Directory(dirPath).list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path
        : entity.uri.pathSegments.last;
    if (!name.startsWith('frame_') || !name.endsWith('.jpg')) continue;
    files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _truncateUtf8(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  if (maxBytes <= 0) return '';
  var end = maxBytes;
  while (end > 0 && (bytes[end - 1] & 0xC0) == 0x80) {
    end -= 1;
  }
  if (end <= 0) return '';
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}

String _dominantEngine(List<String> engines) {
  if (engines.isEmpty) return '';
  final counts = <String, int>{};
  for (final engine in engines) {
    counts.update(engine, (value) => value + 1, ifAbsent: () => 1);
  }
  String winner = '';
  var bestCount = -1;
  counts.forEach((engine, count) {
    if (count > bestCount) {
      winner = engine;
      bestCount = count;
    }
  });
  return winner;
}

String _extensionForMimeType(String sourceMimeType) {
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

String? _cachedBundledFfmpegExecutablePath;

Future<String?> _resolveBundledFfmpegExecutablePath() async {
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
      final chmodResult = await Process.run('chmod', ['755', executable.path]);
      if (chmodResult.exitCode != 0) return null;
    }

    _cachedBundledFfmpegExecutablePath = executable.path;
    return executable.path;
  } catch (_) {
    return null;
  }
}

String? _bundledFfmpegAssetPathForCurrentPlatform() {
  if (kIsWeb) return null;
  if (Platform.isMacOS) return 'assets/bin/ffmpeg/macos/ffmpeg';
  if (Platform.isLinux) return 'assets/bin/ffmpeg/linux/ffmpeg';
  if (Platform.isWindows) return 'assets/bin/ffmpeg/windows/ffmpeg.exe';
  return null;
}
