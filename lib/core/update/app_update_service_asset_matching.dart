part of 'app_update_service.dart';

Uri _buildFallbackReleasePageUriImpl(
    String releaseRepo, String releaseApiOrigin) {
  final repo = releaseRepo.trim();
  if (repo.isEmpty) {
    final origin = _parseUriStatic(releaseApiOrigin.trim());
    if (origin != null) return origin;
    return Uri.parse('https://github.com');
  }
  return Uri.parse('https://github.com/$repo/releases/latest');
}

List<AppUpdateAsset> _parseAssetsImpl(Object? rawAssets) {
  if (rawAssets is! List) return const [];

  final parsed = <AppUpdateAsset>[];
  for (final item in rawAssets) {
    if (item is! Map) continue;
    final name = item['name'];
    final url = item['browser_download_url'];
    final sha256 = item['sha256'];
    if (name is! String || url is! String) continue;
    final uri = _parseUriStatic(url);
    if (uri == null) continue;
    parsed.add(
      AppUpdateAsset(
        name: name,
        downloadUri: uri,
        sha256:
            sha256 is String && sha256.trim().isNotEmpty ? sha256.trim() : null,
      ),
    );
  }

  return parsed;
}

AppUpdateAsset? _matchAssetForCurrentPlatformImpl(
  AppUpdatePlatform platform,
  List<AppUpdateAsset> assets, {
  required bool windowsManagedRuntimeAvailable,
  List<String> androidSupportedAbis = const <String>[],
}) {
  if (platform == AppUpdatePlatform.windows) {
    return _matchWindowsAssetForCurrentRuntimeImpl(
      assets,
      managedRuntimeAvailable: windowsManagedRuntimeAvailable,
    );
  }

  if (platform == AppUpdatePlatform.macos) {
    for (final asset in assets) {
      if (_isMacosManagedArchiveName(asset.name)) return asset;
    }
    for (final asset in assets) {
      if (_isMacosManualInstallerName(asset.name)) return asset;
    }
    return null;
  }

  if (platform == AppUpdatePlatform.android) {
    return _matchAndroidAssetForSupportedAbisImpl(
      assets,
      supportedAbis: androidSupportedAbis,
    );
  }

  final matcher = switch (platform) {
    AppUpdatePlatform.linux => RegExp(r'^SecondLoop-linux-x64-.*\.tar\.gz$'),
    _ => null,
  };

  if (matcher == null) return null;

  for (final asset in assets) {
    if (matcher.hasMatch(asset.name)) return asset;
  }
  return null;
}

AppUpdateAsset? _matchWindowsAssetForCurrentRuntimeImpl(
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
    final stagedPackage = findFirst(_isWindowsVelopackPackageName);
    if (stagedPackage != null) {
      return stagedPackage;
    }
  }

  return findFirst(_isWindowsMsiInstallerName);
}

AppUpdateInstallMode _resolveInstallModeImpl(
  AppUpdatePlatform platform,
  bool isReleaseMode,
  AppUpdateAsset? asset, {
  required bool windowsManagedRuntimeAvailable,
  required bool macosManagedInstallSupported,
}) {
  if (!isReleaseMode || asset == null) {
    return AppUpdateInstallMode.externalDownload;
  }

  final hasIntegrityMetadata = asset.sha256?.trim().isNotEmpty == true;
  return switch (platform) {
    AppUpdatePlatform.windows
        when _isWindowsVelopackPackageName(asset.name) &&
            windowsManagedRuntimeAvailable &&
            hasIntegrityMetadata =>
      AppUpdateInstallMode.seamlessRestart,
    AppUpdatePlatform.macos
        when _isMacosManagedArchiveName(asset.name) &&
            macosManagedInstallSupported &&
            hasIntegrityMetadata =>
      AppUpdateInstallMode.seamlessRestart,
    AppUpdatePlatform.linux
        when asset.name.endsWith('.tar.gz') && hasIntegrityMetadata =>
      AppUpdateInstallMode.seamlessRestart,
    _ => AppUpdateInstallMode.externalDownload,
  };
}

AppUpdateAsset? _matchManifestAssetForCurrentPlatformImpl(
  AppUpdatePlatform platform,
  Map<String, Object?> release, {
  List<String> androidSupportedAbis = const <String>[],
}) {
  final platforms = release['platforms'];
  if (platforms is! Map) {
    return null;
  }

  final keys = switch (platform) {
    AppUpdatePlatform.windows => const ['windows-x64', 'windows-x86_64'],
    AppUpdatePlatform.macos => const [
        'macos-universal',
        'darwin-aarch64',
        'darwin-x86_64',
      ],
    AppUpdatePlatform.linux => const ['linux-x64', 'linux-x86_64'],
    AppUpdatePlatform.android => _androidManifestKeysImpl(androidSupportedAbis),
    _ => const <String>[],
  };

  for (final key in keys) {
    final rawEntry = platforms[key];
    if (rawEntry is! Map) {
      continue;
    }
    final url = _readStringLooseStatic(rawEntry, 'package_url') ??
        _readStringLooseStatic(rawEntry, 'archive_url') ??
        _readStringLooseStatic(rawEntry, 'url');
    final parsedUrl = _parseUriStatic(url);
    if (parsedUrl == null) {
      continue;
    }

    final name = _readStringLooseStatic(rawEntry, 'name') ??
        (parsedUrl.pathSegments.isEmpty ? key : parsedUrl.pathSegments.last);
    final sha256 = _readStringLooseStatic(rawEntry, 'sha256');
    return AppUpdateAsset(
      name: name,
      downloadUri: parsedUrl,
      sha256: sha256,
    );
  }

  return null;
}

bool _isWindowsMsiInstallerName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('.msi') && normalized.contains('secondloop');
}

bool _isWindowsVelopackPackageName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('-full.nupkg') &&
      normalized.contains('secondloop');
}

bool _isMacosManagedArchiveName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('.app.tar.gz') &&
      normalized.contains('secondloop');
}

bool _isMacosManualInstallerName(String name) {
  final normalized = name.trim().toLowerCase();
  return (normalized.endsWith('.dmg') || normalized.endsWith('.zip')) &&
      normalized.contains('secondloop');
}

String? _readStringLooseStatic(Map entry, String key) {
  final value = entry[key];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

Uri? _parseUriStatic(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return Uri.tryParse(trimmed);
}
