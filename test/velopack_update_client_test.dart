import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/app_update_models.dart';
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

File _pendingApplyAttemptMarker(Directory root) => File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}.secondloop_pending_apply',
    );

void main() {
  test('interprets mismatched Windows process path as not running', () {
    final status = interpretWindowsProcessQueryResult(
      exitCode: 0,
      stdoutText: 'C:/Windows/System32/notepad.exe\tNOTEPAD.EXE',
      expectedExecutablePath:
          'C:/Users/test/AppData/Local/SecondLoop/Update.exe',
    );

    expect(status, VelopackProcessProbeStatus.notRunning);
  });

  test('interprets matching Windows process path as expected updater', () {
    final status = interpretWindowsProcessQueryResult(
      exitCode: 0,
      stdoutText:
          'C:/Users/test/AppData/Local/SecondLoop/Update.exe\tUpdate.exe',
      expectedExecutablePath:
          'C:/Users/test/AppData/Local/SecondLoop/Update.exe',
    );

    expect(status, VelopackProcessProbeStatus.runningExpectedProcess);
  });

  test('treats process-name-only probe results as unknown', () {
    final status = interpretWindowsProcessQueryResult(
      exitCode: 0,
      stdoutText: '\tUpdate.exe',
      expectedExecutablePath:
          'C:/Users/test/AppData/Local/SecondLoop/Update.exe',
    );

    expect(status, VelopackProcessProbeStatus.unknown);
  });

  test('builds Windows process probe command with target pid', () {
    final arguments = buildWindowsProcessProbeCommandArguments(4321);

    expect(arguments, hasLength(3));
    expect(arguments[0], '-NoProfile');
    expect(arguments[1], '-Command');
    expect(arguments[2], contains('Get-CimInstance Win32_Process'));
    expect(arguments[2], contains('ProcessId = 4321'));
  });

  test('probes Windows updater status via injected async process runner',
      () async {
    final calls = <String>[];
    final status = await probeWindowsProcessStatusForTest(
      4321,
      expectedExecutablePath:
          'C:/Users/test/AppData/Local/SecondLoop/Update.exe',
      processRunner: (executable, arguments) async {
        calls.add('$executable ${arguments.join(' ')}');
        return ProcessResult(
          4321,
          0,
          'C:/Users/test/AppData/Local/SecondLoop/Update.exe\tUpdate.exe',
          '',
        );
      },
    );

    expect(status, VelopackProcessProbeStatus.runningExpectedProcess);
    expect(calls, hasLength(1));
    expect(calls.single, contains('powershell.exe'));
    expect(calls.single, contains('ProcessId = 4321'));
  });

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

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
    );

    await client.stageAsset(sourcePackage.uri);

    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.2.0-full.nupkg',
    );
    expect(stagedPackage.existsSync(), isTrue);
    expect(stagedPackage.readAsStringSync(), 'nupkg-content');
  });

  test(
      'stageAsset preserves existing package when source already matches target',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_stage_same_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.2.0-full.nupkg',
    )
      ..createSync(recursive: true)
      ..writeAsStringSync('nupkg-content');

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
    );

    await client.stageAsset(stagedPackage.uri);

    expect(stagedPackage.existsSync(), isTrue);
    expect(stagedPackage.readAsStringSync(), 'nupkg-content');
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
    expect(startedArgs, contains('--restart'));
    expect(startedArgs, containsAllInOrder(['--waitPid', '4321']));
    expect(startedArgs, contains('--package'));
    final packageIndex = startedArgs.indexOf('--package');
    expect(packageIndex, greaterThanOrEqualTo(0));
    final packagePath = startedArgs[packageIndex + 1];
    final stagedPackage = File(packagePath);
    expect(stagedPackage.existsSync(), isTrue);
    expect(stagedPackage.readAsStringSync(), 'nupkg-content');
  });

  test('applyPendingOnStartup throws when updater launch fails', () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.1-full.nupkg');

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        throw ProcessException(executable, arguments, 'apply_failed', 1);
      },
    );

    await expectLater(
      client.applyPendingOnStartup(waitPid: 456),
      throwsA(
        isA<ProcessException>().having(
            (error) => error.message, 'message', contains('apply_failed')),
      ),
    );
  });

  test('applyPendingOnStartup skips retry while detached apply is still recent',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_stale_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.1-full.nupkg');
    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.0.1-full.nupkg',
    );

    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.0.1\n${DateTime.now().toUtc().toIso8601String()}\n$pid',
    );

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processProbe: (pid, {required expectedExecutablePath}) async =>
          VelopackProcessProbeStatus.runningExpectedProcess,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final applied = await client.applyPendingOnStartup(waitPid: 789);

    expect(calls, 0);
    expect(applied.status, PendingUpdateStartupStatus.inProgress);
    expect(stagedPackage.existsSync(), isTrue);
    expect(_pendingApplyAttemptMarker(root).existsSync(), isTrue);
  });

  test('applyPendingAndRestart rejects duplicate detached apply while recent',
      () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_apply_manual_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.1-full.nupkg');
    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.0.1-full.nupkg',
    );

    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.0.1\n${DateTime.now().toUtc().toIso8601String()}\n$pid',
    );

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processProbe: (pid, {required expectedExecutablePath}) async =>
          VelopackProcessProbeStatus.runningExpectedProcess,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await expectLater(
      client.applyPendingAndRestart(waitPid: 789),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('apply_already_in_progress'),
        ),
      ),
    );

    expect(calls, 0);
    expect(stagedPackage.existsSync(), isTrue);
    expect(_pendingApplyAttemptMarker(root).existsSync(), isTrue);
  });

  test(
      'applyPendingOnStartup clears stale pending package after detached apply grace period expires',
      () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_apply_expired_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.0.1-full.nupkg');
    final stagedPackage = File(
      '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.0.1-full.nupkg',
    );

    var fakeNow = DateTime.utc(2026, 3, 27, 10, 0, 0);
    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      now: () => fakeNow,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await client.applyPendingOnStartup(waitPid: 456);
    fakeNow = fakeNow.add(const Duration(minutes: 6));

    await expectLater(
      client.applyPendingOnStartup(waitPid: 789),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('previous_apply_failed'),
        ),
      ),
    );

    expect(calls, 1);
    expect(stagedPackage.existsSync(), isFalse);
    expect(_pendingApplyAttemptMarker(root).existsSync(), isFalse);
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
      processProbe: (pid, {required expectedExecutablePath}) async =>
          VelopackProcessProbeStatus.unknown,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 999);

    expect(calls, 0);
    expect(result.status, PendingUpdateStartupStatus.none);
  });

  test(
      'applyPendingOnStartup treats recent marker with dead pid as previous apply failure',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_retry_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');
    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.1.0\n${DateTime.now().toUtc().toIso8601String()}\n999999',
    );

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await expectLater(
      client.applyPendingOnStartup(waitPid: 1234),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('windows_velopack_previous_apply_failed_1.1.0'),
        ),
      ),
    );
    expect(_pendingApplyAttemptMarker(root).existsSync(), isFalse);
    expect(
      File(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.1.0-full.nupkg',
      ).existsSync(),
      isFalse,
    );
  });

  test(
      'recent dead-pid cleanup removes only failed target package and preserves unrelated packages',
      () async {
    final root = await Directory.systemTemp
        .createTemp('velopack_recent_dead_pid_scope_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');
    _createNupkg(root, 'otherapp-9.9.9-full.nupkg');
    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.1.0\n${DateTime.now().toUtc().toIso8601String()}\n999999',
    );

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await expectLater(
      client.applyPendingOnStartup(waitPid: 1234),
      throwsA(isA<StateError>()),
    );

    expect(
      File(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.1.0-full.nupkg',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}otherapp-9.9.9-full.nupkg',
      ).existsSync(),
      isTrue,
    );
  });

  test(
      'expired apply cleanup removes only the failed target package and preserves other pending downloads',
      () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_apply_cleanup_scope_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.2.0-full.nupkg');
    _createNupkg(root, 'com.secondloop.secondloop-1.2.1-full.nupkg');
    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.2.1\n${DateTime.utc(2026, 3, 27, 10, 0, 0).toIso8601String()}\n999999',
    );

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      now: () => DateTime.utc(2026, 3, 27, 10, 6, 0),
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await expectLater(
      client.applyPendingOnStartup(waitPid: 1234),
      throwsA(isA<StateError>()),
    );

    expect(
      File(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.2.1-full.nupkg',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}com.secondloop.secondloop-1.2.0-full.nupkg',
      ).existsSync(),
      isTrue,
    );
  });

  test('pending prerelease package is not newer than installed final release',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_prerelease_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.1.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-rc.1-full.nupkg');

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processProbe: (pid, {required expectedExecutablePath}) async =>
          VelopackProcessProbeStatus.unknown,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 5678);

    expect(calls, 0);
    expect(result.status, PendingUpdateStartupStatus.none);
  });

  test('pending prerelease package is newer than older installed final release',
      () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_prerelease_newer_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.1.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.2.0-rc.1-full.nupkg');

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 6789);

    expect(calls, 1);
    expect(result.status, PendingUpdateStartupStatus.dispatched);
  });

  test('startup treats unverified pending apply process as probe inconclusive',
      () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_probe_unknown_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');

    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.1.0\n${DateTime.now().toUtc().toIso8601String()}\n999999',
    );

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processProbe: (pid, {required expectedExecutablePath}) async =>
          VelopackProcessProbeStatus.unknown,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 2468);

    expect(calls, 0);
    expect(result.status, PendingUpdateStartupStatus.probeInconclusive);
    expect(_pendingApplyAttemptMarker(root).existsSync(), isTrue);
  });

  test('pending apply marker uses normalized version comparison', () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_marker_normalized_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');

    _pendingApplyAttemptMarker(root).writeAsStringSync(
      'v1.1.0\n${DateTime.now().toUtc().toIso8601String()}\n$pid',
    );

    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processProbe: (pid, {required expectedExecutablePath}) async =>
          VelopackProcessProbeStatus.runningExpectedProcess,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 2468);

    expect(result.status, PendingUpdateStartupStatus.inProgress);
    expect(_pendingApplyAttemptMarker(root).existsSync(), isTrue);
  });

  test('applyPendingOnStartup ignores recent marker without updater pid',
      () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_marker_missing_pid_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');
    _pendingApplyAttemptMarker(root).writeAsStringSync(
      '1.1.0\n${DateTime.now().toUtc().toIso8601String()}',
    );

    var calls = 0;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 2468);

    expect(calls, 1);
    expect(result.status, PendingUpdateStartupStatus.dispatched);
    final markerLines = _pendingApplyAttemptMarker(root)
        .readAsStringSync()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    expect(markerLines, hasLength(3));
  });

  test('only SecondLoop full packages count as pending updates', () async {
    final root = await Directory.systemTemp.createTemp('velopack_pkg_filter_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'otherapp-9.9.9-full.nupkg');

    final client = VelopackUpdateClient(updateExecutablePath: updater.path);

    expect(client.hasPendingUpdate(), isFalse);
    expect(client.pendingUpdateVersion(), isNull);
    expect(client.pendingUpdatePackagePath(), isNull);
  });

  test(
      'applyPendingOnStartup starts detached restart flow when newer package is present',
      () async {
    final root = await Directory.systemTemp.createTemp('velopack_apply_run_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');

    var calls = 0;
    late List<String> actualArgs;
    late ProcessStartMode actualMode;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        actualArgs = arguments;
        actualMode = mode;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    final result = await client.applyPendingOnStartup(waitPid: 1000);

    expect(calls, 1);
    expect(result.status, PendingUpdateStartupStatus.dispatched);
    expect(actualMode, ProcessStartMode.detached);
    expect(actualArgs, containsAllInOrder(['apply', '--silent']));
    expect(actualArgs, contains('--restart'));
    expect(actualArgs, containsAllInOrder(['--waitPid', '1000']));
  });

  test('applyPendingAndRestart starts detached restart flow', () async {
    final root =
        await Directory.systemTemp.createTemp('velopack_apply_restart_');
    final updater = File('${root.path}${Platform.pathSeparator}Update.exe')
      ..writeAsStringSync('stub');
    _writeSqVersion(root, '1.0.0');
    _createNupkg(root, 'com.secondloop.secondloop-1.1.0-full.nupkg');

    var calls = 0;
    late List<String> actualArgs;
    late ProcessStartMode actualMode;
    final client = VelopackUpdateClient(
      updateExecutablePath: updater.path,
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        calls += 1;
        actualArgs = arguments;
        actualMode = mode;
        return Process.start(
          Platform.resolvedExecutable,
          const ['--version'],
        );
      },
    );

    await client.applyPendingAndRestart(waitPid: 4321);

    expect(calls, 1);
    expect(actualMode, ProcessStartMode.detached);
    expect(actualArgs, containsAllInOrder(['apply', '--silent']));
    expect(actualArgs, contains('--restart'));
    expect(actualArgs, containsAllInOrder(['--waitPid', '4321']));
  });
}
