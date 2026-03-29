import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/update/app_update_service.dart';

void main() {
  test('buildLinuxUpdaterScriptForTest uses staged swap with rollback', () {
    final script = buildLinuxUpdaterScriptForTest(
      pid: 123,
      appDirPath: '/opt/SecondLoop',
      executablePath: '/opt/SecondLoop/secondloop',
      sourceDirPath: '/tmp/update/payload',
      tempRootPath: '/tmp/update',
    );

    expect(script, contains('BACKUP_DIR='));
    expect(script, contains('STAGED_DIR='));
    expect(script, contains('restore_backup()'));
    expect(script,
        contains('mv "\$APP_DIR" "\$APP_DIR.failed" 2>/dev/null || true'));
    expect(script, contains('mv "\$BACKUP_DIR" "\$APP_DIR" || {'));
    expect(script, contains('rm -rf "\$TEMP_ROOT" || true'));
    expect(script, contains('rm -rf "\$APP_DIR.failed" || true'));
    expect(script, contains('mv "\$APP_DIR" "\$BACKUP_DIR"'));
    expect(script, contains('mv "\$STAGED_DIR" "\$APP_DIR"'));
    expect(script, contains('rm -rf "\$BACKUP_DIR" || true'));
    expect(script, contains('rm -rf "\$STAGED_DIR" "\$TEMP_ROOT" || true'));
    expect(script, contains('same_process_running()'));
    expect(script, contains('if same_process_running; then'));
    expect(script, contains('exit 1'));
  });

  test('sha256FileHexForTest hashes files correctly', () async {
    final tempDir = await Directory.systemTemp.createTemp('update_hash_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File('${tempDir.path}/payload.bin');
    await file.writeAsString('abc');

    expect(
      await sha256FileHexForTest(file),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}
