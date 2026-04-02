part of 'app_update_service.dart';

bool _isAndroidApkAssetImpl(AppUpdateAsset asset) {
  final normalizedInstallMode = asset.installMode?.trim().toLowerCase();
  if (normalizedInstallMode == 'apk') {
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
