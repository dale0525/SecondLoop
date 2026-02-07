import 'dart:convert';
import 'dart:io';

bool isPermissionExecutionError(ProcessException error) {
  final message = error.message.toLowerCase();
  return message.contains('operation not permitted') ||
      message.contains('permission denied') ||
      error.errorCode == 1;
}

Future<void> ensureExecutablePermission(
  String executablePath, {
  required Duration chmodTimeout,
}) async {
  if (Platform.isWindows) return;
  try {
    await Process.run(
      'chmod',
      <String>['755', executablePath],
      runInShell: false,
    ).timeout(chmodTimeout);
  } catch (_) {}
}

Future<ProcessResult> runPythonProcessWithPermissionRetry({
  required String pythonExecutable,
  required List<String> args,
  required Duration timeout,
  required ProcessResult Function() onTimeout,
  required Future<void> Function(String executablePath) clearQuarantineForFile,
  required Future<void> Function(String executablePath) ensurePermission,
  Map<String, String>? environment,
}) async {
  Future<ProcessResult> runOnce() {
    return Process.run(
      pythonExecutable,
      args,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: environment,
    ).timeout(timeout, onTimeout: onTimeout);
  }

  try {
    return await runOnce();
  } on ProcessException catch (error) {
    if (!isPermissionExecutionError(error)) rethrow;
    await clearQuarantineForFile(pythonExecutable);
    await ensurePermission(pythonExecutable);
    try {
      return await runOnce();
    } on ProcessException catch (retryError) {
      if (isPermissionExecutionError(retryError)) {
        throw StateError('linux_ocr_runtime_exec_not_permitted');
      }
      rethrow;
    }
  }
}

Future<ProcessResult> runPipInstallWithRetry({
  required String pythonExecutable,
  required List<String> args,
  required Duration timeout,
  required ProcessResult Function() onTimeout,
  required Future<void> Function(String executablePath) clearQuarantineForFile,
  required Future<void> Function(String executablePath) ensurePermission,
}) {
  return runPythonProcessWithPermissionRetry(
    pythonExecutable: pythonExecutable,
    args: args,
    timeout: timeout,
    onTimeout: onTimeout,
    clearQuarantineForFile: clearQuarantineForFile,
    ensurePermission: ensurePermission,
  );
}

Future<bool> probePythonModules(
  String pythonExecutable, {
  required Duration timeout,
  String? extraPythonPath,
}) async {
  const probe = r'''
import importlib
mods = ["rapidocr_onnxruntime", "pypdfium2", "onnxruntime", "cv2"]
for name in mods:
    importlib.import_module(name)
print("ok")
''';
  try {
    final result = await Process.run(
      pythonExecutable,
      <String>['-c', probe],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: <String, String>{
        'PYTHONUTF8': '1',
        if (extraPythonPath != null && extraPythonPath.trim().isNotEmpty)
          'PYTHONPATH': extraPythonPath.trim(),
      },
    ).timeout(timeout);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
