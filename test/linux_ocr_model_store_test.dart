import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/linux_ocr_model_store.dart';
import 'package:secondloop/core/content_enrichment/linux_ocr_model_store_io.dart';

void main() {
  test('linux ocr runtime store repair and clear flow', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_ocr_runtime_store_test_',
    );

    try {
      final store = FileSystemLinuxOcrModelStore(
        appDirProvider: () async => appDir.path,
      );

      final initial = await store.readStatus();
      if (!initial.supported) {
        expect(initial.installed, isFalse);
        return;
      }

      expect(initial.installed, isFalse);

      final installed = await store.downloadModels();
      expect(installed.supported, isTrue);
      expect(installed.installed, isTrue);
      expect(installed.source, LinuxOcrModelSource.downloaded);
      expect(installed.modelDirPath, isNotNull);

      final installedDir = await store.readInstalledModelDir();
      expect(installedDir, isNotNull);
      expect(await Directory(installedDir!).exists(), isTrue);

      final removed = await store.deleteModels();
      expect(removed.supported, isTrue);
      expect(removed.installed, isFalse);
      expect(removed.modelDirPath, isNull);
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}
