import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/media/ffmpeg_executable_resolver.dart';

void main() {
  group('resolveBundledFfmpegExecutablePathForTest', () {
    test('returns cached executable when already extracted', () async {
      final appDir =
          await Directory.systemTemp.createTemp('secondloop_ffmpeg_');
      addTearDown(() async {
        if (appDir.existsSync()) {
          await appDir.delete(recursive: true);
        }
      });

      final zipBytes = _buildZip({
        'ffmpeg.exe': Uint8List.fromList([1, 2, 3])
      });
      final payloadId = bundledFfmpegPayloadIdForTest(zipBytes);
      final cachedExe = File(
        '${appDir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}ffmpeg${Platform.pathSeparator}$payloadId${Platform.pathSeparator}ffmpeg.exe',
      );
      await cachedExe.parent.create(recursive: true);
      await cachedExe.writeAsBytes(const <int>[9, 9, 9], flush: true);

      final resolved = await resolveBundledFfmpegExecutablePathForTest(
        isWeb: false,
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        loadAssetBytes: (_) async => zipBytes,
        appDirProvider: () async => appDir.path,
        systemPathResolver: () async => null,
      );

      expect(resolved, cachedExe.path);
      expect(await cachedExe.readAsBytes(), const <int>[9, 9, 9]);
    });

    test('extracts bundled windows ffmpeg zip into cache when missing',
        () async {
      final appDir =
          await Directory.systemTemp.createTemp('secondloop_ffmpeg_');
      addTearDown(() async {
        if (appDir.existsSync()) {
          await appDir.delete(recursive: true);
        }
      });

      final zipBytes = _buildZip({
        'ffmpeg.exe': Uint8List.fromList(<int>[7, 8, 9, 10]),
      });

      final resolved = await resolveBundledFfmpegExecutablePathForTest(
        isWeb: false,
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        loadAssetBytes: (_) async => zipBytes,
        appDirProvider: () async => appDir.path,
        systemPathResolver: () async => null,
      );

      expect(resolved, isNotNull);
      final extractedFile = File(resolved!);
      expect(await extractedFile.exists(), isTrue);
      expect(await extractedFile.readAsBytes(), <int>[7, 8, 9, 10]);
      expect(resolved, endsWith('ffmpeg.exe'));
    });

    test('falls back to system ffmpeg when bundled asset is unavailable',
        () async {
      final resolved = await resolveBundledFfmpegExecutablePathForTest(
        isWeb: false,
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        loadAssetBytes: (_) async => null,
        appDirProvider: () async => Directory.systemTemp.path,
        systemPathResolver: () async => r'C:\ffmpeg\bin\ffmpeg.exe',
      );

      expect(resolved, r'C:\ffmpeg\bin\ffmpeg.exe');
    });

    test('returns null when bundled asset and system ffmpeg are unavailable',
        () async {
      final resolved = await resolveBundledFfmpegExecutablePathForTest(
        isWeb: false,
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        loadAssetBytes: (_) async => null,
        appDirProvider: () async => Directory.systemTemp.path,
        systemPathResolver: () async => null,
      );

      expect(resolved, isNull);
    });
  });
}

Uint8List _buildZip(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
