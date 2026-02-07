import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/linux_pdf_compress_resource_store.dart';
import 'package:secondloop/core/content_enrichment/linux_pdf_compress_resource_store_io.dart';

void main() {
  test('linux pdf compression resource status transitions as expected',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_pdf_compress_test_',
    );

    try {
      final store = FileSystemLinuxPdfCompressResourceStore(
        appDirProvider: () async => appDir.path,
        isLinux: () => true,
        installResources: (resourceDirPath) async {
          final bridge = File('$resourceDirPath/pdf_scan_compress_bridge.py');
          await bridge.writeAsString('#!/usr/bin/env python3\nprint("ok")\n');
        },
      );

      final initial = await store.readStatus();
      expect(initial.supported, isTrue);
      expect(initial.installed, isFalse);
      expect(initial.fileCount, 0);

      final installed = await store.downloadResources();
      expect(installed.supported, isTrue);
      expect(installed.installed, isTrue);
      expect(installed.fileCount, 2);
      expect(installed.totalBytes, greaterThan(0));
      expect(
        installed.source,
        LinuxPdfCompressResourceSource.downloaded,
      );

      final installedPath = await store.readInstalledResourceDir();
      expect(installedPath, isNotNull);
      expect(await Directory(installedPath!).exists(), isTrue);

      final removed = await store.deleteResources();
      expect(removed.supported, isTrue);
      expect(removed.installed, isFalse);
      expect(removed.fileCount, 0);
      expect(removed.resourceDirPath, isNull);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('non-linux store reports unsupported', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_pdf_compress_unsupported_',
    );

    try {
      final store = FileSystemLinuxPdfCompressResourceStore(
        appDirProvider: () async => appDir.path,
        isLinux: () => false,
      );

      final status = await store.readStatus();
      expect(status.supported, isFalse);
      expect(status.installed, isFalse);
      expect(status.fileCount, 0);
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}
