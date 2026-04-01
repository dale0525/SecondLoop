import 'app_update_architecture.dart';
import 'app_update_helpers.dart';
import 'app_update_models.dart';

AppUpdateAsset? matchAssetForCurrentPlatform(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> assets, {
  required bool windowsManagedRuntimeAvailable,
  String? currentArchitecture,
  String? windowsAppId,
}) {
  if (platform == AppUpdatePlatform.windows) {
    return _matchWindowsAssetForCurrentRuntime(
      assets,
      managedRuntimeAvailable: windowsManagedRuntimeAvailable,
      currentArchitecture: currentArchitecture,
      appId: windowsAppId,
    );
  }

  if (platform == AppUpdatePlatform.macos) {
    final managedArchive = _selectBestAssetForArchitecture(
      platform,
      assets.where((asset) => isMacosManagedArchiveName(asset.name)).toList(),
      currentArchitecture: currentArchitecture,
    );
    if (managedArchive != null) {
      return managedArchive;
    }

    final manualInstaller = _selectBestAssetForArchitecture(
      platform,
      assets.where((asset) => isMacosManualInstallerName(asset.name)).toList(),
      currentArchitecture: currentArchitecture,
    );
    if (manualInstaller != null) {
      return manualInstaller;
    }
    return null;
  }

  final matcher = switch (platform) {
    AppUpdatePlatform.linux =>
      RegExp(r'^SecondLoop-linux-(?:x64|x86_64)-.*\.tar\.gz$'),
    AppUpdatePlatform.android => RegExp(r'^SecondLoop-android-.*\.apk$'),
    _ => null,
  };

  if (matcher == null) return null;

  for (final asset in assets) {
    if (matcher.hasMatch(asset.name)) return asset;
  }
  return null;
}

AppUpdateAsset? selectExternalDownloadAsset(
  AppUpdatePlatform platform, {
  required AppUpdateAsset? preferredAsset,
  required List<AppUpdateAsset> assets,
  String? currentArchitecture,
  String? windowsAppId,
}) {
  List<AppUpdateAsset> findAll(bool Function(String name) matcher) {
    final matches = <AppUpdateAsset>[];
    for (final asset in assets) {
      if (matcher(asset.name)) {
        matches.add(asset);
      }
    }
    return matches;
  }

  AppUpdateAsset? selectFromMatches(
    bool Function(String name) matcher,
    AppUpdateAsset? preferred,
  ) {
    final matches = findAll(matcher);
    if (preferred != null &&
        matcher(preferred.name) &&
        !matches.contains(preferred)) {
      matches.add(preferred);
    }
    return _selectBestAssetForArchitecture(
      platform,
      matches,
      currentArchitecture: currentArchitecture,
    );
  }

  if (platform == AppUpdatePlatform.windows) {
    final exactAppId = windowsAppId?.trim();
    if (exactAppId != null && exactAppId.isNotEmpty) {
      return selectFromMatches(
        (name) => isWindowsMsiInstallerNameForApp(name, appId: exactAppId),
        preferredAsset,
      );
    }

    return selectFromMatches(isWindowsMsiInstallerName, preferredAsset);
  }

  return switch (platform) {
    AppUpdatePlatform.macos =>
      selectFromMatches(isMacosManualInstallerName, preferredAsset),
    _ => preferredAsset,
  };
}

AppUpdateAsset? _selectBestAssetForArchitecture(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> matches, {
  String? currentArchitecture,
}) {
  if (matches.isEmpty) {
    return null;
  }

  final architecture = normalizeArchitectureLabel(currentArchitecture);

  AppUpdateAsset? bestAsset;
  int? bestScore;
  for (final asset in matches) {
    final score = _scoreManualAssetForArchitecture(
      platform,
      asset.name,
      architecture,
    );
    if (score == null) {
      continue;
    }
    if (bestScore == null || score < bestScore) {
      bestAsset = asset;
      bestScore = score;
    }
  }

  if (bestAsset == null && architecture != 'x64' && architecture != 'arm64') {
    return _fallbackAssetForUnknownArchitecture(platform, matches);
  }

  return bestAsset;
}

AppUpdateAsset? _fallbackAssetForUnknownArchitecture(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> matches,
) {
  if (matches.isEmpty) {
    return null;
  }

  if (platform == AppUpdatePlatform.macos) {
    for (final asset in matches) {
      if (asset.name.trim().toLowerCase().contains('universal')) {
        return asset;
      }
    }
  }

  for (final asset in matches) {
    final normalizedName = asset.name.trim().toLowerCase();
    final hasArm64Token =
        normalizedName.contains('arm64') || normalizedName.contains('aarch64');
    if (!hasArm64Token) {
      return asset;
    }
  }

  return matches.first;
}

int? _scoreManualAssetForArchitecture(
  AppUpdatePlatform platform,
  String assetName,
  String architecture,
) {
  final normalizedName = assetName.trim().toLowerCase();
  final normalizedArchitecture = normalizeArchitectureLabel(architecture);
  final hasArm64Token =
      normalizedName.contains('arm64') || normalizedName.contains('aarch64');
  final hasX64Token = normalizedName.contains('x64') ||
      normalizedName.contains('x86_64') ||
      normalizedName.contains('amd64');
  final hasUniversalToken = normalizedName.contains('universal');
  final hasKnownArchitectureToken =
      hasArm64Token || hasX64Token || hasUniversalToken;

  if (platform == AppUpdatePlatform.macos && hasUniversalToken) {
    return 0;
  }

  return switch (normalizedArchitecture) {
    'arm64' when hasArm64Token => 0,
    'arm64' when hasX64Token => null,
    'arm64' => hasKnownArchitectureToken ? 2 : 1,
    'x64' when hasX64Token => 0,
    'x64' when hasArm64Token => null,
    'x64' => hasKnownArchitectureToken ? 2 : 1,
    _ => hasKnownArchitectureToken ? null : 1,
  };
}

AppUpdateInstallMode resolveInstallMode(
  AppUpdatePlatform platform, {
  required bool isReleaseMode,
  required AppUpdateAsset? asset,
  required bool windowsManagedRuntimeAvailable,
  required bool macosManagedInstallSupported,
  String? windowsAppId,
}) {
  if (!isReleaseMode || asset == null) {
    return AppUpdateInstallMode.externalDownload;
  }

  final isMatchingWindowsManagedPackage =
      _isMatchingWindowsManagedPackageName(asset.name, appId: windowsAppId);

  if (asset.installModeHint == AppUpdateInstallMode.stagedNextLaunch &&
      platform == AppUpdatePlatform.windows &&
      isMatchingWindowsManagedPackage &&
      windowsManagedRuntimeAvailable &&
      assetHasIntegrityMetadata(asset)) {
    return AppUpdateInstallMode.stagedNextLaunch;
  }

  return switch (platform) {
    AppUpdatePlatform.windows
        when isMatchingWindowsManagedPackage &&
            windowsManagedRuntimeAvailable &&
            assetHasIntegrityMetadata(asset) =>
      AppUpdateInstallMode.seamlessRestart,
    AppUpdatePlatform.macos
        when isMacosManagedArchiveName(asset.name) &&
            macosManagedInstallSupported &&
            assetHasIntegrityMetadata(asset) =>
      AppUpdateInstallMode.seamlessRestart,
    AppUpdatePlatform.linux
        when asset.name.endsWith('.tar.gz') &&
            assetHasIntegrityMetadata(asset) =>
      AppUpdateInstallMode.seamlessRestart,
    _ => AppUpdateInstallMode.externalDownload,
  };
}

AppUpdateAsset? matchManifestAssetForCurrentPlatform(
  AppUpdatePlatform platform,
  Map<String, Object?> release, {
  required String currentArchitecture,
  bool allowHttp = false,
  bool allowFile = false,
  String? windowsAppId,
}) {
  final platforms = release['platforms'];
  if (platforms is! Map) {
    return null;
  }

  final candidates = <AppUpdateAsset>[];
  final keys = switch (platform) {
    AppUpdatePlatform.windows => const ['windows-x64', 'windows-x86_64'],
    AppUpdatePlatform.macos =>
      preferredMacosManifestKeysForArchitecture(currentArchitecture),
    AppUpdatePlatform.linux => const ['linux-x64', 'linux-x86_64'],
    _ => const <String>[],
  };

  for (final key in keys) {
    final rawEntry = platforms[key];
    final candidateEntries = switch (rawEntry) {
      Map() => <Map>[rawEntry],
      List() => rawEntry.whereType<Map>().toList(growable: false),
      _ => const <Map>[],
    };
    for (final candidateEntry in candidateEntries) {
      final url = readStringLoose(candidateEntry, 'package_url') ??
          readStringLoose(candidateEntry, 'archive_url') ??
          readStringLoose(candidateEntry, 'url');
      final parsedUrl = parseUpdateUri(
        url,
        allowHttp: allowHttp,
        allowFile: allowFile,
      );
      if (parsedUrl == null) {
        continue;
      }

      final name = readStringLoose(candidateEntry, 'name') ??
          (parsedUrl.pathSegments.isEmpty ? key : parsedUrl.pathSegments.last);
      final manifestAppId = readStringLoose(candidateEntry, 'app_id');
      if (platform == AppUpdatePlatform.windows) {
        final expectedAppId = windowsAppId?.trim();
        if (expectedAppId != null && expectedAppId.isNotEmpty) {
          if (!_matchesExpectedWindowsManifestIdentity(
            assetName: name,
            manifestAppId: manifestAppId,
            expectedAppId: expectedAppId,
          )) {
            continue;
          }
        }
      }
      final sha256 = readStringLoose(candidateEntry, 'sha256');
      final installModeHint = parseManifestInstallModeHint(
        platform,
        readStringLoose(candidateEntry, 'install_mode'),
        assetName: name,
        windowsAppId: windowsAppId,
      );
      candidates.add(
        AppUpdateAsset(
          name: name,
          downloadUri: parsedUrl,
          sha256: sha256,
          installModeHint: installModeHint,
        ),
      );
    }
  }

  return _selectBestAssetForArchitecture(
    platform,
    candidates,
    currentArchitecture: currentArchitecture,
  );
}

bool assetHasIntegrityMetadata(AppUpdateAsset asset) {
  return asset.sha256 != null && asset.sha256!.trim().isNotEmpty;
}

AppUpdateInstallMode? parseManifestInstallModeHint(
  AppUpdatePlatform platform,
  String? rawInstallMode, {
  required String assetName,
  String? windowsAppId,
}) {
  final normalized = rawInstallMode?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final isMatchingWindowsManagedPackage =
      _isMatchingWindowsManagedPackageName(assetName, appId: windowsAppId);

  return switch ((platform, normalized)) {
    (AppUpdatePlatform.windows, 'velopack')
        when isMatchingWindowsManagedPackage =>
      AppUpdateInstallMode.seamlessRestart,
    (AppUpdatePlatform.windows, 'staged-next-launch') ||
    (AppUpdatePlatform.windows, 'staged_next_launch')
        when isMatchingWindowsManagedPackage =>
      AppUpdateInstallMode.stagedNextLaunch,
    (AppUpdatePlatform.macos, 'app-tar-gz')
        when isMacosManagedArchiveName(assetName) =>
      AppUpdateInstallMode.seamlessRestart,
    (AppUpdatePlatform.linux, 'bundle-tar-gz')
        when assetName.toLowerCase().endsWith('.tar.gz') =>
      AppUpdateInstallMode.seamlessRestart,
    _ => null,
  };
}

String describeManualFallbackReason(
  AppUpdatePlatform platform,
  AppUpdateAsset? asset, {
  required bool isReleaseMode,
  required bool windowsManagedRuntimeAvailable,
  required bool macosManagedInstallSupported,
  String? windowsAppId,
  bool sawWindowsIdentityMismatch = false,
}) {
  if (asset == null) {
    if (platform == AppUpdatePlatform.windows && sawWindowsIdentityMismatch) {
      return 'windows_manifest_app_id_mismatch';
    }
    return 'missing_platform_asset';
  }
  if (!isReleaseMode) {
    return 'not_release_mode';
  }
  final isMatchingWindowsManagedPackage =
      _isMatchingWindowsManagedPackageName(asset.name, appId: windowsAppId);
  if (platform == AppUpdatePlatform.windows &&
      isMatchingWindowsManagedPackage) {
    if (!windowsManagedRuntimeAvailable) {
      return 'windows_runtime_unavailable';
    }
    if (!assetHasIntegrityMetadata(asset)) {
      return 'windows_integrity_missing';
    }
    return 'windows_manual_download_required';
  }
  if (platform == AppUpdatePlatform.macos &&
      isMacosManagedArchiveName(asset.name)) {
    if (!macosManagedInstallSupported) {
      return 'macos_install_location_unsupported';
    }
    if (!assetHasIntegrityMetadata(asset)) {
      return 'macos_integrity_missing';
    }
    return 'macos_manual_download_required';
  }
  if (platform == AppUpdatePlatform.linux &&
      asset.name.toLowerCase().endsWith('.tar.gz') &&
      !assetHasIntegrityMetadata(asset)) {
    return 'linux_integrity_missing';
  }
  return 'manual_download_required';
}

bool _isMatchingWindowsManagedPackageName(String assetName, {String? appId}) {
  final exactAppId = appId?.trim();
  if (exactAppId != null && exactAppId.isNotEmpty) {
    return isWindowsVelopackPackageNameForApp(assetName, appId: exactAppId);
  }
  return isWindowsVelopackPackageName(assetName);
}

String? readUpdateString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Uri? parseUpdateUri(
  String? value, {
  bool allowHttp = false,
  bool allowFile = false,
}) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') {
    if (!uri.hasScheme || !uri.hasAuthority) {
      return null;
    }
    return uri;
  }

  if (scheme == 'http') {
    if (!allowHttp || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }
    return uri;
  }

  if (scheme == 'file') {
    if (!allowFile || !uri.hasScheme) {
      return null;
    }
    return uri;
  }

  return null;
}

AppUpdateAsset? _matchWindowsAssetForCurrentRuntime(
  List<AppUpdateAsset> assets, {
  required bool managedRuntimeAvailable,
  String? currentArchitecture,
  String? appId,
}) {
  List<AppUpdateAsset> findAll(bool Function(String name) matcher) {
    final matches = <AppUpdateAsset>[];
    for (final asset in assets) {
      if (matcher(asset.name)) {
        matches.add(asset);
      }
    }
    return matches;
  }

  if (managedRuntimeAvailable) {
    final exactAppId = appId?.trim();
    final stagedPackage = _selectBestAssetForArchitecture(
      AppUpdatePlatform.windows,
      exactAppId == null || exactAppId.isEmpty
          ? findAll(isWindowsVelopackPackageName)
          : findAll(
              (name) =>
                  isWindowsVelopackPackageNameForApp(name, appId: exactAppId),
            ),
      currentArchitecture: currentArchitecture,
    );
    if (stagedPackage != null) {
      return stagedPackage;
    }
  }

  final exactAppId = appId?.trim();
  return _selectBestAssetForArchitecture(
    AppUpdatePlatform.windows,
    exactAppId == null || exactAppId.isEmpty
        ? findAll(isWindowsMsiInstallerName)
        : findAll(
            (name) => isWindowsMsiInstallerNameForApp(name, appId: exactAppId),
          ),
    currentArchitecture: currentArchitecture,
  );
}

bool releaseContainsWindowsIdentityMismatch(
  Map<String, Object?> release, {
  String? windowsAppId,
}) {
  final expectedAppId = windowsAppId?.trim();
  if (expectedAppId == null || expectedAppId.isEmpty) {
    return false;
  }

  var sawWindowsCandidate = false;

  final platforms = release['platforms'];
  if (platforms is Map) {
    for (final key in const ['windows-x64', 'windows-x86_64']) {
      final rawEntry = platforms[key];
      final candidateEntries = switch (rawEntry) {
        Map() => <Map>[rawEntry],
        List() => rawEntry.whereType<Map>().toList(growable: false),
        _ => const <Map>[],
      };
      for (final candidateEntry in candidateEntries) {
        final name = readStringLoose(candidateEntry, 'name') ??
            readStringLoose(candidateEntry, 'package_url') ??
            readStringLoose(candidateEntry, 'url') ??
            '';
        final manifestAppId = readStringLoose(candidateEntry, 'app_id');
        final isWindowsCandidate =
            isWindowsVelopackPackageName(name) || manifestAppId != null;
        if (!isWindowsCandidate) {
          continue;
        }
        sawWindowsCandidate = true;
        if (!_matchesExpectedWindowsManifestIdentity(
          assetName: name,
          manifestAppId: manifestAppId,
          expectedAppId: expectedAppId,
        )) {
          return true;
        }
      }
    }
  }

  final assets = release['assets'];
  if (assets is List) {
    for (final rawAsset in assets.whereType<Map>()) {
      final name = readStringLoose(rawAsset, 'name');
      if (name == null) {
        continue;
      }
      final isWindowsCandidate =
          isWindowsMsiInstallerName(name) || isWindowsVelopackPackageName(name);
      if (!isWindowsCandidate) {
        continue;
      }
      sawWindowsCandidate = true;
      final isExactMatch = isWindowsMsiInstallerNameForApp(
            name,
            appId: expectedAppId,
          ) ||
          isWindowsVelopackPackageNameForApp(name, appId: expectedAppId);
      if (!isExactMatch) {
        return true;
      }
    }
  }

  return sawWindowsCandidate && false;
}

bool _matchesExpectedWindowsManifestIdentity({
  required String assetName,
  required String? manifestAppId,
  required String expectedAppId,
}) {
  final exactNameMatch =
      isWindowsVelopackPackageNameForApp(assetName, appId: expectedAppId) ||
          isWindowsMsiInstallerNameForApp(assetName, appId: expectedAppId);
  if (!exactNameMatch) {
    return false;
  }

  final normalizedManifestAppId = manifestAppId?.trim();
  if (normalizedManifestAppId == null || normalizedManifestAppId.isEmpty) {
    return true;
  }

  return normalizedManifestAppId.toLowerCase() == expectedAppId.toLowerCase();
}
