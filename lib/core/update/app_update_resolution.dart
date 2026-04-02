import 'app_update_architecture.dart';
import 'app_update_helpers.dart';
import 'app_update_models.dart';

AppUpdateAsset? matchAssetForCurrentPlatform(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> assets, {
  required bool windowsManagedRuntimeAvailable,
  String? currentArchitecture,
}) {
  if (platform == AppUpdatePlatform.windows) {
    return _matchWindowsAssetForCurrentRuntime(
      assets,
      managedRuntimeAvailable: windowsManagedRuntimeAvailable,
      currentArchitecture: currentArchitecture,
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

  return switch (platform) {
    AppUpdatePlatform.windows =>
      selectFromMatches(isWindowsMsiInstallerName, preferredAsset),
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

  final architecture = currentArchitecture?.trim();
  if (architecture == null || architecture.isEmpty) {
    return matches.first;
  }

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

  return bestAsset;
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
}) {
  if (!isReleaseMode || asset == null) {
    return AppUpdateInstallMode.externalDownload;
  }

  if (asset.installModeHint == AppUpdateInstallMode.stagedNextLaunch &&
      platform == AppUpdatePlatform.windows &&
      isWindowsVelopackPackageName(asset.name) &&
      windowsManagedRuntimeAvailable &&
      assetHasIntegrityMetadata(asset)) {
    return AppUpdateInstallMode.stagedNextLaunch;
  }

  return switch (platform) {
    AppUpdatePlatform.windows
        when isWindowsVelopackPackageName(asset.name) &&
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
}) {
  final platforms = release['platforms'];
  if (platforms is! Map) {
    return null;
  }

  final keys = switch (platform) {
    AppUpdatePlatform.windows => const ['windows-x64', 'windows-x86_64'],
    AppUpdatePlatform.macos =>
      preferredMacosManifestKeysForArchitecture(currentArchitecture),
    AppUpdatePlatform.linux => const ['linux-x64', 'linux-x86_64'],
    _ => const <String>[],
  };

  for (final key in keys) {
    final rawEntry = platforms[key];
    if (rawEntry is! Map) {
      continue;
    }
    final url = readStringLoose(rawEntry, 'package_url') ??
        readStringLoose(rawEntry, 'archive_url') ??
        readStringLoose(rawEntry, 'url');
    final parsedUrl = parseUpdateUri(
      url,
      allowHttp: allowHttp,
      allowFile: allowFile,
    );
    if (parsedUrl == null) {
      continue;
    }

    final name = readStringLoose(rawEntry, 'name') ??
        (parsedUrl.pathSegments.isEmpty ? key : parsedUrl.pathSegments.last);
    final sha256 = readStringLoose(rawEntry, 'sha256');
    final installModeHint = parseManifestInstallModeHint(
      platform,
      readStringLoose(rawEntry, 'install_mode'),
      assetName: name,
    );
    return AppUpdateAsset(
      name: name,
      downloadUri: parsedUrl,
      sha256: sha256,
      installModeHint: installModeHint,
    );
  }

  return null;
}

bool assetHasIntegrityMetadata(AppUpdateAsset asset) {
  return asset.sha256 != null && asset.sha256!.trim().isNotEmpty;
}

AppUpdateInstallMode? parseManifestInstallModeHint(
  AppUpdatePlatform platform,
  String? rawInstallMode, {
  required String assetName,
}) {
  final normalized = rawInstallMode?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  return switch ((platform, normalized)) {
    (AppUpdatePlatform.windows, 'velopack')
        when isWindowsVelopackPackageName(assetName) =>
      AppUpdateInstallMode.seamlessRestart,
    (AppUpdatePlatform.windows, 'staged-next-launch') ||
    (AppUpdatePlatform.windows, 'staged_next_launch')
        when isWindowsVelopackPackageName(assetName) =>
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
}) {
  if (asset == null) {
    return 'missing_platform_asset';
  }
  if (!isReleaseMode) {
    return 'not_release_mode';
  }
  if (platform == AppUpdatePlatform.windows &&
      isWindowsVelopackPackageName(asset.name)) {
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
    final stagedPackage = _selectBestAssetForArchitecture(
      AppUpdatePlatform.windows,
      findAll(isWindowsVelopackPackageName),
      currentArchitecture: currentArchitecture,
    );
    if (stagedPackage != null) {
      return stagedPackage;
    }
  }

  return _selectBestAssetForArchitecture(
    AppUpdatePlatform.windows,
    findAll(isWindowsMsiInstallerName),
    currentArchitecture: currentArchitecture,
  );
}
