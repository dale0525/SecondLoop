import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_pdf_ocr.dart';

const String kSecondLoopVideoManifestMimeType =
    'application/x.secondloop.video+json';
const String kSecondLoopVideoManifestSchemaV1 = 'secondloop.video_manifest.v1';
const String kSecondLoopVideoManifestSchemaV2 = 'secondloop.video_manifest.v2';
const String kSecondLoopVideoManifestSchemaV3 = 'secondloop.video_manifest.v3';

final RegExp _videoManifestSchemaPattern =
    RegExp(r'^secondloop\.video_manifest\.v\d+$');

bool _isSupportedVideoManifestSchema(String schema) {
  final normalized = schema.trim().toLowerCase();
  if (normalized == kSecondLoopVideoManifestSchemaV1) return true;
  if (normalized == kSecondLoopVideoManifestSchemaV2) return true;
  if (normalized == kSecondLoopVideoManifestSchemaV3) return true;
  return _videoManifestSchemaPattern.hasMatch(normalized);
}

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

final class VideoManifestSegmentRef {
  const VideoManifestSegmentRef({
    required this.index,
    required this.sha256,
    required this.mimeType,
  });

  final int index;
  final String sha256;
  final String mimeType;
}

final class VideoManifestPreviewRef {
  const VideoManifestPreviewRef({
    required this.index,
    required this.sha256,
    required this.mimeType,
    required this.tMs,
    required this.kind,
  });

  final int index;
  final String sha256;
  final String mimeType;
  final int tMs;
  final String kind;
}

final class ParsedVideoManifest {
  const ParsedVideoManifest({
    required this.originalSha256,
    required this.originalMimeType,
    required this.segments,
    this.audioSha256,
    this.audioMimeType,
    this.videoKind = 'unknown',
    this.videoKindConfidence = 0.0,
    this.posterSha256,
    this.posterMimeType,
    this.videoProxySha256,
    this.keyframes = const <VideoManifestPreviewRef>[],
    this.videoProxyMaxDurationMs = 60 * 60 * 1000,
    this.videoProxyMaxBytes = 200 * 1024 * 1024,
  });

  final String originalSha256;
  final String originalMimeType;
  final String? audioSha256;
  final String? audioMimeType;
  final String videoKind;
  final double videoKindConfidence;
  final String? posterSha256;
  final String? posterMimeType;
  final String? videoProxySha256;
  final List<VideoManifestPreviewRef> keyframes;
  final int videoProxyMaxDurationMs;
  final int videoProxyMaxBytes;
  final List<VideoManifestSegmentRef> segments;
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
    final map = Map<dynamic, dynamic>.from(payload);

    String readMapNonEmptyField(
      Map<dynamic, dynamic> source,
      List<String> keys,
    ) {
      for (final key in keys) {
        final raw = source[key];
        if (raw == null) continue;
        final normalized = raw.toString().trim();
        if (normalized.isEmpty) continue;
        if (normalized.toLowerCase() == 'null') continue;
        return normalized;
      }
      return '';
    }

    Object? readMapRawField(
      Map<dynamic, dynamic> source,
      List<String> keys,
    ) {
      for (final key in keys) {
        if (!source.containsKey(key)) continue;
        return source[key];
      }
      return null;
    }

    String readNonEmptyField(
      List<String> keys, {
      String fallbackValue = '',
    }) {
      final value = readMapNonEmptyField(map, keys);
      if (value.isNotEmpty) return value;
      return fallbackValue.trim();
    }

    String? readOptionalNonEmptyField(List<String> keys) {
      final value = readMapNonEmptyField(map, keys);
      if (value.isEmpty) return null;
      return value;
    }

    final schema = readNonEmptyField(const <String>['schema']);
    if (!_isSupportedVideoManifestSchema(schema)) return null;

    int readIntField(Object? raw, {int fallback = 0}) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
      return fallback;
    }

    double readDoubleField(Object? raw, {double fallback = 0.0}) {
      if (raw is double) return raw;
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
      return fallback;
    }

    List<VideoManifestSegmentRef> readSegments() {
      final raw = readMapRawField(
        map,
        const <String>['video_segments', 'videoSegments'],
      );
      if (raw is! List) return const <VideoManifestSegmentRef>[];
      final refs = <VideoManifestSegmentRef>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final itemMap = Map<dynamic, dynamic>.from(item);
        final sha256 = readMapNonEmptyField(itemMap, const <String>['sha256']);
        final mimeType = readMapNonEmptyField(
            itemMap, const <String>['mime_type', 'mimeType']);
        if (sha256.isEmpty || mimeType.isEmpty) continue;

        var index = refs.length;
        final rawIndex = readMapRawField(itemMap, const <String>['index']);
        if (rawIndex is int) {
          index = rawIndex;
        } else if (rawIndex is num) {
          index = rawIndex.toInt();
        } else if (rawIndex is String) {
          final parsedIndex = int.tryParse(rawIndex.trim());
          if (parsedIndex != null) {
            index = parsedIndex;
          }
        }

        refs.add(
          VideoManifestSegmentRef(
            index: index,
            sha256: sha256,
            mimeType: mimeType,
          ),
        );
      }
      refs.sort((a, b) {
        final byIndex = a.index.compareTo(b.index);
        if (byIndex != 0) return byIndex;
        return a.sha256.compareTo(b.sha256);
      });
      return List<VideoManifestSegmentRef>.unmodifiable(refs);
    }

    final segments = readSegments();
    String firstSegmentField(String key) {
      if (segments.isEmpty) return '';
      return switch (key) {
        'sha256' => segments.first.sha256,
        'mime_type' => segments.first.mimeType,
        _ => '',
      };
    }

    final originalSha256 = readNonEmptyField(
      const <String>[
        'video_sha256',
        'videoSha256',
        'original_sha256',
        'originalSha256',
      ],
      fallbackValue: firstSegmentField('sha256'),
    );
    final originalMimeType = readNonEmptyField(
      const <String>[
        'video_mime_type',
        'videoMimeType',
        'original_mime_type',
        'originalMimeType',
      ],
      fallbackValue: firstSegmentField('mime_type'),
    );
    if (originalSha256.isEmpty || originalMimeType.isEmpty) return null;

    final audioSha256 = readOptionalNonEmptyField(
      const <String>['audio_sha256', 'audioSha256'],
    );
    final audioMimeType = readOptionalNonEmptyField(
      const <String>['audio_mime_type', 'audioMimeType'],
    );

    final rawVideoKind =
        readNonEmptyField(const <String>['video_kind', 'videoKind']);
    final normalizedVideoKind = switch (rawVideoKind.toLowerCase()) {
      'screen_recording' => 'screen_recording',
      'vlog' => 'vlog',
      _ => 'unknown',
    };
    final normalizedVideoKindConfidence = readDoubleField(
      readMapRawField(
        map,
        const <String>['video_kind_confidence', 'videoKindConfidence'],
      ),
      fallback: 0.0,
    ).clamp(0.0, 1.0).toDouble();

    List<VideoManifestPreviewRef> readKeyframes() {
      final raw = readMapRawField(map, const <String>['keyframes']);
      if (raw is! List) return const <VideoManifestPreviewRef>[];
      final refs = <VideoManifestPreviewRef>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final itemMap = Map<dynamic, dynamic>.from(item);
        final sha256 = readMapNonEmptyField(itemMap, const <String>['sha256']);
        final mimeType = readMapNonEmptyField(
            itemMap, const <String>['mime_type', 'mimeType']);
        if (sha256.isEmpty || mimeType.isEmpty) continue;
        final rawKind = readMapNonEmptyField(itemMap, const <String>['kind']);
        refs.add(
          VideoManifestPreviewRef(
            index: readIntField(
              readMapRawField(itemMap, const <String>['index']),
              fallback: refs.length,
            ),
            sha256: sha256,
            mimeType: mimeType,
            tMs: readIntField(
              readMapRawField(itemMap, const <String>['t_ms', 'tMs']),
            ),
            kind: rawKind.isEmpty ? 'scene' : rawKind.toLowerCase(),
          ),
        );
      }
      refs.sort((a, b) => a.index.compareTo(b.index));
      return List<VideoManifestPreviewRef>.unmodifiable(refs);
    }

    final normalizedKeyframes = readKeyframes();
    final normalizedPosterSha256 = readOptionalNonEmptyField(
      const <String>['poster_sha256', 'posterSha256'],
    );
    final normalizedPosterMimeType = readOptionalNonEmptyField(
      const <String>['poster_mime_type', 'posterMimeType'],
    );
    final normalizedVideoProxySha256 = readOptionalNonEmptyField(const <String>[
          'video_proxy_sha256',
          'videoProxySha256',
          'video_sha256',
          'videoSha256',
          'original_sha256',
          'originalSha256',
        ]) ??
        originalSha256;
    final normalizedVideoProxyMaxDurationMs = readIntField(
      readMapRawField(
        map,
        const <String>[
          'video_proxy_max_duration_ms',
          'videoProxyMaxDurationMs'
        ],
      ),
      fallback: 60 * 60 * 1000,
    );
    final normalizedVideoProxyMaxBytes = readIntField(
      readMapRawField(
        map,
        const <String>['video_proxy_max_bytes', 'videoProxyMaxBytes'],
      ),
      fallback: 200 * 1024 * 1024,
    );

    final normalizedSegments = segments.isNotEmpty
        ? segments
        : List<VideoManifestSegmentRef>.unmodifiable([
            VideoManifestSegmentRef(
              index: 0,
              sha256: originalSha256,
              mimeType: originalMimeType,
            ),
          ]);

    return ParsedVideoManifest(
      originalSha256: originalSha256,
      originalMimeType: originalMimeType,
      audioSha256: audioSha256,
      audioMimeType: audioMimeType,
      videoKind: normalizedVideoKind,
      videoKindConfidence: normalizedVideoKindConfidence,
      posterSha256: normalizedPosterSha256,
      posterMimeType: normalizedPosterMimeType,
      videoProxySha256: normalizedVideoProxySha256,
      keyframes: normalizedKeyframes,
      videoProxyMaxDurationMs: normalizedVideoProxyMaxDurationMs,
      videoProxyMaxBytes: normalizedVideoProxyMaxBytes,
      segments: normalizedSegments,
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
