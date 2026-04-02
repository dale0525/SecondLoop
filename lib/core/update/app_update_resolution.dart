import 'app_update_architecture.dart';
import 'app_update_helpers.dart';
import 'app_update_models.dart';

AppUpdateAsset? matchAssetForCurrentPlatform(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> assets, {
  required bool windowsManagedRuntimeAvailable,
  String? releaseVersion,
  String? currentArchitecture,
  String? windowsAppId,
}) {
  final versionFilteredAssets = _filterAssetsForReleaseVersion(
    platform,
    assets,
    releaseVersion: releaseVersion,
  );

  if (platform == AppUpdatePlatform.windows) {
    return _matchWindowsAssetForCurrentRuntime(
      versionFilteredAssets,
      managedRuntimeAvailable: windowsManagedRuntimeAvailable,
      currentArchitecture: currentArchitecture,
      appId: windowsAppId,
    );
  }

  if (platform == AppUpdatePlatform.macos) {
    final managedArchive = _selectBestAssetForArchitecture(
      platform,
      versionFilteredAssets
          .where((asset) => isMacosManagedArchiveName(asset.name))
          .toList(),
      currentArchitecture: currentArchitecture,
    );
    if (managedArchive != null) {
      return managedArchive;
    }

    final manualInstaller = _selectBestAssetForArchitecture(
      platform,
      versionFilteredAssets
          .where((asset) => isMacosManualInstallerName(asset.name))
          .toList(),
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

  for (final asset in versionFilteredAssets) {
    if (matcher.hasMatch(asset.name)) return asset;
  }
  return null;
}

AppUpdateAsset? selectExternalDownloadAsset(
  AppUpdatePlatform platform, {
  required AppUpdateAsset? preferredAsset,
  required List<AppUpdateAsset> assets,
  String? releaseVersion,
  String? currentArchitecture,
  String? windowsAppId,
}) {
  final versionFilteredAssets = _filterAssetsForReleaseVersion(
    platform,
    assets,
    releaseVersion: releaseVersion,
  );

  List<AppUpdateAsset> findAll(bool Function(String name) matcher) {
    final matches = <AppUpdateAsset>[];
    for (final asset in versionFilteredAssets) {
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
    final matchedMsi = exactAppId != null && exactAppId.isNotEmpty
        ? selectFromMatches(
            (name) => isWindowsMsiInstallerNameForApp(name, appId: exactAppId),
            preferredAsset,
          )
        : selectFromMatches(isWindowsMsiInstallerName, preferredAsset);
    if (matchedMsi != null) {
      return matchedMsi;
    }
    return null;
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
  int? bestTieBreaker;
  for (final asset in matches) {
    final score = _scoreManualAssetForArchitecture(
      platform,
      asset.name,
      architecture,
    );
    if (score == null) {
      continue;
    }
    final tieBreaker = _assetSelectionTieBreaker(asset);
    if (bestScore == null ||
        score < bestScore ||
        (score == bestScore &&
            (bestTieBreaker == null || tieBreaker < bestTieBreaker))) {
      bestAsset = asset;
      bestScore = score;
      bestTieBreaker = tieBreaker;
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

int _assetSelectionTieBreaker(AppUpdateAsset asset) {
  final hasIntegrity = assetHasIntegrityMetadata(asset);
  final installModeHint = asset.installModeHint;
  if (hasIntegrity && installModeHint != null) {
    return 0;
  }
  if (hasIntegrity) {
    return 1;
  }
  if (installModeHint != null) {
    return 2;
  }
  return 3;
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
  final isWindowsManagedManifestAsset =
      _isWindowsManagedManifestAsset(asset, windowsAppId: windowsAppId);

  if (asset.installModeHint == AppUpdateInstallMode.stagedNextLaunch &&
      platform == AppUpdatePlatform.windows &&
      (isMatchingWindowsManagedPackage || isWindowsManagedManifestAsset) &&
      windowsManagedRuntimeAvailable &&
      assetHasIntegrityMetadata(asset)) {
    return AppUpdateInstallMode.stagedNextLaunch;
  }

  return switch (platform) {
    AppUpdatePlatform.windows
        when (isMatchingWindowsManagedPackage ||
                isWindowsManagedManifestAsset) &&
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
  String? releaseVersion,
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
  final normalizedReleaseVersion =
      releaseVersion == null || releaseVersion.trim().isEmpty
          ? null
          : normalizeStrictAppVersion(
              releaseVersion,
              argumentName: 'releaseVersion',
            );
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

      final manifestAppId = readStringLoose(candidateEntry, 'app_id');
      final packageFileName =
          parsedUrl.pathSegments.isEmpty ? key : parsedUrl.pathSegments.last;
      final name = readStringLoose(candidateEntry, 'name') ?? packageFileName;
      if (normalizedReleaseVersion != null &&
          !_assetMatchesReleaseVersion(
            platform,
            name,
            releaseVersion: normalizedReleaseVersion,
          )) {
        continue;
      }
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
        manifestAppId: manifestAppId,
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
  String? manifestAppId,
  String? windowsAppId,
}) {
  final normalized = rawInstallMode?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final isMatchingWindowsManagedPackage =
      _isMatchingWindowsManagedPackageName(assetName, appId: windowsAppId);
  final expectedWindowsAppId = windowsAppId?.trim();
  final manifestDeclaresMatchingWindowsManagedPackage =
      expectedWindowsAppId != null &&
          expectedWindowsAppId.isNotEmpty &&
          _matchesExpectedWindowsManifestIdentity(
            assetName: assetName,
            manifestAppId: manifestAppId,
            expectedAppId: expectedWindowsAppId,
          );

  return switch ((platform, normalized)) {
    (AppUpdatePlatform.windows, 'velopack')
        when isMatchingWindowsManagedPackage ||
            manifestDeclaresMatchingWindowsManagedPackage =>
      AppUpdateInstallMode.seamlessRestart,
    (AppUpdatePlatform.windows, 'staged-next-launch') ||
    (AppUpdatePlatform.windows, 'staged_next_launch')
        when isMatchingWindowsManagedPackage ||
            manifestDeclaresMatchingWindowsManagedPackage =>
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
  final isWindowsManagedManifestAsset =
      _isWindowsManagedManifestAsset(asset, windowsAppId: windowsAppId);
  if (platform == AppUpdatePlatform.windows &&
      (isMatchingWindowsManagedPackage || isWindowsManagedManifestAsset)) {
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

bool _isWindowsManagedManifestAsset(
  AppUpdateAsset asset, {
  String? windowsAppId,
}) {
  final expectedAppId = windowsAppId?.trim();
  if (expectedAppId == null || expectedAppId.isEmpty) {
    return false;
  }

  return (asset.installModeHint == AppUpdateInstallMode.seamlessRestart ||
          asset.installModeHint == AppUpdateInstallMode.stagedNextLaunch) &&
      !_isMatchingWindowsManagedPackageName(asset.name, appId: expectedAppId);
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
  var sawMatchingCandidate = false;

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
        final isWindowsCandidate = isWindowsVelopackPackageName(name) ||
            isWindowsMsiInstallerName(name) ||
            manifestAppId != null;
        if (!isWindowsCandidate) {
          continue;
        }
        sawWindowsCandidate = true;
        if (_matchesExpectedWindowsManifestIdentity(
          assetName: name,
          manifestAppId: manifestAppId,
          expectedAppId: expectedAppId,
        )) {
          sawMatchingCandidate = true;
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
      if (isExactMatch) {
        sawMatchingCandidate = true;
      }
    }
  }

  return sawWindowsCandidate && !sawMatchingCandidate;
}

List<AppUpdateAsset> _filterAssetsForReleaseVersion(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> assets, {
  String? releaseVersion,
}) {
  if (releaseVersion == null || releaseVersion.trim().isEmpty) {
    return assets;
  }

  final normalizedReleaseVersion = normalizeStrictAppVersion(
    releaseVersion,
    argumentName: 'releaseVersion',
  );

  return assets
      .where(
        (asset) => _assetMatchesReleaseVersion(
          platform,
          asset.name,
          releaseVersion: normalizedReleaseVersion,
        ),
      )
      .toList(growable: false);
}

bool _assetMatchesReleaseVersion(
  AppUpdatePlatform platform,
  String assetName, {
  required String releaseVersion,
}) {
  final assetVersion = _extractAssetVersionForPlatform(platform, assetName);
  if (assetVersion == null) {
    return !_assetNameContainsNonStrictVersionToken(platform, assetName);
  }

  return sameNormalizedVersion(assetVersion, releaseVersion);
}

bool _assetNameContainsNonStrictVersionToken(
  AppUpdatePlatform platform,
  String assetName,
) {
  final normalizedName = assetName.trim();
  if (normalizedName.isEmpty) {
    return false;
  }

  final matcher = switch (platform) {
    AppUpdatePlatform.windows => RegExp(
        r'(?<!\d)\d+\.\d+\.\d+(?:[.+-][A-Za-z0-9][A-Za-z0-9._-]*)+',
        caseSensitive: false,
      ),
    AppUpdatePlatform.macos || AppUpdatePlatform.linux => RegExp(
        r'v\d+\.\d+\.\d+(?:[.+-][A-Za-z0-9][A-Za-z0-9._-]*)+',
        caseSensitive: false,
      ),
    _ => null,
  };
  return matcher?.hasMatch(normalizedName) ?? false;
}

String? _extractAssetVersionForPlatform(
  AppUpdatePlatform platform,
  String assetName,
) {
  return switch (platform) {
    AppUpdatePlatform.windows => _extractWindowsAssetVersion(assetName),
    AppUpdatePlatform.macos ||
    AppUpdatePlatform.linux =>
      _extractTaggedAssetVersion(assetName),
    _ => null,
  };
}

String? _extractWindowsAssetVersion(String assetName) {
  final match = RegExp(
    r'(\d+\.\d+\.\d+)(?=(?:-[A-Za-z0-9_]+)*\.(?:msi|nupkg|exe)$|(?:-[A-Za-z0-9_]+)*$)',
    caseSensitive: false,
  ).firstMatch(assetName.trim());
  final version = match?.group(1);
  if (version == null || tryParseStrictAppVersion(version) == null) {
    return null;
  }
  return version;
}

String? _extractTaggedAssetVersion(String assetName) {
  final match = RegExp(
    r'v(\d+\.\d+\.\d+)(?=(?:-[A-Za-z0-9_]+)*\.(?:app\.tar\.gz|tar\.gz|dmg|zip)$|(?:-[A-Za-z0-9_]+)*$)',
    caseSensitive: false,
  ).firstMatch(assetName.trim());
  final version = match?.group(1);
  if (version == null || tryParseStrictAppVersion(version) == null) {
    return null;
  }
  return version;
}

bool _matchesExpectedWindowsManifestIdentity({
  required String assetName,
  required String? manifestAppId,
  required String expectedAppId,
}) {
  final normalizedManifestAppId = manifestAppId?.trim();
  if (normalizedManifestAppId != null && normalizedManifestAppId.isNotEmpty) {
    if (normalizedManifestAppId.toLowerCase() != expectedAppId.toLowerCase()) {
      return false;
    }

    final exactNameMatch =
        isWindowsVelopackPackageNameForApp(assetName, appId: expectedAppId) ||
            isWindowsMsiInstallerNameForApp(assetName, appId: expectedAppId);
    if (exactNameMatch) {
      return true;
    }

    final carriesRecognizedWindowsIdentity = isWindowsVelopackPackageName(
          assetName,
        ) ||
        isWindowsMsiInstallerName(assetName);
    if (carriesRecognizedWindowsIdentity) {
      return false;
    }

    final normalizedAssetName = assetName.trim().toLowerCase();
    final looksLikeWindowsPackageFile =
        normalizedAssetName.endsWith('.nupkg') ||
            normalizedAssetName.endsWith('.msi') ||
            normalizedAssetName.endsWith('.exe');
    return !looksLikeWindowsPackageFile;
  }

  final exactNameMatch =
      isWindowsVelopackPackageNameForApp(assetName, appId: expectedAppId) ||
          isWindowsMsiInstallerNameForApp(assetName, appId: expectedAppId);
  return exactNameMatch;
}
