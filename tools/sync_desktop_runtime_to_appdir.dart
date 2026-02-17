import 'dart:convert';
import 'dart:io';

const String _kDefaultRuntimeSourceDir = 'assets/ocr/desktop_runtime';
const String _kDefaultBundleId = 'com.secondloop.secondloop';
const String _kDefaultWindowsCompanyName = 'com.secondloop';
const String _kDefaultWindowsProductName = 'SecondLoop';
const String _kReleaseMarker = '_secondloop_desktop_runtime_release.json';
const String _kRuntimeManifest = '_secondloop_desktop_runtime_manifest.json';

const List<String> _kDetModelAliases = <String>[
  'ch_PP-OCRv5_mobile_det.onnx',
  'ch_PP-OCRv4_det_infer.onnx',
  'ch_PP-OCRv3_det_infer.onnx',
];
const List<String> _kClsModelAliases = <String>[
  'ch_ppocr_mobile_v2.0_cls_infer.onnx',
];
const List<String> _kRecModelAliases = <String>[
  'ch_PP-OCRv5_rec_mobile_infer.onnx',
  'ch_PP-OCRv5_mobile_rec.onnx',
  'ch_PP-OCRv4_rec_infer.onnx',
  'ch_PP-OCRv3_rec_infer.onnx',
  'latin_PP-OCRv3_rec_infer.onnx',
  'arabic_PP-OCRv3_rec_infer.onnx',
  'cyrillic_PP-OCRv3_rec_infer.onnx',
  'devanagari_PP-OCRv3_rec_infer.onnx',
  'japan_PP-OCRv3_rec_infer.onnx',
  'korean_PP-OCRv3_rec_infer.onnx',
  'chinese_cht_PP-OCRv3_rec_infer.onnx',
];
const List<String> _kOnnxRuntimeLibAliases = <String>[
  'libonnxruntime.dylib',
  'libonnxruntime.so',
  'onnxruntime.dll',
];
const List<String> _kWhisperBaseModelAliases = <String>[
  'ggml-base.bin',
];

enum _DesktopPlatform {
  macos,
  linux,
  windows,
}

final class _Config {
  const _Config({
    required this.platform,
    required this.bundleId,
    required this.sourceDir,
    required this.dryRun,
  });

  final _DesktopPlatform platform;
  final String bundleId;
  final String sourceDir;
  final bool dryRun;
}

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  final sourceDir = Directory(config.sourceDir);
  if (!await sourceDir.exists()) {
    throw StateError('runtime source missing: ${sourceDir.path}');
  }

  final sourceFiles = await _collectRelativeFilePaths(sourceDir);
  if (sourceFiles.isEmpty) {
    throw StateError('runtime source is empty: ${sourceDir.path}');
  }

  final hasReleaseMarker = sourceFiles.contains(_kReleaseMarker);
  if (!hasReleaseMarker) {
    throw StateError(
      'runtime source missing release marker: ${sourceDir.path}/$_kReleaseMarker',
    );
  }

  final runtimePayloadReady = _hasRequiredRuntimePayload(sourceFiles);
  if (!runtimePayloadReady) {
    stderr.writeln(
      'sync-desktop-runtime-to-appdir: warning: OCR runtime payload incomplete in ${sourceDir.path}',
    );
  }
  final whisperBaseModelReady = _hasWhisperBaseModelPayload(sourceFiles);
  if (!whisperBaseModelReady) {
    stderr.writeln(
      'sync-desktop-runtime-to-appdir: warning: whisper base model payload missing in ${sourceDir.path}',
    );
  }

  final appSupportDir = _resolveAppSupportDir(
    platform: config.platform,
    bundleId: config.bundleId,
  );
  final runtimeDir = Directory(_joinPath(appSupportDir, 'ocr/desktop/runtime'));

  if (config.dryRun) {
    stdout.writeln(
      'sync-desktop-runtime-to-appdir: dry-run '
      'source=${sourceDir.path} '
      'dest=${runtimeDir.path} '
      'files=${sourceFiles.length} '
      'release_marker=$hasReleaseMarker '
      'runtime_payload_detected=$runtimePayloadReady '
      'whisper_base_detected=$whisperBaseModelReady',
    );
    return;
  }

  if (await runtimeDir.exists()) {
    await runtimeDir.delete(recursive: true);
  }
  await runtimeDir.create(recursive: true);

  final copiedCount = await _copyDirectoryContents(
    source: sourceDir,
    destination: runtimeDir,
  );

  final manifestPayload = <String, Object?>{
    'runtime': 'desktop_media',
    'version': 'v1',
    'installed_at_utc': DateTime.now().toUtc().toIso8601String(),
    'source': 'pixi_sync_desktop_runtime_to_appdir',
    'source_runtime_dir': sourceDir.path,
    'copied_file_count': copiedCount,
    'release_marker_present': hasReleaseMarker,
    'runtime_payload_detected': runtimePayloadReady,
    'whisper_base_model_detected': whisperBaseModelReady,
  };
  await File(_joinPath(runtimeDir.path, _kRuntimeManifest))
      .writeAsString(jsonEncode(manifestPayload), flush: true);

  stdout.writeln(
    'sync-desktop-runtime-to-appdir: synced $copiedCount files '
    '-> ${runtimeDir.path}',
  );
}

_Config _parseArgs(List<String> args) {
  var platform = _detectHostPlatform();
  var bundleId = _kDefaultBundleId;
  var sourceDir = _kDefaultRuntimeSourceDir;
  var dryRun = false;

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    if (arg == '--') continue;
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }
    if (arg.startsWith('--platform=')) {
      platform = _parsePlatform(arg.substring('--platform='.length));
      continue;
    }
    if (arg == '--platform') {
      platform = _parsePlatform(_requireNextValue(args, i, '--platform'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--bundle-id=')) {
      final value = arg.substring('--bundle-id='.length).trim();
      if (value.isNotEmpty) bundleId = value;
      continue;
    }
    if (arg == '--bundle-id') {
      final value = _requireNextValue(args, i, '--bundle-id').trim();
      if (value.isNotEmpty) bundleId = value;
      i += 1;
      continue;
    }
    if (arg.startsWith('--source-dir=')) {
      final value = arg.substring('--source-dir='.length).trim();
      if (value.isNotEmpty) sourceDir = value;
      continue;
    }
    if (arg == '--source-dir') {
      final value = _requireNextValue(args, i, '--source-dir').trim();
      if (value.isNotEmpty) sourceDir = value;
      i += 1;
      continue;
    }
    throw ArgumentError('Unknown argument: $arg');
  }

  return _Config(
    platform: platform,
    bundleId: bundleId,
    sourceDir: sourceDir,
    dryRun: dryRun,
  );
}

String _requireNextValue(List<String> args, int index, String flag) {
  if (index + 1 >= args.length) {
    throw ArgumentError('Missing value for $flag');
  }
  return args[index + 1];
}

_DesktopPlatform _detectHostPlatform() {
  if (Platform.isMacOS) return _DesktopPlatform.macos;
  if (Platform.isLinux) return _DesktopPlatform.linux;
  if (Platform.isWindows) return _DesktopPlatform.windows;
  throw StateError('Unsupported host platform for desktop runtime sync');
}

_DesktopPlatform _parsePlatform(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'macos':
      return _DesktopPlatform.macos;
    case 'linux':
      return _DesktopPlatform.linux;
    case 'windows':
      return _DesktopPlatform.windows;
  }
  throw ArgumentError('Unsupported platform: $raw');
}

String _resolveAppSupportDir({
  required _DesktopPlatform platform,
  required String bundleId,
}) {
  switch (platform) {
    case _DesktopPlatform.macos:
      final home = Platform.environment['HOME']?.trim() ?? '';
      if (home.isEmpty) throw StateError('HOME is not set');
      return '$home/Library/Application Support/$bundleId';
    case _DesktopPlatform.linux:
      final xdgDataHome = Platform.environment['XDG_DATA_HOME']?.trim() ?? '';
      if (xdgDataHome.isNotEmpty) return _joinPath(xdgDataHome, bundleId);
      final home = Platform.environment['HOME']?.trim() ?? '';
      if (home.isEmpty) throw StateError('HOME is not set');
      return '$home/.local/share/$bundleId';
    case _DesktopPlatform.windows:
      final appData = Platform.environment['APPDATA']?.trim() ?? '';
      if (appData.isEmpty) throw StateError('APPDATA is not set');
      return _resolveWindowsAppSupportDir(
        appData: appData,
        bundleId: bundleId,
      );
  }
}

String _resolveWindowsAppSupportDir({
  required String appData,
  required String bundleId,
}) {
  final normalizedBundleId = bundleId.trim();
  if (normalizedBundleId.isNotEmpty &&
      normalizedBundleId != _kDefaultBundleId) {
    return _joinPath(appData, normalizedBundleId);
  }

  return _joinPath(
    _joinPath(appData, _kDefaultWindowsCompanyName),
    _kDefaultWindowsProductName,
  );
}

String resolveWindowsAppSupportDirForTest({
  required String appData,
  required String bundleId,
}) {
  return _resolveWindowsAppSupportDir(
    appData: appData,
    bundleId: bundleId,
  );
}

String _joinPath(String base, String relative) {
  final normalizedBase = base.endsWith(Platform.pathSeparator)
      ? base.substring(0, base.length - 1)
      : base;
  final normalizedRelative = relative.startsWith(Platform.pathSeparator)
      ? relative.substring(1)
      : relative;
  return '$normalizedBase${Platform.pathSeparator}$normalizedRelative';
}

Future<Set<String>> _collectRelativeFilePaths(Directory baseDir) async {
  final files = <String>{};
  final prefix = '${baseDir.path}${Platform.pathSeparator}';
  await for (final entity
      in baseDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    var relative = entity.path;
    if (relative.startsWith(prefix)) {
      relative = relative.substring(prefix.length);
    }
    relative = relative.replaceAll('\\', '/');
    files.add(relative);
  }
  return files;
}

bool _containsAnyAlias(Set<String> sourceFiles, List<String> aliases) {
  for (final alias in aliases) {
    for (final path in sourceFiles) {
      if (path.endsWith('/$alias') || path == alias) return true;
    }
  }
  return false;
}

bool _hasRequiredRuntimePayload(Set<String> sourceFiles) {
  return _containsAnyAlias(sourceFiles, _kDetModelAliases) &&
      _containsAnyAlias(sourceFiles, _kClsModelAliases) &&
      _containsAnyAlias(sourceFiles, _kRecModelAliases) &&
      _containsAnyAlias(sourceFiles, _kOnnxRuntimeLibAliases);
}

bool _hasWhisperBaseModelPayload(Set<String> sourceFiles) {
  return _containsAnyAlias(sourceFiles, _kWhisperBaseModelAliases);
}

Future<int> _copyDirectoryContents({
  required Directory source,
  required Directory destination,
}) async {
  var copiedFiles = 0;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final outPath = _joinPath(destination.path, relative);
    if (entity is Directory) {
      await Directory(outPath).create(recursive: true);
      continue;
    }
    if (entity is File) {
      await File(outPath).parent.create(recursive: true);
      await entity.copy(outPath);
      copiedFiles += 1;
    }
  }
  return copiedFiles;
}
