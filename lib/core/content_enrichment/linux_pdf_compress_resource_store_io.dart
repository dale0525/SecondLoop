import 'dart:convert';
import 'dart:io';

import '../backend/native_app_dir.dart';
import 'linux_pdf_compress_resource_script.dart';
import 'linux_pdf_compress_resource_store.dart';

const List<String> _kRequiredResourceFiles = <String>[
  'pdf_scan_compress_bridge.py',
  '_secondloop_manifest.json',
];

typedef LinuxPdfCompressResourceInstaller = Future<void> Function(
  String resourceDirPath,
);

LinuxPdfCompressResourceStore createLinuxPdfCompressResourceStore({
  Future<String> Function()? appDirProvider,
}) {
  return FileSystemLinuxPdfCompressResourceStore(
    appDirProvider: appDirProvider ?? getNativeAppDir,
  );
}

final class FileSystemLinuxPdfCompressResourceStore
    implements LinuxPdfCompressResourceStore {
  const FileSystemLinuxPdfCompressResourceStore({
    required this.appDirProvider,
    this.isLinux = _isLinuxPlatform,
    this.installResources,
  });

  final Future<String> Function() appDirProvider;
  final bool Function() isLinux;
  final LinuxPdfCompressResourceInstaller? installResources;

  @override
  Future<LinuxPdfCompressResourceStatus> readStatus() async {
    if (!isLinux()) {
      return const LinuxPdfCompressResourceStatus(
        supported: false,
        installed: false,
        resourceDirPath: null,
        fileCount: 0,
        totalBytes: 0,
        source: LinuxPdfCompressResourceSource.none,
      );
    }

    final resourceDir = await _resourceDir();
    if (!await resourceDir.exists()) {
      return const LinuxPdfCompressResourceStatus(
        supported: true,
        installed: false,
        resourceDirPath: null,
        fileCount: 0,
        totalBytes: 0,
        source: LinuxPdfCompressResourceSource.none,
      );
    }

    var fileCount = 0;
    var totalBytes = 0;
    for (final fileName in _kRequiredResourceFiles) {
      final file = File('${resourceDir.path}/$fileName');
      if (!await file.exists()) continue;
      fileCount += 1;
      final stat = await file.stat();
      totalBytes += stat.size;
    }

    final installed = fileCount == _kRequiredResourceFiles.length;
    return LinuxPdfCompressResourceStatus(
      supported: true,
      installed: installed,
      resourceDirPath: installed ? resourceDir.path : null,
      fileCount: fileCount,
      totalBytes: totalBytes,
      source: installed
          ? LinuxPdfCompressResourceSource.downloaded
          : LinuxPdfCompressResourceSource.none,
    );
  }

  @override
  Future<LinuxPdfCompressResourceStatus> downloadResources() async {
    if (!isLinux()) {
      throw StateError('linux_pdf_compress_resources_not_supported');
    }

    final resourceDir = await _resourceDir();
    if (await resourceDir.exists()) {
      await resourceDir.delete(recursive: true);
    }
    await resourceDir.create(recursive: true);

    final installer = installResources;
    if (installer != null) {
      await installer(resourceDir.path);
      final manifestFile =
          File('${resourceDir.path}/_secondloop_manifest.json');
      if (!await manifestFile.exists()) {
        await _writeManifest(resourceDir);
      }
    } else {
      await _installDefaultResources(resourceDir);
    }

    return readStatus();
  }

  @override
  Future<LinuxPdfCompressResourceStatus> deleteResources() async {
    if (!isLinux()) {
      throw StateError('linux_pdf_compress_resources_not_supported');
    }

    final resourceDir = await _resourceDir();
    if (await resourceDir.exists()) {
      await resourceDir.delete(recursive: true);
    }
    return readStatus();
  }

  @override
  Future<String?> readInstalledResourceDir() async {
    final status = await readStatus();
    return status.installed ? status.resourceDirPath : null;
  }

  Future<Directory> _resourceDir() async {
    final appDir = await appDirProvider();
    return Directory('$appDir/pdf_compress/linux/resources');
  }

  Future<void> _installDefaultResources(Directory resourceDir) async {
    final bridge = File('${resourceDir.path}/pdf_scan_compress_bridge.py');
    await bridge.writeAsString(
      kLinuxPdfCompressBridgeScript,
      flush: true,
    );
    await _writeManifest(resourceDir);
  }

  Future<void> _writeManifest(Directory resourceDir) async {
    final manifest = File('${resourceDir.path}/_secondloop_manifest.json');
    final payload = <String, Object?>{
      'resource': 'linux_pdf_compress',
      'version': 'v1',
      'downloaded_at_utc': DateTime.now().toUtc().toIso8601String(),
      'files': _kRequiredResourceFiles,
    };
    await manifest.writeAsString(jsonEncode(payload), flush: true);
  }
}

bool _isLinuxPlatform() => Platform.isLinux;
