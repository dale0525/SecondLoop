import 'dart:io';

import 'app_update_models.dart';

bool isWindowsMsiInstallerName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('.msi') && normalized.contains('secondloop');
}

bool isWindowsMsiInstallerNameForApp(
  String name, {
  required String appId,
}) {
  if (!isWindowsMsiInstallerName(name)) {
    return false;
  }

  final normalizedAppId = appId.trim().toLowerCase();
  if (normalizedAppId.isEmpty) {
    return false;
  }

  final normalizedName = name.trim().toLowerCase();
  final hasDevToken = _hasWindowsDevInstallerIdentity(normalizedName);
  final tokens = _windowsInstallerTokens(normalizedName);

  switch (normalizedAppId) {
    case 'com.secondloop.secondloop':
      return !hasDevToken;
    case 'com.secondloop.secondloopdev':
      return hasDevToken;
    default:
      final expectedTokens = _customWindowsInstallerIdentityTokens(
        normalizedAppId,
      );
      if (expectedTokens.isNotEmpty &&
          expectedTokens.every(tokens.contains) &&
          (!hasDevToken || expectedTokens.contains('dev'))) {
        return true;
      }
      return !hasDevToken && _isGenericWindowsInstallerName(tokens);
  }
}

bool _hasWindowsDevInstallerIdentity(String normalizedName) {
  final tokens = _windowsInstallerTokens(normalizedName);
  return tokens.contains('secondloop') && tokens.contains('dev');
}

List<String> _windowsInstallerTokens(String normalizedName) {
  return normalizedName
      .replaceAll('.msi', '')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

List<String> _customWindowsInstallerIdentityTokens(String normalizedAppId) {
  const baseAppId = 'com.secondloop.secondloop';
  final appIdSegments = normalizedAppId.split('.');
  final suffix = normalizedAppId.startsWith(baseAppId)
      ? normalizedAppId.substring(baseAppId.length)
      : (appIdSegments.isEmpty ? '' : appIdSegments.last);
  final normalizedSuffix = suffix.trim();
  if (normalizedSuffix.isEmpty) {
    return const <String>[];
  }
  return normalizedSuffix
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

bool _isGenericWindowsInstallerName(List<String> tokens) {
  final meaningfulTokens = tokens
      .where(
        (token) =>
            token != 'secondloop' &&
            token != 'win' &&
            token != 'x64' &&
            token != 'arm64' &&
            token != 'aarch64',
      )
      .toList(growable: false);
  return meaningfulTokens.isEmpty;
}

bool isWindowsVelopackPackageName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('-full.nupkg') &&
      normalized.contains('secondloop');
}

bool isWindowsVelopackPackageNameForApp(
  String name, {
  required String appId,
}) {
  final normalizedName = name.trim().toLowerCase();
  final normalizedAppId = appId.trim().toLowerCase();
  if (normalizedName.isEmpty || normalizedAppId.isEmpty) {
    return false;
  }

  return normalizedName.endsWith('-full.nupkg') &&
      normalizedName.startsWith('$normalizedAppId-');
}

bool isMacosManagedArchiveName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('.app.tar.gz') &&
      normalized.contains('secondloop');
}

bool isMacosManualInstallerName(String name) {
  final normalized = name.trim().toLowerCase();
  return (normalized.endsWith('.dmg') || normalized.endsWith('.zip')) &&
      normalized.contains('secondloop');
}

String sanitizeUpdateAssetFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  if (sanitized.isEmpty) {
    return 'secondloop-update.bin';
  }
  return sanitized;
}

String? normalizeLatestTag(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^[vV]').hasMatch(trimmed)) {
    return 'v${trimmed.substring(1)}';
  }
  return 'v$trimmed';
}

bool sameNormalizedVersion(String left, String right) {
  final leftVersion = parseComparableAppVersion(left);
  final rightVersion = parseComparableAppVersion(right);
  if (leftVersion == null || rightVersion == null) {
    return false;
  }
  return _listEquals(leftVersion.segments, rightVersion.segments);
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

String? readStringLoose(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Directory resolveExtractedSourceDir(
  Directory extractedDir,
  AppUpdatePlatform platform,
) {
  if (platform == AppUpdatePlatform.linux) {
    final bundle = Directory('${extractedDir.path}/bundle');
    if (bundle.existsSync()) return bundle;
  }

  final entries = extractedDir
      .listSync()
      .where(
        (entry) => entry.path.split(Platform.pathSeparator).last != '.DS_Store',
      )
      .toList(growable: false);

  if (entries.length == 1 && entries.first is Directory) {
    return entries.first as Directory;
  }

  return extractedDir;
}
