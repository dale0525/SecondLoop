import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/desktop_ocr_runtime.dart';

void main() {
  test('resolveManagedDesktopOcrPythonExecutable returns null when missing',
      () async {
    if (!supportsDesktopManagedOcrRuntime()) return;

    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_ocr_runtime_missing_test_',
    );
    try {
      final resolved = await resolveManagedDesktopOcrPythonExecutable(
        appDirProvider: () async => appDir.path,
      );
      expect(resolved, isNull);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('resolveManagedDesktopOcrPythonExecutable prefers bundled runtime',
      () async {
    if (!supportsDesktopManagedOcrRuntime()) return;

    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_desktop_ocr_runtime_present_test_',
    );
    try {
      final candidate = Platform.isWindows
          ? File('${appDir.path}/ocr/desktop/runtime/python/python.exe')
          : File('${appDir.path}/ocr/desktop/runtime/python/bin/python3');
      await candidate.parent.create(recursive: true);
      await candidate.writeAsString('stub', flush: true);

      final resolved = await resolveManagedDesktopOcrPythonExecutable(
        appDirProvider: () async => appDir.path,
      );
      expect(resolved, candidate.path);
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}
