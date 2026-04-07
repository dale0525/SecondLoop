import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/prepare_desktop_runtime.dart' as runtime;

void main() {
  test('pubspec includes desktop runtime asset directories for recursive files',
      () async {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);

    final content = await pubspec.readAsString();
    expect(content, contains('- assets/ocr/desktop_runtime/'));
    expect(content, contains('- assets/ocr/desktop_runtime/models/'));
    expect(content, contains('- assets/ocr/desktop_runtime/onnxruntime/'));
    expect(content, contains('- assets/ocr/desktop_runtime/whisper/'));
  });

  test('desktop runtime asset skeleton placeholders exist in repo', () {
    expect(File('assets/ocr/desktop_runtime/.gitkeep').existsSync(), isTrue);
    expect(
      File('assets/ocr/desktop_runtime/models/.gitkeep').existsSync(),
      isTrue,
    );
    expect(
      File('assets/ocr/desktop_runtime/onnxruntime/.gitkeep').existsSync(),
      isTrue,
    );
    expect(
      File('assets/ocr/desktop_runtime/whisper/.gitkeep').existsSync(),
      isTrue,
    );
  });

  test('runtime output replacement retries transient Windows file locks',
      () async {
    final outputDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_output_',
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_temp_',
    );
    final sourceFile =
        File('${tempDir.path}${Platform.pathSeparator}runtime.txt')
          ..writeAsStringSync('ready');

    var deleteAttempts = 0;
    var renameAttempts = 0;

    try {
      await runtime.replaceRuntimeOutputDirectoryForTest(
        outputDir: outputDir,
        tempDir: tempDir,
        deleteOutputDir: (directory) async {
          deleteAttempts += 1;
          if (deleteAttempts == 1) {
            throw PathAccessException(
              directory.path,
              const OSError(
                'The process cannot access the file because it is being used by another process.',
                32,
              ),
            );
          }
          await directory.delete(recursive: true);
        },
        renameTempDir: (directory, newPath) async {
          renameAttempts += 1;
          if (renameAttempts == 1) {
            throw PathAccessException(
              directory.path,
              const OSError('Access is denied.', 5),
            );
          }
          await directory.rename(newPath);
        },
      );

      expect(deleteAttempts, 2);
      expect(renameAttempts, 2);
      expect(Directory(outputDir.path).existsSync(), isTrue);
      expect(
          File('${outputDir.path}${Platform.pathSeparator}runtime.txt')
              .existsSync(),
          isTrue);
      expect(sourceFile.existsSync(), isFalse);
    } finally {
      if (Directory(outputDir.path).existsSync()) {
        await Directory(outputDir.path).delete(recursive: true);
      }
      if (Directory(tempDir.path).existsSync()) {
        await Directory(tempDir.path).delete(recursive: true);
      }
    }
  });

  test(
      'runtime output replacement tolerates extended transient Windows file locks',
      () async {
    final outputDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_output_extended_',
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_temp_extended_',
    );
    final sourceFile =
        File('${tempDir.path}${Platform.pathSeparator}runtime.txt')
          ..writeAsStringSync('ready');

    var renameAttempts = 0;

    try {
      await runtime.replaceRuntimeOutputDirectoryForTest(
        outputDir: outputDir,
        tempDir: tempDir,
        renameTempDir: (directory, newPath) async {
          renameAttempts += 1;
          if (renameAttempts <= 5) {
            throw PathAccessException(
              directory.path,
              const OSError('Access is denied.', 5),
            );
          }
          await directory.rename(newPath);
        },
        delay: (_) async {},
      );

      expect(renameAttempts, 6);
      expect(Directory(outputDir.path).existsSync(), isTrue);
      expect(
        File('${outputDir.path}${Platform.pathSeparator}runtime.txt')
            .readAsStringSync(),
        'ready',
      );
      expect(sourceFile.existsSync(), isFalse);
    } finally {
      if (Directory(outputDir.path).existsSync()) {
        await Directory(outputDir.path).delete(recursive: true);
      }
      if (Directory(tempDir.path).existsSync()) {
        await Directory(tempDir.path).delete(recursive: true);
      }
    }
  });

  test('runtime output replacement restores previous output when promote fails',
      () async {
    final outputDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_output_restore_',
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_temp_restore_',
    );
    final outputFile =
        File('${outputDir.path}${Platform.pathSeparator}runtime.txt')
          ..writeAsStringSync('existing');
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}runtime.txt')
      ..writeAsStringSync('prepared');

    try {
      await expectLater(
        () => runtime.replaceRuntimeOutputDirectoryForTest(
          outputDir: outputDir,
          tempDir: tempDir,
          renameTempDir: (_, __) async {
            throw PathAccessException(
              tempDir.path,
              const OSError('Access is denied.', 5),
            );
          },
        ),
        throwsA(isA<PathAccessException>()),
      );

      expect(Directory(outputDir.path).existsSync(), isTrue);
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.readAsStringSync(), 'existing');
      expect(Directory(tempDir.path).existsSync(), isTrue);
      expect(tempFile.existsSync(), isTrue);
      expect(tempFile.readAsStringSync(), 'prepared');
    } finally {
      if (Directory(outputDir.path).existsSync()) {
        await Directory(outputDir.path).delete(recursive: true);
      }
      if (Directory(tempDir.path).existsSync()) {
        await Directory(tempDir.path).delete(recursive: true);
      }
    }
  });

  test(
      'runtime output replacement keeps promoted output when backup cleanup still fails',
      () async {
    final outputDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_output_cleanup_',
    );
    final tempDir = await Directory.systemTemp.createTemp(
      'desktop_runtime_temp_cleanup_',
    );
    final staleOutputFile =
        File('${outputDir.path}${Platform.pathSeparator}runtime.txt')
          ..writeAsStringSync('existing');
    final promotedFile = File(
      '${tempDir.path}${Platform.pathSeparator}runtime.txt',
    )..writeAsStringSync('prepared');

    var deleteBackupAttempts = 0;
    final backupPaths = <String>[];

    try {
      await runtime.replaceRuntimeOutputDirectoryForTest(
        outputDir: outputDir,
        tempDir: tempDir,
        deleteOutputDir: (directory) async {
          final normalizedPath = directory.path.toLowerCase();
          if (normalizedPath.contains('.backup.')) {
            deleteBackupAttempts += 1;
            backupPaths.add(directory.path);
            throw PathAccessException(
              directory.path,
              const OSError(
                'The process cannot access the file because it is being used by another process.',
                32,
              ),
            );
          }
          await directory.delete(recursive: true);
        },
        delay: (_) async {},
      );

      expect(deleteBackupAttempts, greaterThanOrEqualTo(1));
      expect(Directory(outputDir.path).existsSync(), isTrue);
      expect(staleOutputFile.readAsStringSync(), 'prepared');
      expect(Directory(tempDir.path).existsSync(), isFalse);
      expect(
        File('${outputDir.path}${Platform.pathSeparator}runtime.txt')
            .readAsStringSync(),
        'prepared',
      );
      expect(promotedFile.existsSync(), isFalse);
      expect(
        backupPaths.any((path) => Directory(path).existsSync()),
        isTrue,
      );
    } finally {
      final parent = outputDir.parent;
      final backupDirs = parent.listSync().whereType<Directory>().where(
            (directory) =>
                directory.path.startsWith('${outputDir.path}.backup.'),
          );
      for (final backupDir in backupDirs) {
        if (backupDir.existsSync()) {
          await backupDir.delete(recursive: true);
        }
      }
      if (Directory(outputDir.path).existsSync()) {
        await Directory(outputDir.path).delete(recursive: true);
      }
      if (Directory(tempDir.path).existsSync()) {
        await Directory(tempDir.path).delete(recursive: true);
      }
    }
  });
}
