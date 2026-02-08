import 'desktop_ocr_runtime.dart';
import 'linux_pdf_compress_resource_store.dart';

LinuxPdfCompressResourceStore createLinuxPdfCompressResourceStore({
  Future<String> Function()? appDirProvider,
}) {
  return FileSystemLinuxPdfCompressResourceStore(
    appDirProvider: appDirProvider,
  );
}

final class FileSystemLinuxPdfCompressResourceStore
    implements LinuxPdfCompressResourceStore {
  const FileSystemLinuxPdfCompressResourceStore({
    this.appDirProvider,
  });

  final Future<String> Function()? appDirProvider;

  @override
  Future<LinuxPdfCompressResourceStatus> readStatus() async {
    final health =
        await readDesktopRuntimeHealth(appDirProvider: appDirProvider);
    if (!health.supported) {
      return const LinuxPdfCompressResourceStatus(
        supported: false,
        installed: false,
        resourceDirPath: null,
        fileCount: 0,
        totalBytes: 0,
        source: LinuxPdfCompressResourceSource.none,
      );
    }

    return LinuxPdfCompressResourceStatus(
      supported: true,
      installed: health.installed,
      resourceDirPath: health.runtimeDirPath,
      fileCount: health.fileCount,
      totalBytes: health.totalBytes,
      source: health.installed
          ? LinuxPdfCompressResourceSource.downloaded
          : LinuxPdfCompressResourceSource.none,
      message: health.message,
    );
  }

  @override
  Future<LinuxPdfCompressResourceStatus> downloadResources() async {
    await repairDesktopRuntimeInstall(appDirProvider: appDirProvider);
    return readStatus();
  }

  @override
  Future<LinuxPdfCompressResourceStatus> deleteResources() async {
    await clearDesktopRuntimeInstall(appDirProvider: appDirProvider);
    return readStatus();
  }

  @override
  Future<String?> readInstalledResourceDir() async {
    final status = await readStatus();
    return status.installed ? status.resourceDirPath : null;
  }
}
