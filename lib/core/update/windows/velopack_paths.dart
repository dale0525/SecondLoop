import 'dart:io';

String resolveVelopackUpdateExePath({String? executablePath}) {
  final effectiveExecutablePath = _resolveExecutablePath(executablePath);
  final executable = File(effectiveExecutablePath).absolute;
  final siblingCandidate = File(
    '${executable.parent.path}${Platform.pathSeparator}Update.exe',
  );
  if (siblingCandidate.existsSync()) {
    return siblingCandidate.path;
  }

  final parentCandidate = File(
    '${executable.parent.parent.path}${Platform.pathSeparator}Update.exe',
  );
  if (parentCandidate.existsSync()) {
    return parentCandidate.path;
  }

  return siblingCandidate.path;
}

String _resolveExecutablePath(String? executablePath) {
  final override = executablePath?.trim() ?? '';
  if (override.isNotEmpty) {
    return override;
  }
  return Platform.resolvedExecutable;
}
