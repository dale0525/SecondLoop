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
    expect(
      scriptText,
      contains(r'APP_START=$(/bin/ps -o lstart= -p "$APP_PID"'),
    );
    expect(
      scriptText,
      contains(r'CURRENT_START=$(/bin/ps -o lstart= -p "$APP_PID"'),
    );
    expect(scriptText, contains(r'waited=$((waited + 1))'));
    expect(scriptText, contains('mv "\$TARGET_APP" "\$BACKUP_APP"'));
    expect(scriptText, contains('ditto "\$REPLACEMENT_APP" "\$TARGET_APP"'));
    expect(scriptText, contains('xattr -dr com.apple.quarantine'));
    expect(scriptText, contains('open -a "\$TARGET_APP"'));
    expect(
      scriptText,
      contains('mv "\$TARGET_APP" "\$TARGET_APP.failed" 2>/dev/null || true'),
    );
    expect(scriptText, contains('mv "\$BACKUP_APP" "\$TARGET_APP" || {'));
    expect(scriptText, contains('rm -rf "\$TARGET_APP.failed" || true'));
    expect(scriptText, contains('rm -rf "\$TEMP_ROOT" || true'));
    expect(scriptText, contains('rm -rf "\$BACKUP_APP" "\$TEMP_ROOT" || true'));
    expect(
      File('${scriptDir.path}/SecondLoop-macos-v1.2.3.app.tar.gz').existsSync(),
      isFalse,
    );
  });
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

Future<File> _createMacosArchive(Directory tempDir) async {
  final sourceRoot = Directory('${tempDir.path}/source');
  final executable = File(
    '${sourceRoot.path}/SecondLoop.app/Contents/MacOS/SecondLoop',
  );
  await executable.parent.create(recursive: true);
  await executable.writeAsString('binary');

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
