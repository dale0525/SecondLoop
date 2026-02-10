import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'prepare_desktop_runtime_hash_lib.dart';

const _runtimeTagPrefix = 'desktop-runtime-';
const _runtimeTagPattern =
    r'^desktop-runtime-v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$';
const _defaultOutputDir = 'assets/ocr/desktop_runtime';
const _defaultCacheDir = '.tool/cache/desktop-runtime';
const _installMarkerFile = '_secondloop_desktop_runtime_release.json';
const _detModelAliases = <String>[
  'ch_PP-OCRv5_mobile_det.onnx',
  'ch_PP-OCRv4_det_infer.onnx',
  'ch_PP-OCRv3_det_infer.onnx',
];
const _clsModelAliases = <String>[
  'ch_ppocr_mobile_v2.0_cls_infer.onnx',
];
const _recModelAliases = <String>[
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
const _onnxRuntimeLibAliases = <String>[
  'libonnxruntime.dylib',
  'libonnxruntime.so',
  'onnxruntime.dll',
];

enum _DesktopPlatform {
  linux,
  macos,
  windows,
}

enum _DesktopArch {
  x64,
  arm64,
}

class _Config {
  const _Config({
    required this.showHelp,
    required this.dryRun,
    required this.force,
    required this.requireRuntimeTag,
    required this.platform,
    required this.arch,
    required this.runtimeTag,
    required this.repo,
    required this.outputDir,
    required this.cacheDir,
  });

  final bool showHelp;
  final bool dryRun;
  final bool force;
  final bool requireRuntimeTag;
  final _DesktopPlatform? platform;
  final _DesktopArch? arch;
  final String? runtimeTag;
  final String? repo;
  final String outputDir;
  final String cacheDir;
}

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final localEnv = await _readDotenv('.env.local');
  final platform = config.platform ?? _detectHostPlatform();
  final arch = config.arch ?? await _detectHostArch();
  final repo = config.repo ?? await _resolveRepositorySlug(localEnv: localEnv);
  final runtimeTag = await _resolveRuntimeTag(
    configured: config.runtimeTag,
    repository: repo,
    requireExplicit: config.requireRuntimeTag,
    localEnv: localEnv,
  );

  final platformName = _platformName(platform);
  final archName = _archName(arch);
  await _installRuntimeTag(
    config: config,
    repo: repo,
    runtimeTag: runtimeTag,
    platformName: platformName,
    archName: archName,
  );
}

Future<void> _installRuntimeTag({
  required _Config config,
  required String repo,
  required String runtimeTag,
  required String platformName,
  required String archName,
}) async {
  if (!RegExp(_runtimeTagPattern).hasMatch(runtimeTag)) {
    throw StateError(
      'Invalid runtime tag: $runtimeTag. '
      'Expected desktop-runtime-vX.Y.Z or desktop-runtime-vX.Y.Z.W',
    );
  }

  final runtimeVersion = runtimeTag.substring(_runtimeTagPrefix.length);
  final archiveBaseName =
      'desktop-runtime-$platformName-$archName-$runtimeVersion.tar.gz';
  final partsListName = '$archiveBaseName.parts.txt';
  final shaFileName = '$archiveBaseName.sha256';

  final outputDir = Directory(config.outputDir);
  final cacheDir = Directory(
    _join(config.cacheDir, '$runtimeTag/$platformName-$archName'),
  );

  if (!config.force) {
    final alreadyInstalled = await _isRuntimeAlreadyInstalled(
      outputDir: outputDir,
      runtimeTag: runtimeTag,
      archiveBaseName: archiveBaseName,
      platform: platformName,
      arch: archName,
    );
    if (alreadyInstalled) {
      stdout.writeln(
        'prepare-desktop-runtime: runtime already installed '
        '($runtimeTag, $platformName/$archName)',
      );
      return;
    }
  }

  if (config.dryRun) {
    stdout.writeln('prepare-desktop-runtime dry-run');
    stdout.writeln('repo:         $repo');
    stdout.writeln('runtime_tag:  $runtimeTag');
    stdout.writeln('platform:     $platformName');
    stdout.writeln('arch:         $archName');
    stdout.writeln('archive:      $archiveBaseName');
    stdout.writeln('output_dir:   ${outputDir.path}');
    stdout.writeln('cache_dir:    ${cacheDir.path}');
    return;
  }

  await cacheDir.create(recursive: true);
  final partsListPath = _join(cacheDir.path, partsListName);
  final shaFilePath = _join(cacheDir.path, shaFileName);

  await _downloadReleaseAsset(
    repo: repo,
    runtimeTag: runtimeTag,
    assetName: partsListName,
    destinationPath: partsListPath,
  );
  await _downloadReleaseAsset(
    repo: repo,
    runtimeTag: runtimeTag,
    assetName: shaFileName,
    destinationPath: shaFilePath,
  );

  final partNames = await _readPartList(partsListPath);
  if (partNames.isEmpty) {
    throw StateError('Empty part list: $partsListPath');
  }

  for (final partName in partNames) {
    await _downloadReleaseAsset(
      repo: repo,
      runtimeTag: runtimeTag,
      assetName: partName,
      destinationPath: _join(cacheDir.path, partName),
    );
  }

  final assembledArchive = _join(cacheDir.path, archiveBaseName);
  await _assembleArchive(
    cacheDir: cacheDir.path,
    partNames: partNames,
    outputArchive: assembledArchive,
  );

  final expectedSha = await _readExpectedSha(shaFilePath);
  final actualSha = await _computeSha256(assembledArchive);
  if (actualSha == null) {
    throw StateError(
      'Cannot compute SHA256 for $assembledArchive '
      '(no sha256sum/shasum/certutil found)',
    );
  }
  if (expectedSha.toLowerCase() != actualSha.toLowerCase()) {
    throw StateError(
      'SHA256 mismatch for $assembledArchive\n'
      'expected=$expectedSha\nactual=$actualSha',
    );
  }

  final tempDir = Directory(
    '${outputDir.path}.tmp-${DateTime.now().millisecondsSinceEpoch}',
  );
  await tempDir.create(recursive: true);
  try {
    await _extractArchive(assembledArchive, tempDir.path);
    await _validateRuntimePayload(tempDir);

    if (await outputDir.exists()) {
      await outputDir.delete(recursive: true);
    }
    await tempDir.rename(outputDir.path);
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  await _writeInstallMarker(
    outputDir: outputDir,
    runtimeTag: runtimeTag,
    archiveBaseName: archiveBaseName,
    platform: platformName,
    arch: archName,
    repo: repo,
    sha256: actualSha,
  );

  stdout.writeln(
    'prepare-desktop-runtime: installed $runtimeTag '
    '($platformName/$archName) -> ${outputDir.path}',
  );
}

_Config _parseArgs(List<String> args) {
  var showHelp = false;
  var dryRun = false;
  var force = false;
  var requireRuntimeTag = false;
  _DesktopPlatform? platform;
  _DesktopArch? arch;
  String? runtimeTag;
  String? repo;
  var outputDir = _defaultOutputDir;
  var cacheDir = _defaultCacheDir;

  String nextValue(int index, String flagName) {
    if (index + 1 >= args.length) {
      throw ArgumentError('Missing value for $flagName');
    }
    return args[index + 1];
  }

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      showHelp = true;
      continue;
    }
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }
    if (arg == '--force') {
      force = true;
      continue;
    }
    if (arg == '--require-runtime-tag') {
      requireRuntimeTag = true;
      continue;
    }
    if (arg.startsWith('--platform=')) {
      platform = _requirePlatform(arg.substring('--platform='.length));
      continue;
    }
    if (arg == '--platform') {
      platform = _requirePlatform(nextValue(i, '--platform'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--arch=')) {
      arch = _requireArch(arg.substring('--arch='.length));
      continue;
    }
    if (arg == '--arch') {
      arch = _requireArch(nextValue(i, '--arch'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--runtime-tag=')) {
      runtimeTag = arg.substring('--runtime-tag='.length);
      continue;
    }
    if (arg == '--runtime-tag') {
      runtimeTag = nextValue(i, '--runtime-tag');
      i += 1;
      continue;
    }
    if (arg.startsWith('--repo=')) {
      repo = arg.substring('--repo='.length);
      continue;
    }
    if (arg == '--repo') {
      repo = nextValue(i, '--repo');
      i += 1;
      continue;
    }
    if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
      continue;
    }
    if (arg == '--output-dir') {
      outputDir = nextValue(i, '--output-dir');
      i += 1;
      continue;
    }
    if (arg.startsWith('--cache-dir=')) {
      cacheDir = arg.substring('--cache-dir='.length);
      continue;
    }
    if (arg == '--cache-dir') {
      cacheDir = nextValue(i, '--cache-dir');
      i += 1;
      continue;
    }
    throw ArgumentError('Unknown argument: $arg');
  }

  return _Config(
    showHelp: showHelp,
    dryRun: dryRun,
    force: force,
    requireRuntimeTag: requireRuntimeTag,
    platform: platform,
    arch: arch,
    runtimeTag: runtimeTag?.trim().isEmpty == true ? null : runtimeTag?.trim(),
    repo: repo?.trim().isEmpty == true ? null : repo?.trim(),
    outputDir: outputDir,
    cacheDir: cacheDir,
  );
}

Future<String> _resolveRuntimeTag({
  required String? configured,
  required String repository,
  required bool requireExplicit,
  required Map<String, String> localEnv,
}) async {
  final configuredTag = configured ??
      Platform.environment['SECONDLOOP_DESKTOP_RUNTIME_TAG']?.trim() ??
      localEnv['SECONDLOOP_DESKTOP_RUNTIME_TAG']?.trim();
  if (configuredTag != null && configuredTag.isNotEmpty) {
    return configuredTag;
  }

  if (requireExplicit) {
    throw StateError(
      'Missing runtime tag. Set SECONDLOOP_DESKTOP_RUNTIME_TAG or pass --runtime-tag.',
    );
  }

  final latest = await _discoverLatestRuntimeTag(repository);
  if (latest == null) {
    throw StateError(
      'Unable to discover latest desktop runtime tag for $repository. '
      'Set SECONDLOOP_DESKTOP_RUNTIME_TAG or pass --runtime-tag.',
    );
  }
  return latest;
}

Future<String?> _discoverLatestRuntimeTag(String repository) async {
  final url = Uri.parse(
    'https://api.github.com/repos/$repository/releases?per_page=100',
  );
  final responseText = await _httpGetText(url);
  final dynamic decoded = jsonDecode(responseText);
  if (decoded is! List) return null;

  for (final dynamic item in decoded) {
    if (item is! Map) continue;
    final tag = item['tag_name']?.toString() ?? '';
    final draft = item['draft'] == true;
    final prerelease = item['prerelease'] == true;
    if (draft || prerelease) continue;
    if (tag.startsWith('desktop-runtime-v')) return tag;
  }
  return null;
}

Future<bool> _isRuntimeAlreadyInstalled({
  required Directory outputDir,
  required String runtimeTag,
  required String archiveBaseName,
  required String platform,
  required String arch,
}) async {
  if (!await outputDir.exists()) return false;
  final marker = File(_join(outputDir.path, _installMarkerFile));
  if (!await marker.exists()) return false;
  final raw = await marker.readAsString();
  final dynamic decoded = jsonDecode(raw);
  if (decoded is! Map) return false;
  if ((decoded['runtime_tag']?.toString() ?? '') != runtimeTag) return false;
  if ((decoded['archive']?.toString() ?? '') != archiveBaseName) return false;
  if ((decoded['platform']?.toString() ?? '') != platform) return false;
  if ((decoded['arch']?.toString() ?? '') != arch) return false;

  final hasFiles =
      await outputDir.list(recursive: true).any((entity) => entity is File);
  if (!hasFiles) return false;
  return _hasRequiredRuntimePayload(outputDir);
}

Future<void> _validateRuntimePayload(Directory outputDir) async {
  final hasRequiredRuntime = await _hasRequiredRuntimePayload(outputDir);
  if (hasRequiredRuntime) return;

  throw StateError(
    'Runtime payload missing required OCR runtime files in ${outputDir.path}. '
    'Expected DET/CLS/REC model files and ONNX Runtime dynamic library.',
  );
}

Future<bool> _hasRequiredRuntimePayload(Directory outputDir) async {
  if (!await outputDir.exists()) return false;
  final basenames = <String>{};
  await for (final entity in outputDir.list(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    final unix = path.split('/');
    final windows = path.split('\\');
    basenames.add((windows.length > unix.length ? windows.last : unix.last));
  }

  bool containsAny(List<String> aliases) {
    for (final alias in aliases) {
      if (basenames.contains(alias)) return true;
    }
    return false;
  }

  return containsAny(_detModelAliases) &&
      containsAny(_clsModelAliases) &&
      containsAny(_recModelAliases) &&
      containsAny(_onnxRuntimeLibAliases);
}

Future<void> _downloadReleaseAsset({
  required String repo,
  required String runtimeTag,
  required String assetName,
  required String destinationPath,
}) async {
  final destinationFile = File(destinationPath);
  await destinationFile.parent.create(recursive: true);

  final ghDownloaded = await _downloadViaGh(
    repo: repo,
    runtimeTag: runtimeTag,
    assetName: assetName,
    destinationDir: destinationFile.parent.path,
  );
  if (ghDownloaded) return;

  final url = Uri.parse(
      'https://github.com/$repo/releases/download/$runtimeTag/$assetName');
  await _httpDownloadFile(url, destinationFile);
}

Future<bool> _downloadViaGh({
  required String repo,
  required String runtimeTag,
  required String assetName,
  required String destinationDir,
}) async {
  final hasGh = await _hasCommand('gh');
  if (!hasGh) return false;

  final result = await Process.run('gh', <String>[
    'release',
    'download',
    runtimeTag,
    '--repo',
    repo,
    '--pattern',
    assetName,
    '--dir',
    destinationDir,
    '--clobber',
  ]);

  if (result.exitCode != 0) return false;
  return true;
}

Future<List<String>> _readPartList(String path) async {
  final lines = await File(path).readAsLines();
  return lines
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

Future<void> _assembleArchive({
  required String cacheDir,
  required List<String> partNames,
  required String outputArchive,
}) async {
  final out = File(outputArchive);
  if (await out.exists()) {
    await out.delete();
  }
  await out.parent.create(recursive: true);

  final sink = out.openWrite();
  try {
    for (final part in partNames) {
      final partFile = File(_join(cacheDir, part));
      if (!await partFile.exists()) {
        throw StateError('Missing part file: ${partFile.path}');
      }
      await sink.addStream(partFile.openRead());
    }
  } finally {
    await sink.close();
  }
}

Future<String> _readExpectedSha(String shaFilePath) async {
  final raw = await File(shaFilePath).readAsString();
  final token = raw.trim().split(RegExp(r'\s+')).first;
  if (token.isEmpty) {
    throw StateError('Invalid sha256 file: $shaFilePath');
  }
  return token;
}

Future<String?> _computeSha256(String filePath) async {
  if (await _hasCommand('sha256sum')) {
    final result = await Process.run('sha256sum', <String>[filePath]);
    if (result.exitCode != 0) return null;
    return extractSha256FromCommandOutput('${result.stdout}');
  }

  if (await _hasCommand('shasum')) {
    final result = await Process.run('shasum', <String>['-a', '256', filePath]);
    if (result.exitCode != 0) return null;
    return extractSha256FromCommandOutput('${result.stdout}');
  }

  if (await _hasCommand('certutil')) {
    final result = await Process.run('certutil', <String>[
      '-hashfile',
      filePath,
      'SHA256',
    ]);
    if (result.exitCode != 0) return null;
    return extractSha256FromCommandOutput('${result.stdout}');
  }

  return null;
}

Future<void> _extractArchive(String archivePath, String outputDir) async {
  final tarResult = await Process.run('tar', <String>[
    '-xzf',
    archivePath,
    '-C',
    outputDir,
  ]);
  if (tarResult.exitCode == 0) return;

  final bytes = await File(archivePath).readAsBytes();
  final tarBytes = const GZipDecoder().decodeBytes(bytes);
  final archive = TarDecoder().decodeBytes(tarBytes);
  for (final entry in archive) {
    final name = entry.name;
    if (name.startsWith('/') || name.contains('..')) continue;
    final outPath = _join(outputDir, name);
    if (entry.isFile) {
      final file = File(outPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content as List<int>, flush: true);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}

Future<void> _writeInstallMarker({
  required Directory outputDir,
  required String runtimeTag,
  required String archiveBaseName,
  required String platform,
  required String arch,
  required String repo,
  required String sha256,
}) async {
  final marker = File(_join(outputDir.path, _installMarkerFile));
  final payload = <String, Object?>{
    'runtime_tag': runtimeTag,
    'archive': archiveBaseName,
    'platform': platform,
    'arch': arch,
    'repo': repo,
    'sha256': sha256,
    'installed_at_utc': DateTime.now().toUtc().toIso8601String(),
  };
  await marker.writeAsString(jsonEncode(payload), flush: true);
}

Future<String> _resolveRepositorySlug({
  required Map<String, String> localEnv,
}) async {
  final fromEnv = Platform.environment['SECONDLOOP_GITHUB_REPO']?.trim() ??
      localEnv['SECONDLOOP_GITHUB_REPO']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final fromGithub = Platform.environment['GITHUB_REPOSITORY']?.trim();
  if (fromGithub != null && fromGithub.isNotEmpty) return fromGithub;

  final result = await Process.run(
    'git',
    <String>['config', '--get', 'remote.origin.url'],
  );
  if (result.exitCode != 0) {
    throw StateError(
      'Cannot resolve repository slug. Set SECONDLOOP_GITHUB_REPO=owner/repo.',
    );
  }
  final remote = '${result.stdout}'.trim();
  final match = RegExp(r'github\.com[:/](.+?)(?:\.git)?$').firstMatch(remote);
  if (match == null) {
    throw StateError(
      'Cannot parse GitHub repository from remote URL: $remote. '
      'Set SECONDLOOP_GITHUB_REPO=owner/repo.',
    );
  }
  return match.group(1)!;
}

Future<Map<String, String>> _readDotenv(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) return const <String, String>{};

  final lines = await file.readAsLines();
  final values = <String, String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    var name = line.substring(0, eq).trim();
    if (name.startsWith('export ')) {
      name = name.substring(7).trim();
    }
    if (name.isEmpty) continue;

    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    values[name] = value;
  }
  return values;
}

Future<String> _httpGetText(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.headers.set('User-Agent', 'secondloop-runtime-preparer');
    final token = Platform.environment['GH_TOKEN'] ??
        Platform.environment['GITHUB_TOKEN'];
    if (token != null && token.trim().isNotEmpty) {
      request.headers.set('Authorization', 'Bearer ${token.trim()}');
    }
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} for $url',
        uri: url,
      );
    }
    return await utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}

Future<void> _httpDownloadFile(Uri url, File outputFile) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    request.followRedirects = true;
    request.headers.set('User-Agent', 'secondloop-runtime-preparer');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed downloading $url (HTTP ${response.statusCode})',
        uri: url,
      );
    }
    final sink = outputFile.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
  } finally {
    client.close(force: true);
  }
}

Future<bool> _hasCommand(String name) async {
  final probe = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(probe, <String>[name]);
  return result.exitCode == 0;
}

_DesktopPlatform _detectHostPlatform() {
  if (Platform.isLinux) return _DesktopPlatform.linux;
  if (Platform.isMacOS) return _DesktopPlatform.macos;
  if (Platform.isWindows) return _DesktopPlatform.windows;
  throw UnsupportedError(
      'Unsupported host platform: ${Platform.operatingSystem}');
}

Future<_DesktopArch> _detectHostArch() async {
  if (Platform.isWindows) {
    final raw = (Platform.environment['PROCESSOR_ARCHITEW6432'] ??
            Platform.environment['PROCESSOR_ARCHITECTURE'] ??
            '')
        .trim()
        .toLowerCase();
    final parsed = _parseArch(raw);
    if (parsed != null) return parsed;
    throw UnsupportedError('Unsupported Windows architecture: $raw');
  }

  final result = await Process.run('uname', <String>['-m']);
  if (result.exitCode != 0) {
    throw UnsupportedError(
        'Cannot detect host architecture (uname -m failed).');
  }
  final raw = '${result.stdout}'.trim().toLowerCase();
  final parsed = _parseArch(raw);
  if (parsed != null) return parsed;
  throw UnsupportedError('Unsupported host architecture: $raw');
}

_DesktopPlatform? _parsePlatform(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'linux':
      return _DesktopPlatform.linux;
    case 'macos':
    case 'darwin':
      return _DesktopPlatform.macos;
    case 'windows':
    case 'win':
      return _DesktopPlatform.windows;
    default:
      return null;
  }
}

_DesktopArch? _parseArch(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'x64':
    case 'x86_64':
    case 'amd64':
      return _DesktopArch.x64;
    case 'arm64':
    case 'aarch64':
      return _DesktopArch.arm64;
    default:
      return null;
  }
}

_DesktopPlatform _requirePlatform(String raw) {
  final parsed = _parsePlatform(raw);
  if (parsed != null) return parsed;
  throw ArgumentError('Unsupported --platform value: $raw');
}

_DesktopArch _requireArch(String raw) {
  final parsed = _parseArch(raw);
  if (parsed != null) return parsed;
  throw ArgumentError('Unsupported --arch value: $raw');
}

String _platformName(_DesktopPlatform platform) {
  switch (platform) {
    case _DesktopPlatform.linux:
      return 'linux';
    case _DesktopPlatform.macos:
      return 'macos';
    case _DesktopPlatform.windows:
      return 'windows';
  }
}

String _archName(_DesktopArch arch) {
  switch (arch) {
    case _DesktopArch.x64:
      return 'x64';
    case _DesktopArch.arm64:
      return 'arm64';
  }
}

String _join(String base, String part) {
  if (base.endsWith(Platform.pathSeparator)) return '$base$part';
  return '$base${Platform.pathSeparator}$part';
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tools/prepare_desktop_runtime.dart [options]

Options:
  --platform <linux|macos|windows>  Target desktop platform (default: host)
  --arch <x64|arm64>                Target arch (default: host)
  --runtime-tag <tag>               Runtime tag (desktop-runtime-vX.Y.Z[.W])
  --repo <owner/repo>               GitHub repository slug (default: auto detect)
  --output-dir <path>               Runtime assets output dir (default: assets/ocr/desktop_runtime)
  --cache-dir <path>                Download cache dir (default: .tool/cache/desktop-runtime)
  --require-runtime-tag             Fail if runtime tag is not explicitly set
  --force                           Force re-download and reinstall
  --dry-run                         Print resolved plan only
  -h, --help                        Show help
''');
}
