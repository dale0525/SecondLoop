import 'desktop_ocr_runtime.dart';
import 'linux_ocr_model_store.dart';

LinuxOcrModelStore createLinuxOcrModelStore({
  Future<String> Function()? appDirProvider,
}) {
  return FileSystemLinuxOcrModelStore(
    appDirProvider: appDirProvider,
  );
}

final class FileSystemLinuxOcrModelStore implements LinuxOcrModelStore {
  const FileSystemLinuxOcrModelStore({
    this.appDirProvider,
  });

  final Future<String> Function()? appDirProvider;

  @override
  Future<LinuxOcrModelStatus> readStatus() async {
    final health =
        await readDesktopRuntimeHealth(appDirProvider: appDirProvider);
    if (!health.supported) {
      return const LinuxOcrModelStatus(
        supported: false,
        installed: false,
        modelDirPath: null,
        modelCount: 0,
        totalBytes: 0,
        source: LinuxOcrModelSource.none,
      );
    }

    return LinuxOcrModelStatus(
      supported: true,
      installed: health.installed,
      modelDirPath: health.runtimeDirPath,
      modelCount: health.fileCount,
      totalBytes: health.totalBytes,
      source: health.installed
          ? LinuxOcrModelSource.downloaded
          : LinuxOcrModelSource.none,
      message: health.message,
    );
  }

  @override
  Future<LinuxOcrModelStatus> downloadModels() async {
    await repairDesktopRuntimeInstall(appDirProvider: appDirProvider);
    return readStatus();
  }

  @override
  Future<LinuxOcrModelStatus> deleteModels() async {
    await clearDesktopRuntimeInstall(appDirProvider: appDirProvider);
    return readStatus();
  }

  @override
  Future<String?> readInstalledModelDir() async {
    final status = await readStatus();
    return status.installed ? status.modelDirPath : null;
  }
}
