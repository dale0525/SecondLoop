import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/desktop_ocr_runtime.dart';

void main() {
  test('desktop runtime health transitions after repair and clear', () async {
    if (!supportsDesktopManagedOcrRuntime()) return;

    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_runtime_health_test_',
    );
    try {
      final initial = await readDesktopRuntimeHealth(
        appDirProvider: () async => appDir.path,
      );
      expect(initial.supported, isTrue);
      expect(initial.installed, isFalse);

      final repaired = await repairDesktopRuntimeInstall(
        appDirProvider: () async => appDir.path,
      );
      expect(repaired.supported, isTrue);
      expect(repaired.installed, isTrue);
      expect(repaired.runtimeDirPath, isNotNull);

      await clearDesktopRuntimeInstall(
        appDirProvider: () async => appDir.path,
      );
      final cleared = await readDesktopRuntimeHealth(
        appDirProvider: () async => appDir.path,
      );
      expect(cleared.installed, isFalse);
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}
