import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/update/windows/velopack_paths.dart';
import 'package:secondloop/core/update/windows/velopack_update_client.dart';

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
      () => client.stageAsset(Uri.parse('https://cdn.example.com/win.msi')),
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
}
