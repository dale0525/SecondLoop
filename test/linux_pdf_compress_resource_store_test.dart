import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/linux_pdf_compress_resource_store.dart';
import 'package:secondloop/core/content_enrichment/linux_pdf_compress_resource_store_io.dart';

void main() {
  test('linux pdf compression runtime store repair and clear flow', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_pdf_runtime_store_test_',
    );

    try {
      final store = FileSystemLinuxPdfCompressResourceStore(
        appDirProvider: () async => appDir.path,
      );

      final initial = await store.readStatus();
      if (!initial.supported) {
        expect(initial.installed, isFalse);
        return;
      }

      expect(initial.installed, isFalse);

      final installed = await store.downloadResources();
      expect(installed.supported, isTrue);
      expect(installed.installed, isTrue);
      expect(installed.source, LinuxPdfCompressResourceSource.downloaded);

      final installedPath = await store.readInstalledResourceDir();
      expect(installedPath, isNotNull);
      expect(await Directory(installedPath!).exists(), isTrue);

      final removed = await store.deleteResources();
      expect(removed.supported, isTrue);
      expect(removed.installed, isFalse);
      expect(removed.resourceDirPath, isNull);
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}
