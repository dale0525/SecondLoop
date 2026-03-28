import 'app_update_architecture.dart';
import 'app_update_helpers.dart';
import 'app_update_models.dart';

AppUpdateAsset? matchAssetForCurrentPlatform(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> assets, {
  required bool windowsManagedRuntimeAvailable,
}) {
  if (platform == AppUpdatePlatform.windows) {
    return _matchWindowsAssetForCurrentRuntime(
      assets,
      managedRuntimeAvailable: windowsManagedRuntimeAvailable,
    );
  }

  if (platform == AppUpdatePlatform.macos) {
    for (final asset in assets) {
      if (isMacosManagedArchiveName(asset.name)) return asset;
    }
    for (final asset in assets) {
      if (isMacosManualInstallerName(asset.name)) return asset;
    }
    return null;
  }

  final matcher = switch (platform) {
    AppUpdatePlatform.linux => RegExp(r'^SecondLoop-linux-x64-.*\.tar\.gz$'),
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
}) {
  AppUpdateAsset? findFirst(bool Function(String name) matcher) {
    for (final asset in assets) {
      if (matcher(asset.name)) return asset;
    }
    return null;
  }

  return switch (platform) {
    AppUpdatePlatform.windows => findFirst(isWindowsMsiInstallerName) ??
        (preferredAsset != null &&
                isWindowsMsiInstallerName(preferredAsset.name)
            ? preferredAsset
            : null),
    AppUpdatePlatform.macos => findFirst(isMacosManualInstallerName) ??
        (preferredAsset != null &&
                isMacosManualInstallerName(preferredAsset.name)
            ? preferredAsset
            : null),
    _ => preferredAsset,
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
    final parsedUrl = parseUpdateUri(url);
    if (parsedUrl == null) {
      continue;
    }

    final name = readStringLoose(rawEntry, 'name') ??
        (parsedUrl.pathSegments.isEmpty ? key : parsedUrl.pathSegments.last);
    final sha256 = readStringLoose(rawEntry, 'sha256');
    return AppUpdateAsset(
      name: name,
      downloadUri: parsedUrl,
      sha256: sha256,
    );
  }

  return null;
}

bool assetHasIntegrityMetadata(AppUpdateAsset asset) {
  return asset.sha256 != null && asset.sha256!.trim().isNotEmpty;
}

String describeManualFallbackReason(
  AppUpdatePlatform platform,
  AppUpdateAsset? asset,
) {
  if (asset == null) {
    return 'missing_platform_asset';
  }
  if (platform == AppUpdatePlatform.windows &&
      isWindowsVelopackPackageName(asset.name)) {
    return 'windows_runtime_unavailable';
  }
  if (platform == AppUpdatePlatform.macos &&
      isMacosManagedArchiveName(asset.name)) {
    return 'macos_install_location_unsupported_or_integrity_missing';
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

Uri? parseUpdateUri(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || (!uri.hasScheme && !uri.hasAuthority)) return null;
  return uri;
}

AppUpdateAsset? _matchWindowsAssetForCurrentRuntime(
  List<AppUpdateAsset> assets, {
  required bool managedRuntimeAvailable,
}) {
  AppUpdateAsset? findFirst(bool Function(String name) matcher) {
    for (final asset in assets) {
      if (matcher(asset.name)) return asset;
    }
    return null;
  }

  if (managedRuntimeAvailable) {
    final stagedPackage = findFirst(isWindowsVelopackPackageName);
    if (stagedPackage != null) {
      return stagedPackage;
    }
  }

  return findFirst(isWindowsMsiInstallerName);
}
