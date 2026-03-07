import 'dart:typed_data';

Future<String?> resolveBundledFfmpegExecutablePath() async => null;

Future<String?> resolveBundledFfmpegExecutablePathForTest({
  required bool isWeb,
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required Future<Uint8List?> Function(String assetPath) loadAssetBytes,
  required Future<String> Function() appDirProvider,
  required Future<String?> Function() systemPathResolver,
}) async {
  return null;
}

String bundledFfmpegPayloadIdForTest(List<int> bytes) => '';
