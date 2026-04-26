import 'dart:async';
import 'dart:io';

typedef WindowsRegistryCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

const _kDefaultWindowsCompanyName = 'com.secondloop';
const _kDefaultWindowsAppId = String.fromEnvironment(
  'SECONDLOOP_APP_ID',
  defaultValue: 'com.secondloop.secondloop',
);
const _kDefaultWindowsAppName = String.fromEnvironment(
  'SECONDLOOP_APP_NAME',
  defaultValue: '',
);

final class WindowsVelopackUninstallCleanupPlan {
  const WindowsVelopackUninstallCleanupPlan({
    required this.directories,
    required this.registryKeys,
  });

  final List<String> directories;
  final List<String> registryKeys;
}

WindowsVelopackUninstallCleanupPlan buildWindowsVelopackUninstallCleanupPlan({
  Map<String, String>? environment,
  String appId = _kDefaultWindowsAppId,
  String productName = '',
  String companyName = _kDefaultWindowsCompanyName,
}) {
  final env = environment ?? Platform.environment;
  final resolvedProductName = _resolveWindowsProductName(
    appId: appId,
    productName: productName,
  );
  final safeCompanyName = _sanitizeWindowsPathComponent(companyName);
  final safeProductName = _sanitizeWindowsPathComponent(resolvedProductName);
  if (safeProductName.isEmpty) {
    return const WindowsVelopackUninstallCleanupPlan(
      directories: [],
      registryKeys: [],
    );
  }
  final relativeAppPath = _joinWindowsPathParts([
    safeCompanyName,
    safeProductName,
  ]);

  final directories = <String>[
    if (_nonEmptyEnv(env, 'APPDATA') case final appData?)
      _joinPath(appData, relativeAppPath),
    if (_nonEmptyEnv(env, 'LOCALAPPDATA') case final localAppData?)
      _joinPath(localAppData, relativeAppPath),
  ];

  return WindowsVelopackUninstallCleanupPlan(
    directories: _dedupe(directories),
    registryKeys: [
      _joinWindowsPathParts([
        'HKCU',
        'Software',
        'SecondLoop',
        safeProductName,
      ]),
    ],
  );
}

Future<void> cleanWindowsVelopackUninstallResidue({
  bool? isWindows,
  Map<String, String>? environment,
  String appId = _kDefaultWindowsAppId,
  String productName = '',
  String companyName = _kDefaultWindowsCompanyName,
  WindowsRegistryCommandRunner? registryCommandRunner,
}) async {
  if (!(isWindows ?? Platform.isWindows)) {
    return;
  }

  final plan = buildWindowsVelopackUninstallCleanupPlan(
    environment: environment,
    appId: appId,
    productName: productName,
    companyName: companyName,
  );
  final protectedDirectoryRoots = <String>[
    if (_nonEmptyEnv(environment ?? Platform.environment, 'APPDATA')
        case final appData?)
      appData,
    if (_nonEmptyEnv(environment ?? Platform.environment, 'LOCALAPPDATA')
        case final localAppData?)
      localAppData,
  ];

  for (final directoryPath in plan.directories) {
    await _removeDirectoryTree(directoryPath);
    await _removeEmptyParentDirectoryIfSafe(
      directoryPath: directoryPath,
      protectedRoots: protectedDirectoryRoots,
    );
  }

  for (final registryKey in plan.registryKeys) {
    await _removeRegistryKey(
      registryKey,
      registryCommandRunner ?? Process.run,
    );
  }
  await _removeRegistryKeyIfEmpty(
    _joinWindowsPathParts(['HKCU', 'Software', 'SecondLoop']),
    registryCommandRunner ?? Process.run,
  );
}

Future<void> cleanCurrentWindowsVelopackUninstallResidue() =>
    cleanWindowsVelopackUninstallResidue();

String _resolveWindowsProductName({
  required String appId,
  required String productName,
}) {
  final configuredProductName = productName.trim();
  if (configuredProductName.isNotEmpty) {
    return configuredProductName;
  }

  if (_kDefaultWindowsAppName.trim().isNotEmpty) {
    return _kDefaultWindowsAppName.trim();
  }

  if (appId.trim().toLowerCase() == 'com.secondloop.secondloopdev') {
    return 'SecondLoop Dev';
  }

  return 'SecondLoop';
}

String? _nonEmptyEnv(Map<String, String> environment, String key) {
  final value = environment[key]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

String _sanitizeWindowsPathComponent(String value) {
  var sanitized = value
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .trimRight()
      .replaceAll(RegExp(r'[.]+$'), '');
  if (sanitized.length > 255) {
    sanitized = sanitized.substring(0, 255);
  }
  return sanitized;
}

Future<void> _removeDirectoryTree(String path) async {
  if (path.trim().isEmpty) {
    return;
  }

  try {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } on FileSystemException {
    return;
  }
}

Future<void> _removeEmptyDirectory(String path) async {
  if (path.trim().isEmpty) {
    return;
  }

  try {
    final directory = Directory(path);
    if (!await directory.exists()) {
      return;
    }
    await directory.delete();
  } on FileSystemException {
    return;
  }
}

Future<void> _removeEmptyParentDirectoryIfSafe({
  required String directoryPath,
  required List<String> protectedRoots,
}) async {
  final parentPath = Directory(directoryPath).parent.path;
  if (_isProtectedDirectoryRoot(parentPath, protectedRoots)) {
    return;
  }
  if (!_isPathUnderAnyRoot(parentPath, protectedRoots)) {
    return;
  }
  await _removeEmptyDirectory(parentPath);
}

bool _isProtectedDirectoryRoot(String path, List<String> protectedRoots) {
  for (final protectedRoot in protectedRoots) {
    if (_isSamePath(path, protectedRoot)) {
      return true;
    }
  }
  return false;
}

bool _isPathUnderAnyRoot(String path, List<String> protectedRoots) {
  for (final protectedRoot in protectedRoots) {
    if (_isPathEqualOrChild(path: path, parentPath: protectedRoot) &&
        !_isSamePath(path, protectedRoot)) {
      return true;
    }
  }
  return false;
}

bool _isPathEqualOrChild({
  required String path,
  required String parentPath,
}) {
  final normalizedPath = _normalizePathForComparison(path);
  final normalizedParentPath = _normalizePathForComparison(parentPath);
  if (normalizedPath.isEmpty || normalizedParentPath.isEmpty) {
    return false;
  }
  if (normalizedPath == normalizedParentPath) {
    return true;
  }
  return normalizedPath.startsWith('$normalizedParentPath/') ||
      normalizedPath.startsWith('$normalizedParentPath\\');
}

bool _isSamePath(String left, String right) =>
    _normalizePathForComparison(left) == _normalizePathForComparison(right);

String _normalizePathForComparison(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'[\\/]+$'), '')
      .replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator)
      .toLowerCase();
}

Future<void> _removeRegistryKey(
  String registryKey,
  WindowsRegistryCommandRunner runner,
) async {
  final result = await _queryRegistryKey(registryKey, runner);
  if (result == null || result.exitCode != 0) {
    return;
  }
  await _deleteRegistryKey(registryKey, runner);
}

Future<ProcessResult?> _queryRegistryKey(
  String registryKey,
  WindowsRegistryCommandRunner runner,
) async {
  try {
    return await runner('reg.exe', ['query', registryKey])
        .timeout(const Duration(seconds: 5));
  } on Object {
    return null;
  }
}

Future<void> _deleteRegistryKey(
  String registryKey,
  WindowsRegistryCommandRunner runner,
) async {
  try {
    await runner('reg.exe', ['delete', registryKey, '/f'])
        .timeout(const Duration(seconds: 5));
  } on Object {
    return;
  }
}

Future<void> _removeRegistryKeyIfEmpty(
  String registryKey,
  WindowsRegistryCommandRunner runner,
) async {
  final result = await _queryRegistryKey(registryKey, runner);
  if (result == null || result.exitCode != 0) {
    return;
  }
  if (_registryQueryOutputHasChildrenOrValues(
    registryKey: registryKey,
    output: result.stdout.toString(),
  )) {
    return;
  }
  await _deleteRegistryKey(registryKey, runner);
}

bool _registryQueryOutputHasChildrenOrValues({
  required String registryKey,
  required String output,
}) {
  final normalizedRegistryKey = _normalizeRegistryKeyForComparison(registryKey);
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final normalizedLine = _normalizeRegistryKeyForComparison(trimmed);
    if (normalizedLine == normalizedRegistryKey) {
      continue;
    }
    if (normalizedLine.startsWith('$normalizedRegistryKey\\')) {
      return true;
    }
    if (RegExp(r'\sREG_[A-Z0-9_]+\s', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
  }

  return false;
}

String _normalizeRegistryKeyForComparison(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[\\/]+'), r'\')
      .replaceAll(RegExp(r'[\\/]+$'), '')
      .toLowerCase();
  if (normalized == 'hkey_current_user' ||
      normalized.startsWith(r'hkey_current_user\')) {
    return normalized.replaceFirst('hkey_current_user', 'hkcu');
  }
  if (normalized == 'hkey_local_machine' ||
      normalized.startsWith(r'hkey_local_machine\')) {
    return normalized.replaceFirst('hkey_local_machine', 'hklm');
  }
  return normalized;
}

List<String> _dedupe(List<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    result.add(value);
  }
  return result;
}

String _joinPath(String base, String relative) {
  final separator = base.contains(r'\') ? r'\' : Platform.pathSeparator;
  final trimmedBase = base.replaceAll(RegExp(r'[\\/]+$'), '');
  final normalizedRelative = relative.replaceAll(RegExp(r'[\\/]+'), separator);
  return '$trimmedBase$separator$normalizedRelative';
}

String _joinWindowsPathParts(List<String> parts) =>
    parts.where((part) => part.trim().isNotEmpty).join(r'\');
