import 'dart:io';

import 'app_update_models.dart';

bool isWindowsMsiInstallerName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('.msi') && normalized.contains('secondloop');
}

bool isWindowsVelopackPackageName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('-full.nupkg') &&
      normalized.contains('secondloop');
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
  final normalizedLeft = trimTrailingZeroSegments(leftVersion.segments);
  final normalizedRight = trimTrailingZeroSegments(rightVersion.segments);
  final sameBaseSegments = normalizedLeft.length == normalizedRight.length &&
      _listEquals(normalizedLeft, normalizedRight);
  if (leftVersion.isPrerelease != rightVersion.isPrerelease) {
    return false;
  }
  if (sameBaseSegments &&
      leftVersion.isPrerelease == rightVersion.isPrerelease) {
    if (!leftVersion.isPrerelease) {
      return true;
    }
    return comparePrereleaseIdentifiers(
          leftVersion.prereleaseIdentifiers,
          rightVersion.prereleaseIdentifiers,
        ) ==
        0;
  }
  return compareReleaseTagWithCurrentVersion(left, right) == 0;
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
