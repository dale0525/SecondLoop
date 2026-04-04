import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/macos/macos_update_client.dart';

void main() {
  test('resolveManagedAppBundlePath supports /Applications install', () {
    final resolved =
        DefaultMacosManagedUpdateClient.resolveManagedAppBundlePath(
      executablePath: '/Applications/SecondLoop.app/Contents/MacOS/SecondLoop',
      environment: const {'HOME': '/Users/tester'},
    );

    expect(resolved, '/Applications/SecondLoop.app');
  });

  test('resolveManagedAppBundlePath supports ~/Applications install', () {
    final resolved =
        DefaultMacosManagedUpdateClient.resolveManagedAppBundlePath(
      executablePath:
          '/Users/tester/Applications/SecondLoop.app/Contents/MacOS/SecondLoop',
      environment: const {'HOME': '/Users/tester'},
    );

    expect(resolved, '/Users/tester/Applications/SecondLoop.app');
  });

  test('resolveManagedAppBundlePath rejects unsupported install path', () {
    final resolved =
        DefaultMacosManagedUpdateClient.resolveManagedAppBundlePath(
      executablePath:
          '/Users/tester/Downloads/SecondLoop.app/Contents/MacOS/SecondLoop',
      environment: const {'HOME': '/Users/tester'},
    );

    expect(resolved, isNull);
  });

  test('cleans temp directory when detached launcher throws', () async {
    final tempDir = await Directory.systemTemp.createTemp('macos_update_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final archiveFile = await _createMacosArchive(tempDir);
    String? capturedScriptPath;

    final client = DefaultMacosManagedUpdateClient(
      executablePath: '/Applications/SecondLoop.app/Contents/MacOS/SecondLoop',
      environment: const {'HOME': '/Users/tester'},
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        capturedScriptPath = arguments.single;
        throw StateError('launcher_failed');
      },
    );

    await expectLater(
      () => client.installArchiveAndRestart(archiveFile.uri, waitPid: 4321),
      throwsStateError,
    );

    expect(capturedScriptPath, isNotNull);
    expect(
      Directory(File(capturedScriptPath!).parent.path).existsSync(),
      isFalse,
    );
  });

  test('cleans temp directory when remote archive fetch times out', () async {
    final beforeDirs = _listMacosUpdateTempDirs();
    final stalledRequest = Completer<HttpClientRequest>();
    final client = DefaultMacosManagedUpdateClient(
      executablePath: '/Applications/SecondLoop.app/Contents/MacOS/SecondLoop',
      environment: const {'HOME': '/Users/tester'},
      httpClientFactory: () => _FakeHttpClient(
        onGetUrl: (_) => stalledRequest.future,
      ),
      networkTimeoutOverride: const Duration(milliseconds: 10),
    );

    await expectLater(
      () => client.installArchiveAndRestart(
        Uri.parse('https://cdn.example.com/SecondLoop-macos-v1.2.3.app.tar.gz'),
        waitPid: 4321,
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(_listMacosUpdateTempDirs(), beforeDirs);
  });

  test('installArchiveAndRestart writes rollback-capable updater script',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('macos_update_test_');
    addTearDown(() => tempDir.delete(recursive: true));

    final archiveFile = await _createMacosArchive(tempDir);
    String? capturedExecutable;
    List<String>? capturedArguments;

    final client = DefaultMacosManagedUpdateClient(
      executablePath: '/Applications/SecondLoop.app/Contents/MacOS/SecondLoop',
      environment: const {'HOME': '/Users/tester'},
      processStarter: (executable, arguments,
          {mode = ProcessStartMode.normal}) async {
        capturedExecutable = executable;
        capturedArguments = arguments;
        if (Platform.isWindows) {
          return Process.start('cmd', const ['/c', 'exit', '0']);
        }
        return Process.start('/usr/bin/true', const []);
      },
    );

    await client.installArchiveAndRestart(archiveFile.uri, waitPid: 4321);

    expect(capturedExecutable, '/bin/sh');
    expect(capturedArguments, isNotNull);
    final scriptPath = capturedArguments!.single;
    final scriptDir = Directory(File(scriptPath).parent.path);
    final scriptText = await File(scriptPath).readAsString();
    expect(scriptText, contains('APP_PID=4321'));
    expect(scriptText, contains('MAX_WAIT=60'));
    expect(scriptText, contains('process_start_time()'));
    expect(scriptText, contains('copy_app_bundle()'));
    expect(scriptText, contains('capture_initial_process_start_time()'));
    expect(
      scriptText,
      contains('if kill -0 "\$APP_PID" 2>/dev/null; then'),
    );
    expect(scriptText, contains('APP_START=""'));
    expect(
      scriptText,
      contains(r'if APP_START=$(capture_initial_process_start_time); then'),
    );
    expect(
      scriptText,
      contains(r'if [ "$capture_status" -eq 1 ]; then'),
    );
    expect(
      scriptText,
      contains(r'current_start=$(process_start_time "$APP_PID")'),
    );
    expect(scriptText, contains(r'PS_BIN="${PS_BIN:-/bin/ps}"'));
    expect(scriptText, contains(r'DITTO_BIN="${DITTO_BIN:-/usr/bin/ditto}"'));
    expect(scriptText, contains(r'XATTR_BIN="${XATTR_BIN:-/usr/bin/xattr}"'));
    expect(scriptText, contains(r'OPEN_BIN="${OPEN_BIN:-/usr/bin/open}"'));
    expect(scriptText, contains('INITIAL_START_MAX_RETRIES='));
    expect(scriptText, contains('INITIAL_START_RETRY_DELAY='));
    expect(
      scriptText,
      contains(r'if [ -z "$current_start" ]; then'),
    );
    expect(
      scriptText,
      contains(r'return 0'),
    );
    expect(scriptText, contains(r'waited=$((waited + 1))'));
    expect(scriptText, contains('mv "\$TARGET_APP" "\$BACKUP_APP"'));
    expect(scriptText, contains('copy_app_bundle'));
    expect(scriptText, isNot(contains('command -v ditto')));
    expect(scriptText,
        isNot(contains('cp -R "\$REPLACEMENT_APP" "\$TARGET_APP"')));
    expect(scriptText, contains(r'"$XATTR_BIN" -dr com.apple.quarantine'));
    expect(scriptText, contains(r'"$OPEN_BIN" -a "$TARGET_APP"'));
    expect(
      scriptText,
      contains('mv "\$TARGET_APP" "\$TARGET_APP.failed" 2>/dev/null || true'),
    );
    expect(scriptText, contains('mv "\$BACKUP_APP" "\$TARGET_APP" || {'));
    expect(scriptText, contains('rm -rf "\$TARGET_APP.failed" || true'));
    expect(scriptText, contains('rm -rf "\$TEMP_ROOT" || true'));
    expect(scriptText, contains('rm -rf "\$BACKUP_APP" "\$TEMP_ROOT" || true'));
    expect(scriptText, contains('same_process_running()'));
    expect(scriptText, contains('if same_process_running; then'));
    expect(
      File('${scriptDir.path}/SecondLoop-macos-v1.2.3.app.tar.gz').existsSync(),
      isFalse,
    );
  });

  test(
    'updater script retries initial ps start-time lookup before installing',
    () async {
      final tempDir =
          await Directory.systemTemp.createTemp('macos_update_script_');
      addTearDown(() => tempDir.delete(recursive: true));

      final homeDir = Directory('${tempDir.path}/home');
      final appBundle =
          Directory('${homeDir.path}/Applications/SecondLoop.app');
      final currentExecutable = File(
        '${appBundle.path}/Contents/MacOS/SecondLoop',
      );
      final currentMarker = File(
        '${appBundle.path}/Contents/Resources/version.txt',
      );
      await currentExecutable.parent.create(recursive: true);
      await currentExecutable.writeAsString('#!/bin/sh\nexit 0\n');
      final currentMode =
          await Process.run('chmod', ['+x', currentExecutable.path]);
      if (currentMode.exitCode != 0) {
        throw StateError('chmod_failed_${currentMode.stderr}');
      }
      await currentMarker.parent.create(recursive: true);
      await currentMarker.writeAsString('old');

      final archiveFile = await _createMacosArchive(
        tempDir,
        markerText: 'new',
      );
      String? capturedScriptPath;

      final client = DefaultMacosManagedUpdateClient(
        executablePath: currentExecutable.path,
        environment: {'HOME': homeDir.path},
        processStarter: (executable, arguments,
            {mode = ProcessStartMode.normal}) async {
          capturedScriptPath = arguments.single;
          return Process.start('/usr/bin/true', const []);
        },
      );

      final waitedProcess = await Process.start(
        '/bin/sh',
        ['-c', 'sleep 1'],
      );
      addTearDown(() async {
        waitedProcess.kill();
        await waitedProcess.exitCode.catchError((_) => -1);
      });

      await client.installArchiveAndRestart(
        archiveFile.uri,
        waitPid: waitedProcess.pid,
      );

      final scriptPath = capturedScriptPath;
      expect(scriptPath, isNotNull);
      final tempRoot = Directory(File(scriptPath!).parent.path);
      final psCountFile = File('${tempDir.path}/ps-count.txt');
      final fakePs = await _writeExecutableScript(
        tempDir,
        'fake-ps.sh',
        '''
#!/bin/sh
count_file='${psCountFile.path}'
count=0
if [ -f "\$count_file" ]; then
  count=\$(cat "\$count_file")
fi
count=\$((count + 1))
printf '%s' "\$count" >"\$count_file"
if [ "\$count" -le 2 ]; then
  exit 0
fi
printf '%s\\n' 'Sat Apr  5 00:00:00 2026'
''',
      );
      final fakeDitto = await _writeExecutableScript(
        tempDir,
        'fake-ditto.sh',
        '''
#!/bin/sh
src=\$1
dst=\$2
cp -R "\$src" "\$dst"
''',
      );
      final fakeOpen = await _writeExecutableScript(
        tempDir,
        'fake-open.sh',
        '#!/bin/sh\nexit 0\n',
      );
      final fakeXattr = await _writeExecutableScript(
        tempDir,
        'fake-xattr.sh',
        '#!/bin/sh\nexit 0\n',
      );

      final result = await Process.run(
        '/bin/bash',
        [scriptPath],
        environment: {
          'PS_BIN': fakePs.path,
          'DITTO_BIN': fakeDitto.path,
          'OPEN_BIN': fakeOpen.path,
          'XATTR_BIN': fakeXattr.path,
          'INITIAL_START_MAX_RETRIES': '3',
          'INITIAL_START_RETRY_DELAY': '0',
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(await currentMarker.readAsString(), 'new');
      expect(await psCountFile.readAsString(), isNot('1'));
      expect(
          int.parse(await psCountFile.readAsString()), greaterThanOrEqualTo(3));
      expect(Directory('${appBundle.path}.backup').existsSync(), isFalse);
      expect(Directory('${appBundle.path}.failed').existsSync(), isFalse);
      expect(tempRoot.existsSync(), isFalse);
    },
  );

  test(
    'updater script installs successfully when invoked via /bin/sh',
    () async {
      final tempDir =
          await Directory.systemTemp.createTemp('macos_update_script_');
      addTearDown(() => tempDir.delete(recursive: true));

      final homeDir = Directory('${tempDir.path}/home');
      final appBundle =
          Directory('${homeDir.path}/Applications/SecondLoop.app');
      final currentExecutable = File(
        '${appBundle.path}/Contents/MacOS/SecondLoop',
      );
      final currentMarker = File(
        '${appBundle.path}/Contents/Resources/version.txt',
      );
      await currentExecutable.parent.create(recursive: true);
      await currentExecutable.writeAsString('#!/bin/sh\nexit 0\n');
      final currentMode =
          await Process.run('chmod', ['+x', currentExecutable.path]);
      if (currentMode.exitCode != 0) {
        throw StateError('chmod_failed_${currentMode.stderr}');
      }
      await currentMarker.parent.create(recursive: true);
      await currentMarker.writeAsString('old');

      final archiveFile = await _createMacosArchive(
        tempDir,
        markerText: 'new',
      );
      String? capturedScriptPath;

      final client = DefaultMacosManagedUpdateClient(
        executablePath: currentExecutable.path,
        environment: {'HOME': homeDir.path},
        processStarter: (executable, arguments,
            {mode = ProcessStartMode.normal}) async {
          capturedScriptPath = arguments.single;
          return Process.start('/usr/bin/true', const []);
        },
      );

      await client.installArchiveAndRestart(archiveFile.uri, waitPid: 999999);

      final scriptPath = capturedScriptPath;
      expect(scriptPath, isNotNull);
      final tempRoot = Directory(File(scriptPath!).parent.path);

      final result = await Process.run('/bin/sh', [scriptPath]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(await currentMarker.readAsString(), 'new');
      expect(Directory('${appBundle.path}.backup').existsSync(), isFalse);
      expect(Directory('${appBundle.path}.failed').existsSync(), isFalse);
      expect(tempRoot.existsSync(), isFalse);
    },
  );

  test(
    'updater script still installs when waited pid is already gone',
    () async {
      final tempDir =
          await Directory.systemTemp.createTemp('macos_update_script_');
      addTearDown(() => tempDir.delete(recursive: true));

      final homeDir = Directory('${tempDir.path}/home');
      final appBundle =
          Directory('${homeDir.path}/Applications/SecondLoop.app');
      final currentExecutable = File(
        '${appBundle.path}/Contents/MacOS/SecondLoop',
      );
      final currentMarker = File(
        '${appBundle.path}/Contents/Resources/version.txt',
      );
      await currentExecutable.parent.create(recursive: true);
      await currentExecutable.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', ['+x', currentExecutable.path]);
      await currentMarker.parent.create(recursive: true);
      await currentMarker.writeAsString('old');

      final archiveFile = await _createMacosArchive(
        tempDir,
        markerText: 'new',
      );
      String? capturedScriptPath;

      final client = DefaultMacosManagedUpdateClient(
        executablePath: currentExecutable.path,
        environment: {'HOME': homeDir.path},
        processStarter: (executable, arguments,
            {mode = ProcessStartMode.normal}) async {
          capturedScriptPath = arguments.single;
          return Process.start('/usr/bin/true', const []);
        },
      );

      await client.installArchiveAndRestart(archiveFile.uri, waitPid: 999999);

      final scriptPath = capturedScriptPath;
      expect(scriptPath, isNotNull);
      final tempRoot = Directory(File(scriptPath!).parent.path);

      final result = await Process.run('/bin/bash', [scriptPath]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(await currentMarker.readAsString(), 'new');
      expect(Directory('${appBundle.path}.backup').existsSync(), isFalse);
      expect(Directory('${appBundle.path}.failed').existsSync(), isFalse);
      expect(tempRoot.existsSync(), isFalse);
    },
  );

  test(
    'updater script fails after exhausting initial ps start-time retries',
    () async {
      final tempDir =
          await Directory.systemTemp.createTemp('macos_update_script_');
      addTearDown(() => tempDir.delete(recursive: true));

      final homeDir = Directory('${tempDir.path}/home');
      final appBundle =
          Directory('${homeDir.path}/Applications/SecondLoop.app');
      final currentExecutable = File(
        '${appBundle.path}/Contents/MacOS/SecondLoop',
      );
      final currentMarker = File(
        '${appBundle.path}/Contents/Resources/version.txt',
      );
      await currentExecutable.parent.create(recursive: true);
      await currentExecutable.writeAsString('#!/bin/sh\nexit 0\n');
      final currentMode =
          await Process.run('chmod', ['+x', currentExecutable.path]);
      if (currentMode.exitCode != 0) {
        throw StateError('chmod_failed_${currentMode.stderr}');
      }
      await currentMarker.parent.create(recursive: true);
      await currentMarker.writeAsString('old');

      final archiveFile = await _createMacosArchive(
        tempDir,
        markerText: 'new',
      );
      String? capturedScriptPath;

      final client = DefaultMacosManagedUpdateClient(
        executablePath: currentExecutable.path,
        environment: {'HOME': homeDir.path},
        processStarter: (executable, arguments,
            {mode = ProcessStartMode.normal}) async {
          capturedScriptPath = arguments.single;
          return Process.start('/usr/bin/true', const []);
        },
      );

      final waitedProcess = await Process.start(
        '/bin/sh',
        ['-c', 'sleep 5'],
      );
      addTearDown(() async {
        waitedProcess.kill();
        await waitedProcess.exitCode.catchError((_) => -1);
      });

      await client.installArchiveAndRestart(
        archiveFile.uri,
        waitPid: waitedProcess.pid,
      );

      final scriptPath = capturedScriptPath;
      expect(scriptPath, isNotNull);
      final tempRoot = Directory(File(scriptPath!).parent.path);
      final psCountFile = File('${tempDir.path}/ps-fail-count.txt');
      final fakePs = await _writeExecutableScript(
        tempDir,
        'fake-ps-empty.sh',
        '''
#!/bin/sh
count_file='${psCountFile.path}'
count=0
if [ -f "\$count_file" ]; then
  count=\$(cat "\$count_file")
fi
count=\$((count + 1))
printf '%s' "\$count" >"\$count_file"
exit 0
''',
      );
      final fakeDitto = await _writeExecutableScript(
        tempDir,
        'fake-ditto.sh',
        '''
#!/bin/sh
src=\$1
dst=\$2
cp -R "\$src" "\$dst"
''',
      );
      final fakeOpen = await _writeExecutableScript(
        tempDir,
        'fake-open.sh',
        '#!/bin/sh\nexit 0\n',
      );
      final fakeXattr = await _writeExecutableScript(
        tempDir,
        'fake-xattr.sh',
        '#!/bin/sh\nexit 0\n',
      );

      final result = await Process.run(
        '/bin/bash',
        [scriptPath],
        environment: {
          'PS_BIN': fakePs.path,
          'DITTO_BIN': fakeDitto.path,
          'OPEN_BIN': fakeOpen.path,
          'XATTR_BIN': fakeXattr.path,
          'INITIAL_START_MAX_RETRIES': '2',
          'INITIAL_START_RETRY_DELAY': '0',
        },
      );

      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(await currentMarker.readAsString(), 'old');
      expect(await psCountFile.readAsString(), '2');
      expect(Directory('${appBundle.path}.backup').existsSync(), isFalse);
      expect(Directory('${appBundle.path}.failed').existsSync(), isFalse);
      expect(tempRoot.existsSync(), isFalse);
    },
  );
}

Set<String> _listMacosUpdateTempDirs() {
  return Directory.systemTemp
      .listSync()
      .whereType<Directory>()
      .map((dir) => dir.path)
      .where((path) => path.split(Platform.pathSeparator).last.startsWith(
            'secondloop_macos_update_',
          ))
      .toSet();
}

Future<File> _createMacosArchive(
  Directory tempDir, {
  String markerText = 'binary',
}) async {
  final sourceRoot = Directory('${tempDir.path}/source');
  final executable = File(
    '${sourceRoot.path}/SecondLoop.app/Contents/MacOS/SecondLoop',
  );
  final markerFile = File(
    '${sourceRoot.path}/SecondLoop.app/Contents/Resources/version.txt',
  );
  await executable.parent.create(recursive: true);
  await executable.writeAsString('#!/bin/sh\nexit 0\n');
  await markerFile.parent.create(recursive: true);
  await markerFile.writeAsString(markerText);
  final modeResult = await Process.run('chmod', ['+x', executable.path]);
  if (modeResult.exitCode != 0) {
    throw StateError('chmod_failed_${modeResult.stderr}');
  }

  final archiveFile =
      File('${tempDir.path}/SecondLoop-macos-v1.2.3.app.tar.gz');
  final result = await Process.run(
    'tar',
    [
      '--format=ustar',
      '-C',
      sourceRoot.path,
      '-czf',
      archiveFile.path,
      'SecondLoop.app'
    ],
  );
  if (result.exitCode != 0) {
    throw StateError('tar_failed_${result.stderr}');
  }
  return archiveFile;
}

Future<File> _writeExecutableScript(
  Directory tempDir,
  String name,
  String content,
) async {
  final file = File('${tempDir.path}/$name');
  await file.writeAsString(content);
  final modeResult = await Process.run('chmod', ['+x', file.path]);
  if (modeResult.exitCode != 0) {
    throw StateError('chmod_failed_${modeResult.stderr}');
  }
  return file;
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({required this.onGetUrl});

  final Future<HttpClientRequest> Function(Uri uri) onGetUrl;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => onGetUrl(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
