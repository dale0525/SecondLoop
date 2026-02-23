import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class AudioTranscodeResult {
  const AudioTranscodeResult({
    required this.bytes,
    required this.mimeType,
    required this.didTranscode,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool didTranscode;
}

typedef AudioTranscodeFn = Future<Uint8List> Function(
  Uint8List originalBytes, {
  required String sourceMimeType,
  required int targetSampleRateHz,
  required int targetBitrateKbps,
  required bool mono,
});

typedef AudioTranscodeCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef AudioNativeTranscodeFn = Future<Uint8List> Function(
  Uint8List originalBytes, {
  required String sourceMimeType,
  required int targetSampleRateHz,
  required int targetBitrateKbps,
  required bool mono,
});

typedef AudioNativeDecodeToWavFn = Future<Uint8List> Function(
  Uint8List originalBytes, {
  required String sourceMimeType,
  int? maxDecodedWavBytes,
});

typedef AudioFfmpegExecutableResolver = Future<String?> Function();

final class AudioTranscodeWorker {
  static const String targetMimeType = 'audio/mp4';
  static const int _targetSampleRateHz = 24000;
  static const int _targetBitrateKbps = 48;
  static const int _maxLocalTranscodeAttempts = 3;
  static const Duration _nativeTranscodeTimeout = Duration(seconds: 30);
  static const MethodChannel _audioTranscodeChannel =
      MethodChannel('secondloop/audio_transcode');
  static String? _cachedBundledFfmpegExecutablePath;
  @visibleForTesting
  static AudioTranscodeFn? debugTranscodeOverride;
  @visibleForTesting
  static AudioNativeTranscodeFn? debugNativeTranscodeOverride;
  @visibleForTesting
  static AudioNativeDecodeToWavFn? debugNativeDecodeToWavOverride;
  @visibleForTesting
  static bool? debugUseNativeTranscodeOverride;
  @visibleForTesting
  static bool? debugPreferVideoManifestWavProxyOverride;
  @visibleForTesting
  static AudioFfmpegExecutableResolver? debugFfmpegExecutableResolver;

  @visibleForTesting
  static String debugExtensionForMimeType(String sourceMimeType) {
    return _extensionForMimeType(sourceMimeType);
  }

  static Future<AudioTranscodeResult> transcodeVideoAudioForManifest(
    Uint8List originalBytes, {
    required String originalMimeType,
    required Uint8List primarySegmentBytes,
    required String primarySegmentMimeType,
    AudioTranscodeFn? transcode,
    AudioTranscodeCommandRunner? commandRunner,
    AudioNativeTranscodeFn? nativeTranscode,
    AudioNativeDecodeToWavFn? nativeDecodeToWav,
    AudioFfmpegExecutableResolver? ffmpegExecutableResolver,
  }) async {
    final normalizedOriginalMime = originalMimeType.trim().toLowerCase();
    final normalizedPrimaryMime = primarySegmentMimeType.trim().toLowerCase();
    final shouldRetryWithOriginal =
        !identical(originalBytes, primarySegmentBytes) ||
            normalizedOriginalMime != normalizedPrimaryMime;

    if (_shouldPreferVideoManifestWavProxy()) {
      final primaryDirectWav = await _fallbackExtractAudioWavProxy(
        primarySegmentBytes,
        sourceMimeType: primarySegmentMimeType,
        nativeDecodeToWav: nativeDecodeToWav,
      );
      if (primaryDirectWav.isNotEmpty) {
        return AudioTranscodeResult(
          bytes: primaryDirectWav,
          mimeType: 'audio/wav',
          didTranscode: true,
        );
      }

      if (shouldRetryWithOriginal) {
        final originalDirectWav = await _fallbackExtractAudioWavProxy(
          originalBytes,
          sourceMimeType: originalMimeType,
          nativeDecodeToWav: nativeDecodeToWav,
          maxDecodedWavBytes: 0,
        );
        if (originalDirectWav.isNotEmpty) {
          return AudioTranscodeResult(
            bytes: originalDirectWav,
            mimeType: 'audio/wav',
            didTranscode: true,
          );
        }
      }
    }

    final primaryResult = await transcodeToM4aProxy(
      primarySegmentBytes,
      sourceMimeType: primarySegmentMimeType,
      transcode: transcode,
      commandRunner: commandRunner,
      nativeTranscode: nativeTranscode,
      nativeDecodeToWav: nativeDecodeToWav,
      ffmpegExecutableResolver: ffmpegExecutableResolver,
    );
    if (await _isUsableVideoManifestAudioProxy(
      primaryResult,
      nativeDecodeToWav: nativeDecodeToWav,
    )) {
      return primaryResult;
    }

    final primaryWavFallback = await _fallbackExtractAudioWavProxy(
      primarySegmentBytes,
      sourceMimeType: primarySegmentMimeType,
      nativeDecodeToWav: nativeDecodeToWav,
    );
    if (primaryWavFallback.isNotEmpty) {
      return AudioTranscodeResult(
        bytes: primaryWavFallback,
        mimeType: 'audio/wav',
        didTranscode: true,
      );
    }

    if (!shouldRetryWithOriginal) {
      return primaryResult;
    }

    final originalResult = await transcodeToM4aProxy(
      originalBytes,
      sourceMimeType: originalMimeType,
      transcode: transcode,
      commandRunner: commandRunner,
      nativeTranscode: nativeTranscode,
      nativeDecodeToWav: nativeDecodeToWav,
      ffmpegExecutableResolver: ffmpegExecutableResolver,
    );
    if (await _isUsableVideoManifestAudioProxy(
      originalResult,
      nativeDecodeToWav: nativeDecodeToWav,
    )) {
      return originalResult;
    }

    final originalWavFallback = await _fallbackExtractAudioWavProxy(
      originalBytes,
      sourceMimeType: originalMimeType,
      nativeDecodeToWav: nativeDecodeToWav,
      maxDecodedWavBytes: 0,
    );
    if (originalWavFallback.isNotEmpty) {
      return AudioTranscodeResult(
        bytes: originalWavFallback,
        mimeType: 'audio/wav',
        didTranscode: true,
      );
    }

    return primaryResult;
  }

  static bool _isUsableAudioProxy(AudioTranscodeResult result) {
    final normalizedMimeType = result.mimeType.trim().toLowerCase();
    return result.didTranscode &&
        result.bytes.isNotEmpty &&
        normalizedMimeType.startsWith('audio/');
  }

  static Future<bool> _isUsableVideoManifestAudioProxy(
    AudioTranscodeResult result, {
    AudioNativeDecodeToWavFn? nativeDecodeToWav,
  }) async {
    if (!_isUsableAudioProxy(result)) {
      return false;
    }

    final normalizedMimeType = result.mimeType.trim().toLowerCase();
    if (normalizedMimeType == 'audio/wav' ||
        normalizedMimeType == 'audio/wave' ||
        normalizedMimeType == 'audio/x-wav') {
      return true;
    }

    if (!_shouldValidateVideoManifestAudioProxyDecode()) {
      return true;
    }

    final decodeFn = nativeDecodeToWav ??
        debugNativeDecodeToWavOverride ??
        (
          bytes, {
          required sourceMimeType,
          maxDecodedWavBytes,
        }) {
          return _decodeToWavWithNativePlatformApi(
            bytes,
            sourceMimeType: sourceMimeType,
            maxDecodedWavBytes: maxDecodedWavBytes,
          );
        };

    try {
      final wavBytes = await decodeFn(
        result.bytes,
        sourceMimeType: result.mimeType,
      );
      return wavBytes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool _shouldValidateVideoManifestAudioProxyDecode() {
    final forced = debugUseNativeTranscodeOverride;
    if (forced != null) return forced;
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static bool _shouldPreferVideoManifestWavProxy() {
    final forced = debugPreferVideoManifestWavProxyOverride;
    if (forced != null) return forced;
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<AudioTranscodeResult> transcodeToM4aProxy(
    Uint8List originalBytes, {
    required String sourceMimeType,
    AudioTranscodeFn? transcode,
    AudioTranscodeCommandRunner? commandRunner,
    AudioNativeTranscodeFn? nativeTranscode,
    AudioNativeDecodeToWavFn? nativeDecodeToWav,
    AudioFfmpegExecutableResolver? ffmpegExecutableResolver,
  }) async {
    final normalized = sourceMimeType.trim().toLowerCase();
    final canonicalSourceMimeType = _canonicalizeAudioMimeType(sourceMimeType);
    final canTranscode =
        normalized.startsWith('audio/') || normalized.startsWith('video/');
    if (!canTranscode) {
      return AudioTranscodeResult(
        bytes: originalBytes,
        mimeType: sourceMimeType,
        didTranscode: false,
      );
    }

    if (canonicalSourceMimeType == targetMimeType) {
      return AudioTranscodeResult(
        bytes: originalBytes,
        mimeType: targetMimeType,
        didTranscode: false,
      );
    }

    final fn = transcode ??
        debugTranscodeOverride ??
        (
          bytes, {
          required sourceMimeType,
          required targetSampleRateHz,
          required targetBitrateKbps,
          required mono,
        }) {
          if (_shouldUseNativeTranscode()) {
            final nativeFn = nativeTranscode ??
                debugNativeTranscodeOverride ??
                (
                  originalBytes, {
                  required sourceMimeType,
                  required targetSampleRateHz,
                  required targetBitrateKbps,
                  required mono,
                }) {
                  return _transcodeWithNativePlatformApi(
                    originalBytes,
                    sourceMimeType: sourceMimeType,
                    targetSampleRateHz: targetSampleRateHz,
                    targetBitrateKbps: targetBitrateKbps,
                    mono: mono,
                  );
                };
            return nativeFn(
              bytes,
              sourceMimeType: sourceMimeType,
              targetSampleRateHz: targetSampleRateHz,
              targetBitrateKbps: targetBitrateKbps,
              mono: mono,
            );
          }

          return _transcodeWithFfmpeg(
            bytes,
            sourceMimeType: sourceMimeType,
            targetSampleRateHz: targetSampleRateHz,
            targetBitrateKbps: targetBitrateKbps,
            mono: mono,
            commandRunner: commandRunner,
            ffmpegExecutableResolver: ffmpegExecutableResolver,
          );
        };
    final transcodedBytes = await _transcodeWithRetries(
      fn,
      originalBytes,
      sourceMimeType,
    );
    if (transcodedBytes.isNotEmpty) {
      return AudioTranscodeResult(
        bytes: transcodedBytes,
        mimeType: targetMimeType,
        didTranscode: true,
      );
    }

    final wavFallbackBytes = await _fallbackExtractAudioWavProxy(
      originalBytes,
      sourceMimeType: sourceMimeType,
      nativeDecodeToWav: nativeDecodeToWav,
    );
    if (wavFallbackBytes.isNotEmpty) {
      return AudioTranscodeResult(
        bytes: wavFallbackBytes,
        mimeType: 'audio/wav',
        didTranscode: true,
      );
    }

    return AudioTranscodeResult(
      bytes: originalBytes,
      mimeType: canonicalSourceMimeType,
      didTranscode: false,
    );
  }

  static Future<Uint8List> _transcodeWithRetries(
    AudioTranscodeFn transcode,
    Uint8List originalBytes,
    String sourceMimeType,
  ) async {
    for (var attempt = 1; attempt <= _maxLocalTranscodeAttempts; attempt++) {
      try {
        final bytes = await transcode(
          originalBytes,
          sourceMimeType: sourceMimeType,
          targetSampleRateHz: _targetSampleRateHz,
          targetBitrateKbps: _targetBitrateKbps,
          mono: true,
        );
        if (bytes.isNotEmpty) return bytes;
      } on TimeoutException {
        break;
      } catch (_) {
        // Ignore and retry below.
      }
    }
    return Uint8List(0);
  }

  static bool _shouldUseNativeTranscode() {
    final forced = debugUseNativeTranscodeOverride;
    if (forced != null) return forced;
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  static Future<Uint8List> _fallbackExtractAudioWavProxy(
    Uint8List originalBytes, {
    required String sourceMimeType,
    AudioNativeDecodeToWavFn? nativeDecodeToWav,
    int? maxDecodedWavBytes,
  }) async {
    final normalizedMimeType = sourceMimeType.trim().toLowerCase();
    final isVideoSource = normalizedMimeType.startsWith('video/');
    if (!isVideoSource || !_shouldUseNativeTranscode()) {
      return Uint8List(0);
    }

    final decodeFn = nativeDecodeToWav ??
        debugNativeDecodeToWavOverride ??
        (
          bytes, {
          required sourceMimeType,
          maxDecodedWavBytes,
        }) {
          return _decodeToWavWithNativePlatformApi(
            bytes,
            sourceMimeType: sourceMimeType,
            maxDecodedWavBytes: maxDecodedWavBytes,
          );
        };

    try {
      return await decodeFn(
        originalBytes,
        sourceMimeType: sourceMimeType,
        maxDecodedWavBytes: maxDecodedWavBytes,
      );
    } catch (_) {
      return Uint8List(0);
    }
  }

  static String _canonicalizeAudioMimeType(String sourceMimeType) {
    final normalized = sourceMimeType.trim().toLowerCase();
    switch (normalized) {
      case 'audio/x-m4a':
      case 'audio/m4a':
        return targetMimeType;
      case 'audio/x-wav':
      case 'audio/wave':
        return 'audio/wav';
      case 'audio/x-mp3':
      case 'audio/mp3':
        return 'audio/mpeg';
      case 'audio/x-ogg':
      case 'application/ogg':
        return 'audio/ogg';
      default:
        return normalized;
    }
  }

  static Future<Uint8List> _transcodeWithFfmpeg(
    Uint8List originalBytes, {
    required String sourceMimeType,
    required int targetSampleRateHz,
    required int targetBitrateKbps,
    required bool mono,
    AudioTranscodeCommandRunner? commandRunner,
    AudioFfmpegExecutableResolver? ffmpegExecutableResolver,
  }) async {
    Directory? tempDir;
    try {
      final executableResolver = ffmpegExecutableResolver ??
          debugFfmpegExecutableResolver ??
          _resolveBundledFfmpegExecutablePath;
      final executablePath = await executableResolver();
      if (executablePath == null || executablePath.trim().isEmpty) {
        return Uint8List(0);
      }

      tempDir = await Directory.systemTemp.createTemp('secondloop_audio_');
      final sourceExt = _extensionForMimeType(sourceMimeType);
      final inputPath = '${tempDir.path}/input.$sourceExt';
      final outputPath = '${tempDir.path}/output.m4a';
      await File(inputPath).writeAsBytes(originalBytes, flush: true);

      final args = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        inputPath,
        '-vn',
        if (mono) ...['-ac', '1'],
        '-ar',
        '$targetSampleRateHz',
        '-b:a',
        '${targetBitrateKbps}k',
        '-c:a',
        'aac',
        '-movflags',
        '+faststart',
        outputPath,
      ];

      final runner = commandRunner ??
          ((executable, arguments) => Process.run(executable, arguments));
      final result = await runner(executablePath, args);
      if (result.exitCode != 0) return Uint8List(0);

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) return Uint8List(0);
      final out = await outputFile.readAsBytes();
      if (out.isEmpty) return Uint8List(0);
      return out;
    } catch (_) {
      return Uint8List(0);
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

  static Future<Uint8List> _transcodeWithNativePlatformApi(
    Uint8List originalBytes, {
    required String sourceMimeType,
    required int targetSampleRateHz,
    required int targetBitrateKbps,
    required bool mono,
  }) async {
    if (kIsWeb) return Uint8List(0);
    if (!(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      return Uint8List(0);
    }

    Directory? tempDir;
    try {
      tempDir =
          await Directory.systemTemp.createTemp('secondloop_audio_native_');
      final sourceExt = _extensionForMimeType(sourceMimeType);
      final inputPath = '${tempDir.path}/input.$sourceExt';
      final outputPath = '${tempDir.path}/output.m4a';
      await File(inputPath).writeAsBytes(originalBytes, flush: true);

      final ok =
          await _audioTranscodeChannel.invokeMethod<bool>('transcodeToM4a', {
        'input_path': inputPath,
        'output_path': outputPath,
        'sample_rate_hz': targetSampleRateHz,
        'bitrate_kbps': targetBitrateKbps,
        'mono': mono,
      }).timeout(_nativeTranscodeTimeout);
      if (ok != true) return Uint8List(0);

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) return Uint8List(0);
      final out = await outputFile.readAsBytes();
      if (out.isEmpty) return Uint8List(0);
      return out;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return Uint8List(0);
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // ignore
        }
      }
    }
  }

  static Future<Uint8List> _decodeToWavWithNativePlatformApi(
    Uint8List originalBytes, {
    required String sourceMimeType,
    int? maxDecodedWavBytes,
  }) async {
    if (kIsWeb) return Uint8List(0);
    if (!(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      return Uint8List(0);
    }

    Directory? tempDir;
    try {
      tempDir =
          await Directory.systemTemp.createTemp('secondloop_audio_native_');
      final sourceExt = _extensionForMimeType(sourceMimeType);
      final inputPath = '${tempDir.path}/input.$sourceExt';
      final outputPath = '${tempDir.path}/output.wav';
      await File(inputPath).writeAsBytes(originalBytes, flush: true);

      final decodeRequest = <String, Object?>{
        'input_path': inputPath,
        'output_path': outputPath,
        if (maxDecodedWavBytes != null)
          'max_decoded_wav_bytes': maxDecodedWavBytes,
      };
      final ok = await _audioTranscodeChannel
          .invokeMethod<bool>('decodeToWavPcm16Mono16k', decodeRequest)
          .timeout(_nativeTranscodeTimeout);
      if (ok != true) return Uint8List(0);

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) return Uint8List(0);
      final out = await outputFile.readAsBytes();
      if (out.isEmpty) return Uint8List(0);
      return out;
    } on TimeoutException {
      return Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // ignore
        }
      }
    }
  }

  static String _extensionForMimeType(String sourceMimeType) {
    final normalized = sourceMimeType.trim().toLowerCase();
    switch (normalized) {
      case 'audio/mp4':
      case 'audio/m4a':
      case 'audio/x-m4a':
        return 'm4a';
      case 'video/mp4':
        return 'mp4';
      case 'audio/mpeg':
      case 'video/mpeg':
        return 'mp3';
      case 'audio/wav':
      case 'audio/wave':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/flac':
        return 'flac';
      case 'audio/ogg':
      case 'audio/opus':
      case 'video/ogg':
        return 'ogg';
      case 'audio/aac':
        return 'aac';
      case 'video/quicktime':
        return 'mov';
      case 'video/x-matroska':
        return 'mkv';
      default:
        return normalized.startsWith('video/') ? 'mp4' : 'bin';
    }
  }
}
