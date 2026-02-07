import 'linux_ocr_model_store_stub.dart'
    if (dart.library.io) 'linux_ocr_model_store_io.dart' as impl;

enum LinuxOcrModelSource {
  none,
  downloaded,
}

final class LinuxOcrModelStatus {
  const LinuxOcrModelStatus({
    required this.supported,
    required this.installed,
    required this.modelDirPath,
    required this.modelCount,
    required this.totalBytes,
    required this.source,
    this.message,
  });

  final bool supported;
  final bool installed;
  final String? modelDirPath;
  final int modelCount;
  final int totalBytes;
  final LinuxOcrModelSource source;
  final String? message;
}

abstract class LinuxOcrModelStore {
  Future<LinuxOcrModelStatus> readStatus();
  Future<LinuxOcrModelStatus> downloadModels();
  Future<LinuxOcrModelStatus> deleteModels();
  Future<String?> readInstalledModelDir();
}

LinuxOcrModelStore createLinuxOcrModelStore({
  Future<String> Function()? appDirProvider,
}) {
  return impl.createLinuxOcrModelStore(
    appDirProvider: appDirProvider,
  );
}
