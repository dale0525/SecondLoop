import 'linux_pdf_compress_resource_store_stub.dart'
    if (dart.library.io) 'linux_pdf_compress_resource_store_io.dart' as impl;

enum LinuxPdfCompressResourceSource {
  none,
  downloaded,
}

final class LinuxPdfCompressResourceStatus {
  const LinuxPdfCompressResourceStatus({
    required this.supported,
    required this.installed,
    required this.resourceDirPath,
    required this.fileCount,
    required this.totalBytes,
    required this.source,
    this.message,
  });

  final bool supported;
  final bool installed;
  final String? resourceDirPath;
  final int fileCount;
  final int totalBytes;
  final LinuxPdfCompressResourceSource source;
  final String? message;
}

abstract class LinuxPdfCompressResourceStore {
  Future<LinuxPdfCompressResourceStatus> readStatus();
  Future<LinuxPdfCompressResourceStatus> downloadResources();
  Future<LinuxPdfCompressResourceStatus> deleteResources();
  Future<String?> readInstalledResourceDir();
}

LinuxPdfCompressResourceStore createLinuxPdfCompressResourceStore({
  Future<String> Function()? appDirProvider,
}) {
  return impl.createLinuxPdfCompressResourceStore(
    appDirProvider: appDirProvider,
  );
}
