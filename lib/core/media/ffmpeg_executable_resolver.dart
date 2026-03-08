import 'dart:typed_data';

import 'ffmpeg_executable_resolver_stub.dart'
    if (dart.library.io) 'ffmpeg_executable_resolver_io.dart' as impl;

Future<String?> resolveBundledFfmpegExecutablePath() {
  return impl.resolveBundledFfmpegExecutablePath();
}

Future<String?> resolveBundledFfmpegExecutablePathForTest({
  required bool isWeb,
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required Future<Uint8List?> Function(String assetPath) loadAssetBytes,
  required Future<String> Function() appDirProvider,
  required Future<String?> Function() systemPathResolver,
}) {
  return impl.resolveBundledFfmpegExecutablePathForTest(
    isWeb: isWeb,
    isWindows: isWindows,
    isMacOS: isMacOS,
    isLinux: isLinux,
    loadAssetBytes: loadAssetBytes,
    appDirProvider: appDirProvider,
    systemPathResolver: systemPathResolver,
  );
}

String bundledFfmpegPayloadIdForTest(List<int> bytes) {
  return impl.bundledFfmpegPayloadIdForTest(bytes);
}
