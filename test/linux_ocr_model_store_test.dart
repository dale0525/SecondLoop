import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/content_enrichment/linux_ocr_model_store_io.dart';

const List<String> _kExpectedModelFiles = <String>[
  'ch_PP-OCRv4_det_infer.onnx',
  'ch_ppocr_mobile_v2.0_cls_infer.onnx',
  'ch_PP-OCRv4_rec_infer.onnx',
  'latin_PP-OCRv3_rec_infer.onnx',
  'latin_dict.txt',
  'arabic_PP-OCRv3_rec_infer.onnx',
  'arabic_dict.txt',
  'cyrillic_PP-OCRv3_rec_infer.onnx',
  'cyrillic_dict.txt',
  'devanagari_PP-OCRv3_rec_infer.onnx',
  'devanagari_dict.txt',
  'japan_PP-OCRv3_rec_infer.onnx',
  'japan_dict.txt',
  'korean_PP-OCRv3_rec_infer.onnx',
  'korean_dict.txt',
  'chinese_cht_PP-OCRv3_rec_infer.onnx',
  'chinese_cht_dict.txt',
];

void main() {
  test('download models installs managed runtime when python is unavailable',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_ocr_runtime_install_test_',
    );

    var managedRuntimeInstalled = false;

    try {
      final wheelBytes = _buildRapidOcrWheel();
      final servedWheel = File('${appDir.path}/rapidocr_test.whl');
      await servedWheel.writeAsBytes(wheelBytes, flush: true);

      final store = _buildStore(
        appDir: appDir,
        servedWheel: servedWheel,
        wheelBytes: wheelBytes,
        managedRuntimeInstaller: ({
          required Directory runtimeDir,
          required bool pythonAvailableAtDownload,
        }) async {
          managedRuntimeInstalled = true;
          await _writeMinimalRuntime(runtimeDir);
        },
      );

      final status = await store.downloadModels();
      expect(status.supported, isTrue);
      expect(status.installed, isTrue);
      expect(managedRuntimeInstalled, isTrue);
      expect(status.modelCount, _kExpectedModelFiles.length);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('download models succeeds even when python is unavailable', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_ocr_model_test_',
    );

    try {
      final wheelBytes = _buildRapidOcrWheel();
      final servedWheel = File('${appDir.path}/rapidocr_test.whl');
      await servedWheel.writeAsBytes(wheelBytes, flush: true);

      final store = _buildStore(
        appDir: appDir,
        servedWheel: servedWheel,
        wheelBytes: wheelBytes,
        managedRuntimeInstaller: ({
          required Directory runtimeDir,
          required bool pythonAvailableAtDownload,
        }) async {
          await _writeMinimalRuntime(runtimeDir);
        },
      );

      final status = await store.downloadModels();
      expect(status.supported, isTrue);
      expect(status.installed, isTrue);
      expect(status.modelCount, _kExpectedModelFiles.length);

      final modelDir = Directory('${appDir.path}/ocr/desktop/models');
      expect(await modelDir.exists(), isTrue);
      expect(await File('${modelDir.path}/ch_PP-OCRv4_det_infer.onnx').exists(),
          isTrue);
      expect(
          await File('${modelDir.path}/latin_PP-OCRv3_rec_infer.onnx').exists(),
          isTrue);
      expect(await File('${modelDir.path}/latin_dict.txt').exists(), isTrue);
      expect(
          await File('${modelDir.path}/arabic_PP-OCRv3_rec_infer.onnx')
              .exists(),
          isTrue);
      expect(
          await File('${modelDir.path}/japan_PP-OCRv3_rec_infer.onnx').exists(),
          isTrue);
      expect(
          await File('${modelDir.path}/chinese_cht_dict.txt').exists(), isTrue);

      final manifest = File('${modelDir.path}/_secondloop_manifest.json');
      expect(await manifest.exists(), isTrue);
      final decoded = jsonDecode(await manifest.readAsString()) as Map;
      expect(decoded['python_available_at_download'], isFalse);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('download models keeps files when runtime install is blocked', () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_ocr_runtime_blocked_test_',
    );

    try {
      final wheelBytes = _buildRapidOcrWheel();
      final servedWheel = File('${appDir.path}/rapidocr_test.whl');
      await servedWheel.writeAsBytes(wheelBytes, flush: true);

      final store = _buildStore(
        appDir: appDir,
        servedWheel: servedWheel,
        wheelBytes: wheelBytes,
        managedRuntimeInstaller: ({
          required Directory runtimeDir,
          required bool pythonAvailableAtDownload,
        }) async {
          throw StateError('linux_ocr_runtime_exec_not_permitted');
        },
      );

      final status = await store.downloadModels();
      expect(status.supported, isTrue);
      expect(status.installed, isFalse);
      expect(status.modelCount, _kExpectedModelFiles.length);
      expect(
        status.message,
        'runtime_missing:linux_ocr_runtime_exec_not_permitted',
      );

      final modelDir = Directory('${appDir.path}/ocr/desktop/models');
      expect(await modelDir.exists(), isTrue);
      expect(await File('${modelDir.path}/ch_PP-OCRv4_det_infer.onnx').exists(),
          isTrue);
      expect(
          await File('${modelDir.path}/latin_PP-OCRv3_rec_infer.onnx').exists(),
          isTrue);
      expect(await File('${modelDir.path}/latin_dict.txt').exists(), isTrue);
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('readStatus exposes runtime install error detail from model manifest',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_ocr_runtime_error_status_test_',
    );
    try {
      final modelDir = Directory('${appDir.path}/ocr/desktop/models');
      await modelDir.create(recursive: true);
      await _writeAllExpectedModelFiles(modelDir);
      await File('${modelDir.path}/_secondloop_manifest.json').writeAsString(
        jsonEncode(<String, Object?>{
          'runtime_install_error': 'linux_ocr_runtime_exec_not_permitted',
        }),
        flush: true,
      );

      final store = FileSystemLinuxOcrModelStore(
        appDirProvider: () async => appDir.path,
        supportsDesktopOcrModels: () => true,
      );

      final status = await store.readStatus();
      expect(status.installed, isFalse);
      expect(status.modelCount, _kExpectedModelFiles.length);
      expect(
        status.message,
        'runtime_missing:linux_ocr_runtime_exec_not_permitted',
      );
    } finally {
      await appDir.delete(recursive: true);
    }
  });

  test('readStatus recovers from stale runtime_packages_invalid state',
      () async {
    final appDir = await Directory.systemTemp.createTemp(
      'secondloop_linux_ocr_runtime_recover_status_test_',
    );
    try {
      final modelDir = Directory('${appDir.path}/ocr/desktop/models');
      await modelDir.create(recursive: true);
      await _writeAllExpectedModelFiles(modelDir);
      final modelManifest = File('${modelDir.path}/_secondloop_manifest.json');
      await modelManifest.writeAsString(
        jsonEncode(<String, Object?>{
          'runtime_install_error': 'linux_ocr_runtime_packages_invalid',
        }),
        flush: true,
      );

      final runtimeDir = Directory('${appDir.path}/ocr/desktop/runtime');
      final python = File('${runtimeDir.path}/python/bin/python3.11');
      await python.parent.create(recursive: true);
      await python.writeAsString(
        '#!/bin/sh\n'
        'if [ "\$1" = "--version" ]; then\n'
        '  echo "Python 3.11.0"\n'
        '  exit 0\n'
        'fi\n'
        'exit 0\n',
        flush: true,
      );
      if (!Platform.isWindows) {
        await Process.run('chmod', <String>['755', python.path]);
      }
      await Directory(
        '${runtimeDir.path}/python/lib/python3.11/site-packages/rapidocr_onnxruntime',
      ).create(recursive: true);

      final store = FileSystemLinuxOcrModelStore(
        appDirProvider: () async => appDir.path,
        supportsDesktopOcrModels: () => true,
      );

      final status = await store.readStatus();
      expect(status.installed, isTrue);
      expect(status.message, isNull);
      expect(
        await File(
          '${runtimeDir.path}/_secondloop_runtime_manifest.json',
        ).exists(),
        isTrue,
      );
      final updatedManifest = jsonDecode(await modelManifest.readAsString());
      expect(
        (updatedManifest as Map<String, Object?>)
            .containsKey('runtime_install_error'),
        isFalse,
      );
    } finally {
      await appDir.delete(recursive: true);
    }
  });
}

FileSystemLinuxOcrModelStore _buildStore({
  required Directory appDir,
  required File servedWheel,
  required List<int> wheelBytes,
  required Future<void> Function({
    required Directory runtimeDir,
    required bool pythonAvailableAtDownload,
  }) managedRuntimeInstaller,
}) {
  return FileSystemLinuxOcrModelStore(
    appDirProvider: () async => appDir.path,
    pypiJsonUrl: 'https://unit-test.invalid/pypi.json',
    supportsDesktopOcrModels: () => true,
    pythonExecutableResolver: () async => null,
    downloadJson: (_) async => <String, Object?>{
      'info': <String, Object?>{'version': '0.0.0-test'},
      'urls': <Object?>[
        <String, Object?>{
          'packagetype': 'bdist_wheel',
          'filename': 'rapidocr_onnxruntime-0.0.0-py3-none-any.whl',
          'url': servedWheel.uri.toString(),
        },
      ],
    },
    downloadFile: (uri, outFile) async {
      if (uri.toString() == servedWheel.uri.toString()) {
        await outFile.writeAsBytes(wheelBytes, flush: true);
        return;
      }
      if (outFile.path.toLowerCase().endsWith('.txt')) {
        await outFile.writeAsString('a\nb\nc\n', flush: true);
      } else {
        await outFile.writeAsBytes(const <int>[9, 8, 7, 6], flush: true);
      }
    },
    managedRuntimeInstaller: managedRuntimeInstaller,
  );
}

Future<void> _writeMinimalRuntime(Directory runtimeDir) async {
  final python = File('${runtimeDir.path}/python/bin/python3');
  await python.parent.create(recursive: true);
  await python.writeAsString('#!/bin/sh\necho Python 3.11\n', flush: true);
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['755', python.path]);
  }
  final packageDir = Directory(
    '${runtimeDir.path}/python/lib/python3.11/site-packages/rapidocr_onnxruntime',
  );
  await packageDir.create(recursive: true);
  await runtimeDir.create(recursive: true);
  await File('${runtimeDir.path}/_secondloop_runtime_manifest.json')
      .writeAsString('{}', flush: true);
}

Future<void> _writeAllExpectedModelFiles(Directory modelDir) async {
  for (final name in _kExpectedModelFiles) {
    final file = File('${modelDir.path}/$name');
    if (name.toLowerCase().endsWith('.txt')) {
      await file.writeAsString('x\ny\n', flush: true);
    } else {
      await file.writeAsBytes(const <int>[1, 2, 3], flush: true);
    }
  }
}

List<int> _buildRapidOcrWheel() {
  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes(
      'rapidocr_onnxruntime/models/ch_PP-OCRv4_det_infer.onnx',
      const <int>[1, 2, 3],
    ),
  );
  archive.addFile(
    ArchiveFile.bytes(
      'rapidocr_onnxruntime/models/ch_ppocr_mobile_v2.0_cls_infer.onnx',
      const <int>[4, 5, 6],
    ),
  );
  archive.addFile(
    ArchiveFile.bytes(
      'rapidocr_onnxruntime/models/ch_PP-OCRv4_rec_infer.onnx',
      const <int>[7, 8, 9],
    ),
  );

  return ZipEncoder().encode(archive);
}
