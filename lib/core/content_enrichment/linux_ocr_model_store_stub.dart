import 'linux_ocr_model_store.dart';

LinuxOcrModelStore createLinuxOcrModelStore({
  Future<String> Function()? appDirProvider,
}) {
  return const _UnsupportedLinuxOcrModelStore();
}

final class _UnsupportedLinuxOcrModelStore implements LinuxOcrModelStore {
  const _UnsupportedLinuxOcrModelStore();

  @override
  Future<LinuxOcrModelStatus> readStatus() async {
    return const LinuxOcrModelStatus(
      supported: false,
      installed: false,
      modelDirPath: null,
      modelCount: 0,
      totalBytes: 0,
      source: LinuxOcrModelSource.none,
    );
  }

  @override
  Future<LinuxOcrModelStatus> downloadModels() async {
    throw StateError('linux_ocr_models_not_supported');
  }

  @override
  Future<LinuxOcrModelStatus> deleteModels() async {
    throw StateError('linux_ocr_models_not_supported');
  }

  @override
  Future<String?> readInstalledModelDir() async => null;
}
