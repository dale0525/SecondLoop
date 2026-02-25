import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/windows/velopack_paths.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

void _writeSqVersion(Directory root, String version) {
  final currentDir = Directory('${root.path}${Platform.pathSeparator}current')
    ..createSync(recursive: true);
  final sqVersion =
      File('${currentDir.path}${Platform.pathSeparator}sq.version')
        ..writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
<metadata>
<version>$version</version>
</metadata>
</package>
''');
  expect(sqVersion.existsSync(), isTrue);
}

void _createNupkg(Directory root, String fileName) {
  final packagesDir = Directory('${root.path}${Platform.pathSeparator}packages')
    ..createSync(recursive: true);
  final pkgFile = File('${packagesDir.path}${Platform.pathSeparator}$fileName')
    ..writeAsStringSync('stub');
  expect(pkgFile.existsSync(), isTrue);
}

void main() {
  test('resolveVelopackUpdateExePath prefers sibling Update.exe', () async {
    final root = await Directory.systemTemp.createTemp('velopack_paths_');
    final appDir = Directory('${root.path}${Platform.pathSeparator}app')
      ..createSync(recursive: true);
    final appExe = File('${appDir.path}${Platform.pathSeparator}SecondLoop.exe')
      ..writeAsStringSync('stub');
    final siblingUpdater =
        File('${appDir.path}${Platform.pathSeparator}Update.exe')
          ..writeAsStringSync('stub');

    final resolved = resolveVelopackUpdateExePath(executablePath: appExe.path);

    expect(resolved, siblingUpdater.path);
  });

  test('stageAsset throws when updater exits non-zero', () async {
    final root = await Directory.systemTemp.createTemp('velopack_stage_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processRunner: (executable, arguments) async {
        return ProcessResult(123, 1, '', 'boom');
      },
    );

    expect(
      () => client.stageAsset(Uri.parse('https://cdn.example.com/win.nupkg')),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('windows_velopack_stage_failed_'),
        ),
      ),
    );
  });

  test('applyPendingOnStartup throws when updater exits non-zero', () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.1-full.nupkg');

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processRunner: (executable, arguments) async {
        return ProcessResult(456, 1, '', 'apply_failed');
      },
    );

    expect(
      client.applyPendingOnStartup,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('windows_velopack_apply_failed_'),
        ),
      ),
    );
  });

  test('applyPendingOnStartup skips apply when package version equals current',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_skip_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.0-full.nupkg');

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processRunner: (executable, arguments) async {
        calls += 1;
        return ProcessResult(999, 0, '', '');
      },
    );

    await client.applyPendingOnStartup();

    expect(calls, 0);
  });

  test('applyPendingOnStartup runs apply when newer package is present',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_run_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');

    var calls = 0;
    late List<String> actualArgs;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processRunner: (executable, arguments) async {
        calls += 1;
        actualArgs = arguments;
        return ProcessResult(1000, 0, '', '');
      },
    );

    await client.applyPendingOnStartup();

    expect(calls, 1);
    expect(actualArgs, ['apply', '--silent']);
  });
}
