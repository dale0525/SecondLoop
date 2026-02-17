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
      expect(initial.whisperBaseModelInstalled, isFalse);

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
      expect(cleared.whisperBaseModelInstalled, isFalse);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('desktop runtime health detects whisper base model payload', () async {
    if (!supportsDesktopManagedOcrRuntime()) return;

    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_runtime_whisper_payload_test_',
    );
    try {
      final runtimeDir = Directory('${appDir.path}/ocr/desktop/runtime');
      final modelsDir = Directory('${runtimeDir.path}/models');
      final onnxDir = Directory('${runtimeDir.path}/onnxruntime');
      final whisperDir = Directory('${runtimeDir.path}/whisper');
      await modelsDir.create(recursive: true);
      await onnxDir.create(recursive: true);
      await whisperDir.create(recursive: true);

      await File(
        '${runtimeDir.path}/_secondloop_desktop_runtime_manifest.json',
      ).writeAsString('{"runtime":"desktop_media"}', flush: true);
      await File('${modelsDir.path}/ch_PP-OCRv5_mobile_det.onnx')
          .writeAsBytes(const <int>[1], flush: true);
      await File('${modelsDir.path}/ch_ppocr_mobile_v2.0_cls_infer.onnx')
          .writeAsBytes(const <int>[1], flush: true);
      await File('${modelsDir.path}/ch_PP-OCRv5_mobile_rec.onnx')
          .writeAsBytes(const <int>[1], flush: true);
      await File('${onnxDir.path}/onnxruntime.dll')
          .writeAsBytes(const <int>[1], flush: true);
      await File('${whisperDir.path}/ggml-base.bin')
          .writeAsBytes(const <int>[1], flush: true);

      final health = await readDesktopRuntimeHealth(
        appDirProvider: () async => appDir.path,
      );
      expect(health.supported, isTrue);
      expect(health.installed, isTrue);
      expect(health.whisperBaseModelInstalled, isTrue);
      expect(health.message, isNull);
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
