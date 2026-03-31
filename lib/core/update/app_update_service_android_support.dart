part of 'app_update_service.dart';

Future<List<String>> _loadAndroidSupportedAbisImpl({
  required List<String>? override,
  required AndroidSupportedAbisLoader? loader,
}) async {
  if (override != null) {
    return _normalizeAndroidSupportedAbisImpl(override);
  }
  if (loader != null) {
    return _normalizeAndroidSupportedAbisImpl(await loader());
  }
  try {
    const channel = MethodChannel('secondloop/android_update');
    final values = await channel.invokeListMethod<String>('getSupportedAbis');
    return _normalizeAndroidSupportedAbisImpl(values ?? const <String>[]);
  } on MissingPluginException {
    return const <String>[];
  } catch (_) {
    return const <String>[];
  }
}

List<String> _normalizeAndroidSupportedAbisImpl(List<String> values) {
  final normalized = <String>[];
  for (final value in values) {
    final abi = value.trim().toLowerCase();
    if (abi.isEmpty || normalized.contains(abi)) {
      continue;
    }
    normalized.add(abi);
  }
  return normalized;
}

AppUpdateAsset? _matchAndroidAssetForSupportedAbisImpl(
  List<AppUpdateAsset> assets, {
  required List<String> supportedAbis,
}) {
  final apkAssets = assets.where((asset) {
    final name = asset.name.trim().toLowerCase();
    return name.startsWith('secondloop-android-') && name.endsWith('.apk');
  }).toList(growable: false);
  if (apkAssets.isEmpty) return null;

  for (final abi in supportedAbis) {
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
  final normalizedName = assetName.trim().toLowerCase();
  final normalizedAbi = abi.trim().toLowerCase();
  return normalizedName.contains('-$normalizedAbi') ||
      (normalizedAbi == 'arm64-v8a' && normalizedName.contains('-arm64-'));
}

bool _isAndroidUniversalApkNameImpl(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  return normalized.startsWith('secondloop-android-') &&
      normalized.endsWith('.apk') &&
      !normalized.contains('arm64-v8a') &&
      !normalized.contains('armeabi-v7a') &&
      !normalized.contains('x86_64');
}

List<String> _androidManifestKeysImpl(List<String> supportedAbis) {
  final keys = <String>[];
  void add(String key) {
    if (!keys.contains(key)) {
      keys.add(key);
    }
  }

  for (final abi in supportedAbis) {
    switch (abi) {
      case 'arm64-v8a':
        add('android-arm64-v8a');
        add('android-arm64');
        break;
      case 'armeabi-v7a':
        add('android-armeabi-v7a');
        add('android-armv7');
        break;
      case 'x86_64':
        add('android-x86_64');
        break;
    }
  }

  add('android-universal');
  add('android');
  return keys;
}
