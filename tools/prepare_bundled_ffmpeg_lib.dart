enum DesktopPlatform { macos, linux, windows }

DesktopPlatform parseDesktopPlatform(String value) {
  final normalized = value.trim().toLowerCase();
  switch (normalized) {
    case 'mac':
    case 'macos':
    case 'darwin':
      return DesktopPlatform.macos;
    case 'linux':
      return DesktopPlatform.linux;
    case 'win':
    case 'windows':
      return DesktopPlatform.windows;
  }
  throw FormatException('Unsupported desktop platform: $value');
}

String desktopPlatformFolderName(DesktopPlatform platform) {
  switch (platform) {
    case DesktopPlatform.macos:
      return 'macos';
    case DesktopPlatform.linux:
      return 'linux';
    case DesktopPlatform.windows:
      return 'windows';
  }
}

String bundledExecutableName(DesktopPlatform platform) {
  switch (platform) {
    case DesktopPlatform.windows:
      return 'ffmpeg.exe';
    case DesktopPlatform.macos:
    case DesktopPlatform.linux:
      return 'ffmpeg';
  }
}

String bundledRelativePath(DesktopPlatform platform) {
  final folder = desktopPlatformFolderName(platform);
  final executable = bundledExecutableName(platform);
  return 'assets/bin/ffmpeg/$folder/$executable';
}

String? resolveFfmpegFromPath({
  required String pathEnv,
  required DesktopPlatform platform,
  required String pathSeparator,
  required bool Function(String candidatePath) isFile,
}) {
  if (pathEnv.trim().isEmpty) return null;

  final names = <String>[
    if (platform == DesktopPlatform.windows) 'ffmpeg.exe',
    'ffmpeg',
  ];

  final entries = pathEnv
      .split(pathSeparator)
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty);

  for (final rawEntry in entries) {
    final entry = _trimOuterQuotes(rawEntry);
    if (entry.isEmpty) continue;
    for (final name in names) {
      final candidate = _joinDirectoryAndFile(entry, name, platform);
      if (isFile(candidate)) return candidate;
    }
  }

  return null;
}

String _joinDirectoryAndFile(
  String directory,
  String fileName,
  DesktopPlatform platform,
) {
  final hasTrailingSlash = directory.endsWith('/') || directory.endsWith(r'\');
  if (hasTrailingSlash) return '$directory$fileName';
  final separator = platform == DesktopPlatform.windows ? r'\' : '/';
  return '$directory$separator$fileName';
}

String _trimOuterQuotes(String value) {
  if (value.length < 2) return value;
  if (value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
