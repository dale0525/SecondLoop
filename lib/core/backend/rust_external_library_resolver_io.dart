import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

const String _kRustLibraryFileName = 'secondloop_rust.dll';

ExternalLibrary? resolveDesktopRustExternalLibrary() {
  if (kIsWeb) {
    return null;
  }

  final resolvedPath = resolveRustLibraryPathForTest(
    isWindows: Platform.isWindows,
    resolvedExecutable: Platform.resolvedExecutable,
    siblingExists: _siblingRustLibraryExists(Platform.resolvedExecutable),
  );
  if (resolvedPath == null) {
    return null;
  }

  return ExternalLibrary.open(
    resolvedPath,
    debugInfo: ' (resolved from executable directory)',
  );
}

String? resolveRustLibraryPathForTest({
  required bool isWindows,
  required String resolvedExecutable,
  required bool siblingExists,
}) {
  if (!isWindows || resolvedExecutable.trim().isEmpty || !siblingExists) {
    return null;
  }

  return _resolveSiblingPath(
    executablePath: resolvedExecutable,
    siblingFileName: _kRustLibraryFileName,
  );
}

bool _siblingRustLibraryExists(String resolvedExecutable) {
  final siblingPath = _resolveSiblingPath(
    executablePath: resolvedExecutable,
    siblingFileName: _kRustLibraryFileName,
  );
  if (siblingPath == null) {
    return false;
  }

  return File(siblingPath).existsSync();
}

String? _resolveSiblingPath({
  required String executablePath,
  required String siblingFileName,
}) {
  final trimmed = executablePath.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final slashIndex = trimmed.lastIndexOf('/');
  final backslashIndex = trimmed.lastIndexOf(r'\');
  final separatorIndex =
      slashIndex > backslashIndex ? slashIndex : backslashIndex;
  if (separatorIndex < 0) {
    return null;
  }

  final directoryPath = trimmed.substring(0, separatorIndex);
  final separator = backslashIndex >= slashIndex ? r'\' : '/';
  return '$directoryPath$separator$siblingFileName';
}
