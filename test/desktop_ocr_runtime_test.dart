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
      if (repaired.installed) {
        expect(repaired.message, isNull);
        expect(repaired.runtimeDirPath, isNotNull);
      } else {
        expect(repaired.message, 'runtime_payload_incomplete');
        expect(repaired.runtimeDirPath, isNull);
      }

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

  test('desktop runtime health requires standard runtime manifest marker',
      () async {
    if (!supportsDesktopManagedOcrRuntime()) return;

    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_runtime_non_standard_manifest_test_',
    );
    try {
      final runtimeDir = Directory('${appDir.path}/ocr/desktop/runtime');
      await runtimeDir.create(recursive: true);
      await File('${runtimeDir.path}/_unrelated_runtime_marker.json')
          .writeAsString('{"runtime":"non_standard"}');
      await File('${runtimeDir.path}/runtime-placeholder.bin')
          .writeAsBytes(const <int>[1, 2, 3], flush: true);

      final health = await readDesktopRuntimeHealth(
        appDirProvider: () async => appDir.path,
      );
      expect(health.supported, isTrue);
      expect(health.installed, isFalse);
      expect(health.message, 'runtime_not_initialized');
      expect(health.runtimeDirPath, isNull);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('desktop runtime health rejects manifest-only install marker', () async {
    if (!supportsDesktopManagedOcrRuntime()) return;

    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_runtime_manifest_only_test_',
    );
    try {
      final runtimeDir = Directory('${appDir.path}/ocr/desktop/runtime');
      await runtimeDir.create(recursive: true);
      await File(
        '${runtimeDir.path}/_secondloop_desktop_runtime_manifest.json',
      ).writeAsString('{"runtime":"desktop_media"}', flush: true);

      final health = await readDesktopRuntimeHealth(
        appDirProvider: () async => appDir.path,
      );
      expect(health.supported, isTrue);
      expect(health.installed, isFalse);
      expect(health.message, 'runtime_payload_incomplete');
      expect(health.runtimeDirPath, isNull);
      expect(health.fileCount, greaterThanOrEqualTo(1));
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}
