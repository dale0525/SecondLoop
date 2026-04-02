part of 'app_update_service.dart';

bool _isAndroidApkAssetImpl(AppUpdateAsset asset) {
  if (asset.installModeHint == AppUpdateInstallMode.externalDownload &&
      asset.name.trim().toLowerCase().startsWith('secondloop-android-') &&
      asset.name.trim().toLowerCase().endsWith('.apk')) {
    return true;
  }

  final normalizedName = asset.name.trim().toLowerCase();
  if (normalizedName.startsWith('secondloop-android-') &&
      normalizedName.endsWith('.apk')) {
    return true;
  }
  final normalizedPath = asset.downloadUri.path.toLowerCase();
  return normalizedPath.contains('secondloop-android') &&
      normalizedPath.endsWith('.apk');
}

Future<List<String>> _loadAndroidSupportedAbisImpl({
  required List<String>? override,
  required AndroidSupportedAbisLoader? loader,
}) async {
  if (override != null) {
    return normalizeAndroidSupportedAbis(override);
  }
  if (loader != null) {
    return normalizeAndroidSupportedAbis(await loader());
  }
  try {
    const channel = MethodChannel('secondloop/android_update');
    final values = await channel.invokeListMethod<String>('getSupportedAbis');
    return normalizeAndroidSupportedAbis(values ?? const <String>[]);
  } on MissingPluginException {
    return const <String>[];
  } catch (_) {
    return const <String>[];
  }
}

AppUpdateAsset? _matchAndroidAssetForSupportedAbisImpl(
  List<AppUpdateAsset> assets, {
  required List<String> supportedAbis,
}) {
  final apkAssets =
      assets.where(_isAndroidApkAssetImpl).toList(growable: false);
  if (apkAssets.isEmpty) return null;

  final normalizedSupportedAbis = normalizeAndroidSupportedAbis(supportedAbis);
  if (normalizedSupportedAbis.isEmpty) {
    return null;
  }

  if (shouldRejectAndroidFallbackForSupportedAbis(normalizedSupportedAbis)) {
    return null;
  }

  for (final abi in normalizedSupportedAbis) {
    for (final asset in apkAssets) {
      if (_androidAssetMatchesAbiImpl(asset.name, abi)) {
        return asset;
      }
    }
  }

  for (final asset in apkAssets) {
    if (_isAndroidUniversalApkNameImpl(asset.name)) {
      return asset;
    }
  }

  return null;
}

AppUpdateAsset? _matchAndroidManifestAssetForCurrentPlatform(
  Map<String, Object?> release, {
  required List<String> supportedAbis,
  required bool allowHttp,
  required bool allowFile,
}) {
  final platforms = release['platforms'];
  if (platforms is! Map) {
    return null;
  }

  for (final key in _androidManifestKeysImpl(supportedAbis)) {
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

    final fallbackName = _androidManifestFallbackAssetName(
      key: key,
      uri: parsedUrl,
    );
    final name = readStringLoose(rawEntry, 'name') ?? fallbackName;
    final sha256 = readStringLoose(rawEntry, 'sha256');
    final installMode = readStringLoose(rawEntry, 'install_mode');
    final isExplicitApk = installMode?.trim().toLowerCase() == 'apk';
    if (!isExplicitApk && !name.toLowerCase().endsWith('.apk')) {
      continue;
    }

    return AppUpdateAsset(
      name: name,
      downloadUri: parsedUrl,
      sha256: sha256,
      installModeHint: AppUpdateInstallMode.externalDownload,
    );
  }

  return null;
}

bool _androidAssetMatchesAbiImpl(String assetName, String abi) {
  final normalizedAbi = canonicalizeAndroidAbi(abi);
  return extractLeadingAndroidAbi(assetName) == normalizedAbi;
}

bool _isAndroidUniversalApkNameImpl(String assetName) {
  return isUniversalAndroidApkName(assetName);
}

List<String> _androidManifestKeysImpl(List<String> supportedAbis) {
  final keys = <String>[];
  void add(String key) {
    if (!keys.contains(key)) {
      keys.add(key);
    }
  }

  final normalizedSupportedAbis = normalizeAndroidSupportedAbis(supportedAbis);
  if (shouldRejectAndroidFallbackForSupportedAbis(normalizedSupportedAbis)) {
    return const <String>[];
  }

  for (final abi in normalizedSupportedAbis) {
    switch (canonicalizeAndroidAbi(abi)) {
      case 'arm64-v8a':
        add('android-arm64-v8a');
        add('android-arm64');
        break;
      case 'armeabi-v7a':
        add('android-armeabi-v7a');
        add('android-armv7');
        add('android-arm-v7a');
        break;
    }
  }

  add('android-universal');
  add('android');
  return keys;
}

bool isAndroidApkAssetForUpdate(AppUpdateAsset asset) =>
    _isAndroidApkAssetImpl(asset);

String _androidManifestFallbackAssetName({
  required String key,
  required Uri uri,
}) {
  if (uri.pathSegments.isNotEmpty) {
    final lastSegment = uri.pathSegments.last.trim();
    if (lastSegment.isNotEmpty && lastSegment.toLowerCase().endsWith('.apk')) {
      return lastSegment;
    }
  }

  return switch (key) {
    'android-arm64-v8a' ||
    'android-arm64' =>
      'SecondLoop-android-arm64-v8a.apk',
    'android-armeabi-v7a' ||
    'android-armv7' ||
    'android-arm-v7a' =>
      'SecondLoop-android-armeabi-v7a.apk',
    _ => 'SecondLoop-android-universal.apk',
  };
}
