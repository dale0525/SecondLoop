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
  test('isAvailable requires Update.exe and current sq.version', () async {
    final root = await Directory.systemTemp.createTemp('velopack_available_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');

    final missingMarkerClient = VelopackUpdateClient(
      updateExecutablePath: updater.path,
    );

    expect(missingMarkerClient.isAvailable(), isFalse);

    _writeSqVersion(root, '1.0.0');
    final readyClient =
        VelopackUpdateClient(updateExecutablePath: updater.path);
    expect(readyClient.isAvailable(), isTrue);
  });

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

  test('stageAsset downloads package into local packages directory', () async {
    final root = await Directory.systemTemp.createTemp('velopack_stage_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    final sourceDir = Directory('${root.path}${Platform.pathSeparator}source')
      ..createSync(recursive: true);
    final sourcePackage = File(
      '${sourceDir.path}${Platform.pathSeparator}com.secondloop.secondloop-1.2.0-full.nupkg',
    )..writeAsStringSync('nupkg-content');

    var runnerCalls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processRunner: (executable, arguments) async {
        runnerCalls += 1;
        return ProcessResult(123, 0, '', '');
      },
    );

    await client.stageAsset(sourcePackage.uri);

    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.2.0-full.nupkg',
    );
    expect(stagedPackage.existsSync(), isTrue);
    expect(stagedPackage.readAsStringSync(), 'nupkg-content');
    expect(runnerCalls, 0);
  });

  test('installAssetAndRestart starts detached apply command', () async {
    final root = await Directory.systemTemp.createTemp('velopack_install_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    final sourceDir = Directory('${root.path}${Platform.pathSeparator}source')
      ..createSync(recursive: true);
    final sourcePackage = File(
      '${sourceDir.path}${Platform.pathSeparator}com.secondloop.secondloop-2.0.0-full.nupkg',
    )..writeAsStringSync('nupkg-content');

    var starterCalls = 0;
    late String startedExecutable;
    late List<String> startedArgs;
    late ProcessStartMode startedMode;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        starterCalls += 1;
        startedExecutable = executable;
        startedArgs = arguments;
        startedMode = mode;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await client.installAssetAndRestart(
      sourcePackage.uri,
      waitPid: 4321,
    );

    expect(starterCalls, 1);
    expect(startedExecutable, updater.path);
    expect(startedMode, ProcessStartMode.detached);
    expect(startedArgs[0], 'apply');
    expect(startedArgs, containsAllInOrder(['--waitPid', '4321']));
    expect(startedArgs, contains('--package'));
    final packageIndex = startedArgs.indexOf('--package');
    expect(packageIndex, greaterThanOrEqualTo(0));
    final packagePath = startedArgs[packageIndex + 1];
    final stagedPackage = File(packagePath);
    expect(stagedPackage.existsSync(), isTrue);
    expect(stagedPackage.readAsStringSync(), 'nupkg-content');
  });

  test(
      'applyPendingOnStartup deletes staged package when updater exits non-zero',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.1-full.nupkg');
    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.0.1-full.nupkg',
    );

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processRunner: (executable, arguments) async {
        return ProcessResult(456, 1, '', 'apply_failed');
      },
    );

    await expectLater(
      client.applyPendingOnStartup(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('windows_velopack_apply_failed_'),
        ),
      ),
    );
    expect(stagedPackage.existsSync(), isFalse);
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
