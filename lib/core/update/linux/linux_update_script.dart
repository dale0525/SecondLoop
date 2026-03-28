String buildLinuxUpdaterScript({
  required int pid,
  required String appDirPath,
  required String executablePath,
  required String sourceDirPath,
  required String tempRootPath,
}) {
  return _buildLinuxUpdaterScriptImpl(
    pid: pid,
    appDirPath: appDirPath,
    executablePath: executablePath,
    sourceDirPath: sourceDirPath,
    tempRootPath: tempRootPath,
  );
}

String buildLinuxUpdaterScriptForTest({
  required int pid,
  required String appDirPath,
  required String executablePath,
  required String sourceDirPath,
  required String tempRootPath,
}) {
  return _buildLinuxUpdaterScriptImpl(
    pid: pid,
    appDirPath: appDirPath,
    executablePath: executablePath,
    sourceDirPath: sourceDirPath,
    tempRootPath: tempRootPath,
  );
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _buildLinuxUpdaterScriptImpl({
  required int pid,
  required String appDirPath,
  required String executablePath,
  required String sourceDirPath,
  required String tempRootPath,
}) {
  final safePid = pid.toString();
  final appDir = _shellQuote(appDirPath);
  final executable = _shellQuote(executablePath);
  final sourceDir = _shellQuote(sourceDirPath);
  final tempRoot = _shellQuote(tempRootPath);

  return '''#!/usr/bin/env bash
set -euo pipefail
APP_PID=$safePid
APP_DIR=$appDir
EXE_PATH=$executable
SOURCE_DIR=$sourceDir
TEMP_ROOT=$tempRoot
APP_PARENT=\$(dirname "\$APP_DIR")
BACKUP_DIR="\$APP_PARENT/.secondloop-update-backup.\$APP_PID"
STAGED_DIR="\$APP_PARENT/.secondloop-update-stage.\$APP_PID"
MAX_WAIT=60
waited=0
APP_START=\$(/bin/ps -o lstart= -p "\$APP_PID" 2>/dev/null | sed 's/^ *//')

cleanup() {
  rm -rf "\$STAGED_DIR" "\$TEMP_ROOT" || true
}

restore_backup() {
  if [ -d "\$BACKUP_DIR" ]; then
    mv "\$APP_DIR" "\$APP_DIR.failed" 2>/dev/null || true
    mv "\$BACKUP_DIR" "\$APP_DIR" || {
      rm -rf "\$TEMP_ROOT" || true
      exit 1
    }
    rm -rf "\$APP_DIR.failed" || true
  fi
}

on_error() {
  restore_backup
  cleanup
}

trap on_error EXIT

while kill -0 "\$APP_PID" 2>/dev/null && [ "\$waited" -lt "\$MAX_WAIT" ]; do
  CURRENT_START=\$(/bin/ps -o lstart= -p "\$APP_PID" 2>/dev/null | sed 's/^ *//')
  if [ -n "\$APP_START" ] && [ "\$CURRENT_START" != "\$APP_START" ]; then
    break
  fi
  sleep 1
  waited=\$((waited + 1))
done

if kill -0 "\$APP_PID" 2>/dev/null; then
  exit 1
fi

rm -rf "\$STAGED_DIR" "\$BACKUP_DIR"
mkdir -p "\$STAGED_DIR"
cp -a "\$SOURCE_DIR"/. "\$STAGED_DIR"/
mv "\$APP_DIR" "\$BACKUP_DIR"
mv "\$STAGED_DIR" "\$APP_DIR"
rm -rf "\$BACKUP_DIR" || true
chmod +x "\$EXE_PATH" || true
nohup "\$EXE_PATH" >/dev/null 2>&1 &
trap - EXIT
cleanup
''';
}
