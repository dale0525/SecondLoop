import 'linux_pdf_compress_resource_store.dart';

LinuxPdfCompressResourceStore createLinuxPdfCompressResourceStore({
  Future<String> Function()? appDirProvider,
}) {
  return const _UnsupportedLinuxPdfCompressResourceStore();
}

final class _UnsupportedLinuxPdfCompressResourceStore
    implements LinuxPdfCompressResourceStore {
  const _UnsupportedLinuxPdfCompressResourceStore();

  @override
  Future<LinuxPdfCompressResourceStatus> readStatus() async {
    return const LinuxPdfCompressResourceStatus(
      supported: false,
      installed: false,
      resourceDirPath: null,
      fileCount: 0,
      totalBytes: 0,
      source: LinuxPdfCompressResourceSource.none,
    );
  }

  @override
  Future<LinuxPdfCompressResourceStatus> downloadResources() async {
    throw StateError('linux_pdf_compress_resources_not_supported');
  }

  @override
  Future<LinuxPdfCompressResourceStatus> deleteResources() async {
    throw StateError('linux_pdf_compress_resources_not_supported');
  }

  @override
  Future<String?> readInstalledResourceDir() async => null;
}
