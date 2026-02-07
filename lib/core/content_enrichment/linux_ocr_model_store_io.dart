import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive.dart';

import '../backend/native_app_dir.dart';
import 'desktop_ocr_runtime.dart';
import 'linux_ocr_model_store.dart';
import 'linux_ocr_runtime_process.dart';

const String _kRapidOcrPypiJsonUrl =
    'https://pypi.org/pypi/rapidocr_onnxruntime/json';
const List<String> _kRapidOcrWheelModelFiles = <String>[
  'ch_PP-OCRv4_det_infer.onnx',
  'ch_ppocr_mobile_v2.0_cls_infer.onnx',
  'ch_PP-OCRv4_rec_infer.onnx',
];
const List<String> _kDesktopOcrModelFiles = <String>[
  ..._kRapidOcrWheelModelFiles,
  'latin_PP-OCRv3_rec_infer.onnx',
  'latin_dict.txt',
  'arabic_PP-OCRv3_rec_infer.onnx',
  'arabic_dict.txt',
  'cyrillic_PP-OCRv3_rec_infer.onnx',
  'cyrillic_dict.txt',
  'devanagari_PP-OCRv3_rec_infer.onnx',
  'devanagari_dict.txt',
  'japan_PP-OCRv3_rec_infer.onnx',
  'japan_dict.txt',
  'korean_PP-OCRv3_rec_infer.onnx',
  'korean_dict.txt',
  'chinese_cht_PP-OCRv3_rec_infer.onnx',
  'chinese_cht_dict.txt',
];
const List<_RemoteOcrModelAsset> _kMultilingualRecAssets =
    <_RemoteOcrModelAsset>[
  _RemoteOcrModelAsset(
    targetFileName: 'latin_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/latin_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'latin_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/latin_PP-OCRv3_rec_infer/resolve/main/latin_dict.txt?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'arabic_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/arabic_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'arabic_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/arabic_PP-OCRv3_rec_infer/resolve/main/arabic_dict.txt?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'cyrillic_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/cyrillic_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'cyrillic_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/cyrillic_PP-OCRv3_rec_infer/resolve/main/cyrillic_dict.txt?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'devanagari_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/devanagari_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'devanagari_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/devanagari_PP-OCRv3_rec_infer/resolve/main/devanagari_dict.txt?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'japan_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/japan_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'japan_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/japan_PP-OCRv3_rec_infer/resolve/main/japan_dict.txt?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'korean_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/korean_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'korean_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/korean_PP-OCRv3_rec_infer/resolve/main/korean_dict.txt?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'chinese_cht_PP-OCRv3_rec_infer.onnx',
    url:
        'https://huggingface.co/cycloneboy/chinese_cht_PP-OCRv3_rec_infer/resolve/main/model.onnx?download=true',
  ),
  _RemoteOcrModelAsset(
    targetFileName: 'chinese_cht_dict.txt',
    url:
        'https://huggingface.co/cycloneboy/chinese_cht_PP-OCRv3_rec_infer/resolve/main/chinese_cht_dict.txt?download=true',
  ),
];
const String _kPythonStandaloneReleaseApiUrl =
    'https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest';
const String _kManagedPythonVersionPrefix = '3.11.';
const List<String> _kRuntimeImportProbeModules = <String>[
  'rapidocr_onnxruntime',
  'pypdfium2',
  'onnxruntime',
  'cv2',
];
const List<String> _kRuntimePipPackages = <String>[
  'numpy',
  'pillow',
  'pyclipper',
  'shapely',
  'pyyaml',
  'tqdm',
  'six',
  'onnxruntime',
  'opencv-python-headless',
  'pypdfium2',
];
const Duration _kDownloadTimeout = Duration(minutes: 4);
const Duration _kPythonProbeTimeout = Duration(seconds: 5);
const Duration _kPipInstallTimeout = Duration(minutes: 15);
const Duration _kRuntimeProbeTimeout = Duration(seconds: 12);
const Duration _kChmodTimeout = Duration(seconds: 5);
const Duration _kXattrTimeout = Duration(seconds: 20);
const Duration _kAppDirResolveTimeout = Duration(seconds: 2);

typedef DesktopOcrManagedRuntimeInstaller = Future<void> Function({
  required Directory runtimeDir,
  required bool pythonAvailableAtDownload,
});

LinuxOcrModelStore createLinuxOcrModelStore({
  Future<String> Function()? appDirProvider,
}) {
  return FileSystemLinuxOcrModelStore(
    appDirProvider: appDirProvider ?? getNativeAppDir,
  );
}

final class FileSystemLinuxOcrModelStore implements LinuxOcrModelStore {
  const FileSystemLinuxOcrModelStore({
    required this.appDirProvider,
    this.pypiJsonUrl = _kRapidOcrPypiJsonUrl,
    this.supportsDesktopOcrModels = _supportsDesktopOcrModels,
    this.pythonExecutableResolver = _resolvePythonExecutable,
    this.downloadJson = _downloadJsonViaHttp,
    this.downloadFile = _downloadFileViaHttp,
    this.managedRuntimeInstaller = _installManagedDesktopOcrRuntime,
  });

  final Future<String> Function() appDirProvider;
  final String pypiJsonUrl;
  final bool Function() supportsDesktopOcrModels;
  final Future<String?> Function() pythonExecutableResolver;
  final Future<Map<String, Object?>> Function(Uri uri) downloadJson;
  final Future<void> Function(Uri uri, File outFile) downloadFile;
  final DesktopOcrManagedRuntimeInstaller managedRuntimeInstaller;

  @override
  Future<LinuxOcrModelStatus> readStatus() async {
    if (!supportsDesktopOcrModels()) {
      return const LinuxOcrModelStatus(
        supported: false,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      );
    }

    final modelDir = await _modelDirOrNull();
    if (modelDir == null) {
      return const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      );
    }
    final exists = await modelDir.exists();
    if (!exists) {
      return const LinuxOcrModelStatus(
        supported: true,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      );
    }

    var totalBytes = 0;
    var modelCount = 0;
    for (final targetFileName in _kDesktopOcrModelFiles) {
      final found = File('${modelDir.path}/$targetFileName');
      if (!await found.exists()) continue;
      modelCount += 1;
      final stat = await found.stat();
      totalBytes += stat.size;
    }

    var runtimeReady = false;
    final runtimeDir = await _runtimeDirOrNull();
    if (runtimeDir != null) {
      runtimeReady = await _hasManagedRuntimeMarker(runtimeDir);
      if (!runtimeReady) {
        runtimeReady = await _recoverManagedRuntimeIfUsable(
          runtimeDir: runtimeDir,
          modelDir: modelDir,
        );
      }
    }
    final runtimeInstallError = !runtimeReady
        ? await _readRuntimeInstallErrorFromModelManifest(modelDir)
        : null;

    final installed =
        modelCount == _kDesktopOcrModelFiles.length && runtimeReady;
    final runtimeMissing =
        modelCount == _kDesktopOcrModelFiles.length && !runtimeReady;
    String? statusMessage;
    if (!installed && runtimeMissing) {
      if (runtimeInstallError != null && runtimeInstallError.isNotEmpty) {
        statusMessage = 'runtime_missing:$runtimeInstallError';
      } else {
        statusMessage = 'runtime_missing';
      }
    }
    return LinuxOcrModelStatus(
      supported: true,
      installed: installed,
      modelDirPath: installed ? modelDir.path : null,
      modelCount: modelCount,
      totalBytes: totalBytes,
      source:
          installed ? LinuxOcrModelSource.downloaded : LinuxOcrModelSource.none,
      message: statusMessage,
    );
  }

  @override
  Future<LinuxOcrModelStatus> downloadModels() async {
    if (!supportsDesktopOcrModels()) {
      throw StateError('linux_ocr_models_not_supported');
    }
    final pythonAvailable = (await pythonExecutableResolver()) != null;

    final wheel = await _resolveRapidOcrWheel();
    final tempDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_ocr_models_',
    );
    final wheelFile = File('${tempDir.path}/rapidocr_onnxruntime.whl');
    final modelDir = await _modelDirOrThrow();
    final runtimeDir = await _runtimeDirOrThrow();

    try {
      await downloadFile(Uri.parse(wheel.url), wheelFile);
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
      }
      await modelDir.create(recursive: true);
      await _extractModelsFromWheel(
        wheelPath: wheelFile.path,
        outputDir: modelDir.path,
      );
      await _downloadMultilingualModels(modelDir);
      String? runtimeInstallError;
      try {
        await managedRuntimeInstaller(
          runtimeDir: runtimeDir,
          pythonAvailableAtDownload: pythonAvailable,
        );
      } catch (e) {
        if (_isRecoverableRuntimeInstallError(e)) {
          runtimeInstallError = _normalizeRuntimeInstallError(e);
        } else {
          rethrow;
        }
      }
      await _writeManifest(
        modelDir: modelDir,
        version: wheel.version,
        wheelUrl: wheel.url,
        pythonAvailableAtDownload: pythonAvailable,
        runtimeInstallError: runtimeInstallError,
      );
      return readStatus();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<LinuxOcrModelStatus> deleteModels() async {
    if (!supportsDesktopOcrModels()) {
      throw StateError('linux_ocr_models_not_supported');
    }
    final modelDir = await _modelDirOrThrow();
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
    return readStatus();
  }

  @override
  Future<String?> readInstalledModelDir() async {
    final status = await readStatus();
    return status.installed ? status.modelDirPath : null;
  }

  Future<Directory?> _modelDirOrNull() async {
    try {
      final appDir = await appDirProvider().timeout(_kAppDirResolveTimeout);
      return Directory('$appDir/ocr/desktop/models');
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _runtimeDirOrNull() async {
    try {
      final appDir = await appDirProvider().timeout(_kAppDirResolveTimeout);
      return resolveDesktopOcrRuntimeDir(
        appDirProvider: () async => appDir,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _runtimeDirOrThrow() async {
    final runtimeDir = await _runtimeDirOrNull();
    if (runtimeDir != null) return runtimeDir;
    throw StateError('linux_ocr_app_dir_unavailable');
  }

  Future<Directory> _modelDirOrThrow() async {
    final modelDir = await _modelDirOrNull();
    if (modelDir != null) return modelDir;
    throw StateError('linux_ocr_app_dir_unavailable');
  }

  Future<_RapidOcrWheel> _resolveRapidOcrWheel() async {
    final payload = await downloadJson(Uri.parse(pypiJsonUrl));
    final info = payload['info'];
    final infoMap = info is Map ? info : const {};
    final version = (infoMap['version']?.toString() ?? '').trim();

    final candidates = payload['urls'];
    if (candidates is List) {
      for (final raw in candidates) {
        if (raw is! Map) continue;
        final packageType = (raw['packagetype']?.toString() ?? '').trim();
        final filename = (raw['filename']?.toString() ?? '').trim();
        final url = (raw['url']?.toString() ?? '').trim();
        if (packageType != 'bdist_wheel') continue;
        if (!filename.contains('py3-none-any.whl')) continue;
        if (url.isEmpty) continue;
        return _RapidOcrWheel(url: url, version: version);
      }
    }

    throw StateError('linux_ocr_wheel_not_found');
  }

  Future<void> _extractModelsFromWheel({
    required String wheelPath,
    required String outputDir,
  }) async {
    final wheelFile = File(wheelPath);
    if (!await wheelFile.exists()) {
      throw StateError('linux_ocr_extract_failed:wheel_missing');
    }

    Archive archive;
    try {
      final bytes = await wheelFile.readAsBytes();
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (e) {
      throw StateError('linux_ocr_extract_failed:$e');
    }

    final entriesByPath = <String, ArchiveFile>{
      for (final entry in archive.files)
        if (entry.isFile) entry.name: entry,
    };
    for (final targetFileName in _kRapidOcrWheelModelFiles) {
      final sourcePath = 'rapidocr_onnxruntime/models/$targetFileName';
      final entry = entriesByPath[sourcePath];
      if (entry == null) {
        throw StateError('linux_ocr_extract_missing:$targetFileName');
      }
      final outFile = File('$outputDir/$targetFileName');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content, flush: true);
    }
  }

  Future<void> _downloadMultilingualModels(Directory modelDir) async {
    for (final asset in _kMultilingualRecAssets) {
      final outFile = File('${modelDir.path}/${asset.targetFileName}');
      await outFile.parent.create(recursive: true);
      await downloadFile(Uri.parse(asset.url), outFile);
    }
  }

  Future<void> _writeManifest({
    required Directory modelDir,
    required String version,
    required String wheelUrl,
    required bool pythonAvailableAtDownload,
    String? runtimeInstallError,
  }) async {
    final file = File('${modelDir.path}/_secondloop_manifest.json');
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, Object?>{
      'source': 'pypi',
      'package': 'rapidocr_onnxruntime',
      'version': version,
      'wheel_url': wheelUrl,
      'downloaded_at_utc': now,
      'python_available_at_download': pythonAvailableAtDownload,
      'model_files': _kDesktopOcrModelFiles,
      'multilingual_model_files': <String>[
        for (final asset in _kMultilingualRecAssets) asset.targetFileName,
      ],
      if (runtimeInstallError != null && runtimeInstallError.trim().isNotEmpty)
        'runtime_install_error': runtimeInstallError.trim(),
    };
    await file.writeAsString(
      jsonEncode(payload),
      flush: true,
    );
  }

  Future<String?> _readRuntimeInstallErrorFromModelManifest(
    Directory modelDir,
  ) async {
    final file = File('${modelDir.path}/_secondloop_manifest.json');
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final value = decoded['runtime_install_error']?.toString().trim() ?? '';
      if (value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }
}

Future<Map<String, Object?>> _downloadJsonViaHttp(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_kDownloadTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'request_failed:${response.statusCode}',
        uri: uri,
      );
    }

    final text = await utf8
        .decodeStream(response)
        .timeout(_kDownloadTimeout, onTimeout: () => '{}');
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw StateError('linux_ocr_invalid_json');
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadFileViaHttp(Uri uri, File outFile) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(_kDownloadTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'download_failed:${response.statusCode}',
        uri: uri,
      );
    }
    final sink = outFile.openWrite();
    await response.pipe(sink);
    await sink.close();
  } finally {
    client.close(force: true);
  }
}

Future<void> _installManagedDesktopOcrRuntime({
  required Directory runtimeDir,
  required bool pythonAvailableAtDownload,
}) async {
  if (await _isManagedRuntimeUsable(runtimeDir)) {
    return;
  }

  final hostPython = await _resolvePythonExecutable();
  if (hostPython != null) {
    final installedViaSystem = await _installRuntimeUsingSystemPython(
      runtimeDir: runtimeDir,
      pythonExecutable: hostPython,
      pythonAvailableAtDownload: pythonAvailableAtDownload,
    );
    if (installedViaSystem) {
      return;
    }
  }

  final release = await _resolvePythonStandaloneReleaseAsset();
  final tempDir = await Directory.systemTemp.createTemp(
    'secondloop_desktop_ocr_runtime_',
  );
  final archiveFile = File('${tempDir.path}/${release.fileName}');

  try {
    await _downloadFileViaHttp(Uri.parse(release.url), archiveFile);
    if (await runtimeDir.exists()) {
      await runtimeDir.delete(recursive: true);
    }
    await runtimeDir.create(recursive: true);
    await _extractTarGzArchive(
      archiveFile: archiveFile,
      outputDir: runtimeDir,
    );
    await _ensureManagedPythonExecutablePermissions(runtimeDir);
    await _clearMacQuarantineRecursively(runtimeDir);
    final pythonExecutable = await _resolveManagedPythonExecutableFromDir(
      runtimeDir,
      requireProbe: false,
    );
    if (pythonExecutable == null) {
      throw StateError('linux_ocr_runtime_python_missing');
    }
    await _installRuntimePackages(pythonExecutable);
    final importReady = await probePythonModules(
      pythonExecutable,
      timeout: _kRuntimeProbeTimeout,
    );
    if (!importReady) {
      throw StateError('linux_ocr_runtime_packages_invalid');
    }
    await _writeRuntimeManifest(
      runtimeDir: runtimeDir,
      pythonAvailableAtDownload: pythonAvailableAtDownload,
      source: 'python-build-standalone',
      releaseTag: release.releaseTag,
      archiveName: release.fileName,
      pythonExecutable: pythonExecutable,
    );
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<bool> _installRuntimeUsingSystemPython({
  required Directory runtimeDir,
  required String pythonExecutable,
  required bool pythonAvailableAtDownload,
}) async {
  final sitePackagesDir = Directory('${runtimeDir.path}/site-packages');
  try {
    if (await runtimeDir.exists()) {
      await runtimeDir.delete(recursive: true);
    }
    await sitePackagesDir.create(recursive: true);
    await _installRuntimePackages(
      pythonExecutable,
      targetDir: sitePackagesDir.path,
    );
    final importReady = await probePythonModules(
      pythonExecutable,
      timeout: _kRuntimeProbeTimeout,
      extraPythonPath: sitePackagesDir.path,
    );
    if (!importReady) {
      return false;
    }
    await _writeRuntimeManifest(
      runtimeDir: runtimeDir,
      pythonAvailableAtDownload: pythonAvailableAtDownload,
      source: 'system-python-target',
      pythonExecutable: pythonExecutable,
      pythonPath: sitePackagesDir.path,
    );
    return true;
  } catch (_) {
    try {
      if (await runtimeDir.exists()) {
        await runtimeDir.delete(recursive: true);
      }
    } catch (_) {}
    return false;
  }
}

Future<bool> _isManagedRuntimeUsable(Directory runtimeDir) async {
  if (!await runtimeDir.exists()) return false;
  final marker = File('${runtimeDir.path}/_secondloop_runtime_manifest.json');
  if (!await marker.exists()) return false;
  final probe = await _probeManagedRuntimeFromLayout(runtimeDir);
  return probe.ready;
}

Future<_RuntimeProbeState> _probeManagedRuntimeFromLayout(
  Directory runtimeDir,
) async {
  if (!await runtimeDir.exists()) {
    return const _RuntimeProbeState(ready: false);
  }
  final siteDir = await _resolveManagedSitePackagesDir(runtimeDir);
  if (siteDir == null) {
    return const _RuntimeProbeState(ready: false);
  }
  final modulePresent = await _hasRapidOcrModuleInSitePackages(siteDir);
  if (!modulePresent) {
    return const _RuntimeProbeState(ready: false);
  }
  final pythonPathHint =
      _requiresPythonPathInjection(runtimeDir, siteDir) ? siteDir.path : null;
  final python = await _resolveManagedPythonExecutableFromDir(runtimeDir);
  if (python != null) {
    final ready = await probePythonModules(
      python,
      timeout: _kRuntimeProbeTimeout,
      extraPythonPath: pythonPathHint,
    );
    if (ready) {
      return _RuntimeProbeState(
        ready: true,
        pythonExecutable: python,
        pythonPath: pythonPathHint,
      );
    }
    return const _RuntimeProbeState(ready: false);
  }
  final manifest = await _readRuntimeManifest(runtimeDir);
  final configuredPython = _readRuntimePythonExecutableFromManifest(manifest);
  if (configuredPython != null) {
    final configuredReady = await probePythonModules(
      configuredPython,
      timeout: _kRuntimeProbeTimeout,
      extraPythonPath: pythonPathHint,
    );
    if (configuredReady) {
      return _RuntimeProbeState(
        ready: true,
        pythonExecutable: configuredPython,
        pythonPath: pythonPathHint,
      );
    }
  }
  final hostPython = await _resolvePythonExecutable();
  if (hostPython == null) {
    return const _RuntimeProbeState(ready: false);
  }
  final hostReady = await probePythonModules(
    hostPython,
    timeout: _kRuntimeProbeTimeout,
    extraPythonPath: pythonPathHint,
  );
  if (!hostReady) {
    return const _RuntimeProbeState(ready: false);
  }
  return _RuntimeProbeState(
    ready: true,
    pythonExecutable: hostPython,
    pythonPath: pythonPathHint,
  );
}

Future<bool> _hasManagedRuntimeMarker(Directory runtimeDir) async {
  if (!await runtimeDir.exists()) return false;
  final marker = File('${runtimeDir.path}/_secondloop_runtime_manifest.json');
  if (!await marker.exists()) return false;
  final siteDir = await _resolveManagedSitePackagesDir(runtimeDir);
  if (siteDir == null) return false;
  if (!await _hasRapidOcrModuleInSitePackages(siteDir)) return false;
  final managedPython = await _resolveManagedPythonExecutableFromDir(
    runtimeDir,
    requireProbe: false,
  );
  if (managedPython != null) return true;
  final manifest = await _readRuntimeManifest(runtimeDir);
  final configuredPython = _readRuntimePythonExecutableFromManifest(manifest);
  if (configuredPython != null && await File(configuredPython).exists()) {
    return true;
  }
  final hostPython = await _resolvePythonExecutable();
  return hostPython != null;
}

Future<bool> _recoverManagedRuntimeIfUsable({
  required Directory runtimeDir,
  required Directory modelDir,
}) async {
  final probe = await _probeManagedRuntimeFromLayout(runtimeDir);
  if (!probe.ready) return false;
  await _writeRecoveredRuntimeManifest(runtimeDir: runtimeDir, probe: probe);
  await _clearRuntimeInstallErrorFromModelManifest(modelDir);
  return true;
}

Future<void> _writeRecoveredRuntimeManifest({
  required Directory runtimeDir,
  required _RuntimeProbeState probe,
}) async {
  final file = File('${runtimeDir.path}/_secondloop_runtime_manifest.json');
  if (await file.exists()) return;
  final payload = <String, Object?>{
    'source': 'runtime-recovered',
    'downloaded_at_utc': DateTime.now().toUtc().toIso8601String(),
    'python_available_at_download': true,
    'modules': _kRuntimeImportProbeModules,
    if (probe.pythonExecutable != null &&
        probe.pythonExecutable!.trim().isNotEmpty)
      'python_executable': probe.pythonExecutable!.trim(),
    if (probe.pythonPath != null && probe.pythonPath!.trim().isNotEmpty)
      'python_path': probe.pythonPath!.trim(),
  };
  try {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {}
}

Future<void> _clearRuntimeInstallErrorFromModelManifest(
    Directory modelDir) async {
  final file = File('${modelDir.path}/_secondloop_manifest.json');
  if (!await file.exists()) return;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return;
    final payload = decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (!payload.containsKey('runtime_install_error')) return;
    payload.remove('runtime_install_error');
    await file.writeAsString(jsonEncode(payload), flush: true);
  } catch (_) {}
}

Future<bool> _hasRapidOcrModuleInSitePackages(Directory siteDir) async {
  final moduleCandidates = <String>[
    '${siteDir.path}/rapidocr_onnxruntime',
    '${siteDir.path}/rapidocr_onnxruntime.py',
  ];
  for (final candidate in moduleCandidates) {
    if (await File(candidate).exists()) return true;
    if (await Directory(candidate).exists()) return true;
  }
  return false;
}

Future<String?> _resolveManagedPythonExecutableFromDir(
  Directory runtimeDir, {
  bool requireProbe = true,
}) async {
  final candidates = <String>[
    '${runtimeDir.path}/python/bin/python3.11',
    '${runtimeDir.path}/python/bin/python3.10',
    '${runtimeDir.path}/python/bin/python3',
    '${runtimeDir.path}/python/bin/python',
    '${runtimeDir.path}/python/python.exe',
    '${runtimeDir.path}/python/python3.exe',
  ];
  for (final path in candidates) {
    if (!await File(path).exists()) continue;
    if (!requireProbe) return path;
    await _clearMacQuarantineForFile(path);
    final ok = await _probePythonBinary(path);
    if (ok) return path;
  }
  return null;
}

Future<bool> _probePythonBinary(String executablePath) async {
  try {
    final result = await Process.run(
      executablePath,
      const <String>['--version'],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(_kPythonProbeTimeout);
    if (result.exitCode != 0) return false;
    final out = ((result.stdout as String?) ?? '').trim();
    final err = ((result.stderr as String?) ?? '').trim();
    final text = '$out $err';
    return text.contains('Python ');
  } catch (_) {
    return false;
  }
}

Future<Directory?> _resolveManagedSitePackagesDir(Directory runtimeDir) async {
  final portableSite = Directory('${runtimeDir.path}/site-packages');
  if (await portableSite.exists()) return portableSite;
  final libRoot = Directory('${runtimeDir.path}/python/lib');
  if (await libRoot.exists()) {
    await for (final child in libRoot.list(followLinks: false)) {
      if (child is! Directory) continue;
      final name = child.path.split('/').last;
      if (!name.startsWith('python')) continue;
      final site = Directory('${child.path}/site-packages');
      if (await site.exists()) return site;
    }
  }
  final windowsSite = Directory('${runtimeDir.path}/python/Lib/site-packages');
  if (await windowsSite.exists()) return windowsSite;
  return null;
}

bool _requiresPythonPathInjection(Directory runtimeDir, Directory siteDir) {
  final runtimeRoot = runtimeDir.path;
  final sitePath = siteDir.path;
  return sitePath == '$runtimeRoot/site-packages';
}

Future<Map<String, Object?>?> _readRuntimeManifest(Directory runtimeDir) async {
  final file = File('${runtimeDir.path}/_secondloop_runtime_manifest.json');
  if (!await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  } catch (_) {
    return null;
  }
}

String? _readRuntimePythonExecutableFromManifest(
  Map<String, Object?>? manifest,
) {
  final value = manifest?['python_executable']?.toString().trim() ?? '';
  if (value.isEmpty) return null;
  return value;
}

Future<void> _clearMacQuarantineRecursively(Directory target) async {
  if (!Platform.isMacOS) return;
  try {
    await Process.run(
      'xattr',
      <String>['-dr', 'com.apple.quarantine', target.path],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(_kXattrTimeout);
  } catch (_) {}
}

Future<void> _clearMacQuarantineForFile(String filePath) async {
  if (!Platform.isMacOS) return;
  try {
    await Process.run(
      'xattr',
      <String>['-d', 'com.apple.quarantine', filePath],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(_kXattrTimeout);
  } catch (_) {}
}

Future<void> _extractTarGzArchive({
  required File archiveFile,
  required Directory outputDir,
}) async {
  final compressed = await archiveFile.readAsBytes();
  final tarBytes = const GZipDecoder().decodeBytes(compressed);
  final archive = TarDecoder().decodeBytes(tarBytes);

  for (final entry in archive.files) {
    final relativePath = _normalizeArchivePath(entry.name);
    if (relativePath == null) continue;
    final outputPath = '${outputDir.path}/$relativePath';
    if (entry.isSymbolicLink && !Platform.isWindows) {
      final target = entry.symbolicLink?.trim() ?? '';
      if (target.isEmpty) continue;
      final link = Link(outputPath);
      await link.parent.create(recursive: true);
      try {
        final existingType = FileSystemEntity.typeSync(
          outputPath,
          followLinks: false,
        );
        if (existingType == FileSystemEntityType.file ||
            existingType == FileSystemEntityType.link) {
          await File(outputPath).delete();
        } else if (existingType == FileSystemEntityType.directory) {
          await Directory(outputPath).delete(recursive: true);
        }
      } catch (_) {}
      try {
        await link.create(target, recursive: true);
      } catch (_) {}
      continue;
    }
    if (entry.isFile) {
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content, flush: true);
      continue;
    }
    await Directory(outputPath).create(recursive: true);
  }
}

String? _normalizeArchivePath(String rawPath) {
  final path = rawPath.replaceAll('\\', '/').trim();
  if (path.isEmpty) return null;
  if (path.startsWith('/') || path.startsWith('../') || path.contains('/../')) {
    return null;
  }
  return path;
}

Future<void> _ensureManagedPythonExecutablePermissions(
  Directory runtimeDir,
) async {
  if (Platform.isWindows) return;
  final candidates = <String>[
    '${runtimeDir.path}/python/bin/python',
    '${runtimeDir.path}/python/bin/python3',
    '${runtimeDir.path}/python/bin/python3.11',
    '${runtimeDir.path}/python/bin/pip',
    '${runtimeDir.path}/python/bin/pip3',
    '${runtimeDir.path}/python/bin/pip3.11',
  ];
  for (final candidate in candidates) {
    if (!await File(candidate).exists()) continue;
    try {
      await Process.run(
        'chmod',
        <String>['755', candidate],
        runInShell: false,
      ).timeout(_kChmodTimeout);
    } catch (_) {}
  }
}

Future<void> _installRuntimePackages(
  String pythonExecutable, {
  String? targetDir,
}) async {
  final baseArgs = <String>[
    '-m',
    'pip',
    'install',
    '--disable-pip-version-check',
    '--no-input',
    '--no-cache-dir',
    '--only-binary=:all:',
    if (targetDir != null && targetDir.trim().isNotEmpty) ...<String>[
      '--target',
      targetDir.trim()
    ],
  ];

  final baseInstall = await runPipInstallWithRetry(
    pythonExecutable: pythonExecutable,
    args: <String>[
      ...baseArgs,
      ..._kRuntimePipPackages,
    ],
    timeout: _kPipInstallTimeout,
    onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
    clearQuarantineForFile: _clearMacQuarantineForFile,
    ensurePermission: (path) => ensureExecutablePermission(
      path,
      chmodTimeout: _kChmodTimeout,
    ),
  );
  if (baseInstall.exitCode != 0) {
    final stderr = (baseInstall.stderr as String?)?.trim() ?? 'unknown';
    throw StateError('linux_ocr_runtime_pip_failed:$stderr');
  }

  final rapidocrInstall = await runPipInstallWithRetry(
    pythonExecutable: pythonExecutable,
    args: <String>[
      ...baseArgs,
      '--no-deps',
      'rapidocr_onnxruntime',
    ],
    timeout: _kPipInstallTimeout,
    onTimeout: () => ProcessResult(0, -1, '', 'timeout'),
    clearQuarantineForFile: _clearMacQuarantineForFile,
    ensurePermission: (path) => ensureExecutablePermission(
      path,
      chmodTimeout: _kChmodTimeout,
    ),
  );
  if (rapidocrInstall.exitCode != 0) {
    final stderr = (rapidocrInstall.stderr as String?)?.trim() ?? 'unknown';
    throw StateError('linux_ocr_runtime_pip_failed:$stderr');
  }
}

Future<_PythonStandaloneReleaseAsset>
    _resolvePythonStandaloneReleaseAsset() async {
  final payload =
      await _downloadJsonViaHttp(Uri.parse(_kPythonStandaloneReleaseApiUrl));
  final releaseTag = payload['tag_name']?.toString().trim();
  final suffix = _runtimeAssetSuffixForCurrentAbi();
  if (releaseTag == null || releaseTag.isEmpty || suffix == null) {
    throw StateError('linux_ocr_runtime_release_not_found');
  }

  final assets = payload['assets'];
  if (assets is! List) {
    throw StateError('linux_ocr_runtime_release_not_found');
  }

  const expectedPrefix = 'cpython-$_kManagedPythonVersionPrefix';
  for (final raw in assets) {
    if (raw is! Map) continue;
    final name = raw['name']?.toString().trim() ?? '';
    final url = raw['browser_download_url']?.toString().trim() ?? '';
    if (!name.startsWith(expectedPrefix)) continue;
    if (!name.endsWith(suffix)) continue;
    if (url.isEmpty) continue;
    return _PythonStandaloneReleaseAsset(
      releaseTag: releaseTag,
      fileName: name,
      url: url,
    );
  }

  throw StateError('linux_ocr_runtime_asset_not_found');
}

String? _runtimeAssetSuffixForCurrentAbi() {
  switch (Abi.current()) {
    case Abi.macosArm64:
      return 'aarch64-apple-darwin-install_only.tar.gz';
    case Abi.macosX64:
      return 'x86_64-apple-darwin-install_only.tar.gz';
    case Abi.linuxX64:
      return 'x86_64-unknown-linux-gnu-install_only.tar.gz';
    case Abi.linuxArm64:
      return 'aarch64-unknown-linux-gnu-install_only.tar.gz';
    case Abi.windowsX64:
      return 'x86_64-pc-windows-msvc-install_only.tar.gz';
    case Abi.windowsArm64:
      return 'aarch64-pc-windows-msvc-install_only.tar.gz';
    default:
      return null;
  }
}

Future<void> _writeRuntimeManifest({
  required Directory runtimeDir,
  required bool pythonAvailableAtDownload,
  required String source,
  String? releaseTag,
  String? archiveName,
  String? pythonExecutable,
  String? pythonPath,
}) async {
  final file = File('${runtimeDir.path}/_secondloop_runtime_manifest.json');
  final now = DateTime.now().toUtc().toIso8601String();
  final payload = <String, Object?>{
    'source': source,
    if (releaseTag != null && releaseTag.trim().isNotEmpty)
      'release_tag': releaseTag.trim(),
    if (archiveName != null && archiveName.trim().isNotEmpty)
      'archive': archiveName.trim(),
    'downloaded_at_utc': now,
    'python_available_at_download': pythonAvailableAtDownload,
    'modules': _kRuntimeImportProbeModules,
    if (pythonExecutable != null && pythonExecutable.trim().isNotEmpty)
      'python_executable': pythonExecutable.trim(),
    if (pythonPath != null && pythonPath.trim().isNotEmpty)
      'python_path': pythonPath.trim(),
  };
  await file.writeAsString(jsonEncode(payload), flush: true);
}

bool _supportsDesktopOcrModels() {
  if (Platform.isLinux) return true;
  if (Platform.isMacOS) return true;
  if (Platform.isWindows) return true;
  return false;
}

final class _RapidOcrWheel {
  const _RapidOcrWheel({
    required this.url,
    required this.version,
  });

  final String url;
  final String version;
}

final class _RemoteOcrModelAsset {
  const _RemoteOcrModelAsset({
    required this.targetFileName,
    required this.url,
  });

  final String targetFileName;
  final String url;
}

final class _PythonStandaloneReleaseAsset {
  const _PythonStandaloneReleaseAsset({
    required this.releaseTag,
    required this.fileName,
    required this.url,
  });

  final String releaseTag;
  final String fileName;
  final String url;
}

final class _RuntimeProbeState {
  const _RuntimeProbeState({
    required this.ready,
    this.pythonExecutable,
    this.pythonPath,
  });

  final bool ready;
  final String? pythonExecutable;
  final String? pythonPath;
}

Future<String?> _resolvePythonExecutable() async {
  final candidates = <String>[
    'python3',
    'python',
    if (!Platform.isWindows) ...<String>[
      '/usr/bin/python3',
      '/usr/local/bin/python3',
    ],
    if (Platform.isMacOS) ...<String>[
      '/opt/homebrew/bin/python3',
      '/opt/local/bin/python3',
    ],
  ];
  for (final candidate in candidates) {
    try {
      final result = await Process.run(
        candidate,
        const <String>['--version'],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(_kPythonProbeTimeout);
      if (result.exitCode == 0) {
        final out = ((result.stdout as String?) ?? '').trim();
        final err = ((result.stderr as String?) ?? '').trim();
        if ('$out $err'.contains('Python ')) {
          return candidate;
        }
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

bool _isRecoverableRuntimeInstallError(Object error) {
  final message = '$error'.toLowerCase();
  return message.contains('linux_ocr_runtime_exec_not_permitted') ||
      message.contains('linux_ocr_runtime_python_missing') ||
      message.contains('linux_ocr_runtime_pip_failed') ||
      message.contains('linux_ocr_runtime_packages_invalid') ||
      message.contains('operation not permitted') ||
      message.contains('permission denied');
}

String _normalizeRuntimeInstallError(Object error) {
  final raw = '$error';
  const known = <String>[
    'linux_ocr_runtime_exec_not_permitted',
    'linux_ocr_runtime_python_missing',
    'linux_ocr_runtime_pip_failed',
    'linux_ocr_runtime_packages_invalid',
  ];
  for (final code in known) {
    if (raw.contains(code)) return code;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'runtime_error_unknown';
  return trimmed;
}
