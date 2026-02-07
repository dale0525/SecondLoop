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

String? resolveFfmpegFromProjectPaths({
  required String projectRoot,
  required DesktopPlatform platform,
  required bool Function(String candidatePath) isFile,
}) {
  final executable = bundledExecutableName(platform);
  final platformFolder = desktopPlatformFolderName(platform);
  final candidates = <String>[
    _joinPath(
      projectRoot,
      <String>['.tools', 'ffmpeg', platformFolder, executable],
      platform,
    ),
    _joinPath(projectRoot, <String>['.tools', 'ffmpeg', executable], platform),
    _joinPath(
      projectRoot,
      <String>['.tool', 'ffmpeg', platformFolder, executable],
      platform,
    ),
    _joinPath(projectRoot, <String>['.tool', 'ffmpeg', executable], platform),
    if (platform == DesktopPlatform.windows)
      _joinPath(
        projectRoot,
        <String>['.pixi', 'envs', 'default', 'Library', 'bin', executable],
        platform,
      ),
    _joinPath(
      projectRoot,
      <String>['.pixi', 'envs', 'default', 'bin', executable],
      platform,
    ),
  ];

  for (final candidate in candidates) {
    if (isFile(candidate)) return candidate;
  }
  return null;
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

String _joinPath(
  String base,
  List<String> rest,
  DesktopPlatform platform,
) {
  var out = base;
  for (final part in rest) {
    out = _joinDirectoryAndFile(out, part, platform);
  }
  return out;
}

String _trimOuterQuotes(String value) {
  if (value.length < 2) return value;
  if (value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
