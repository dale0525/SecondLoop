part of 'app_update_service.dart';

const Map<String, List<String>> _androidAbiAliases = <String, List<String>>{
  'arm64-v8a': <String>['arm64-v8a', 'arm64', 'aarch64'],
  'armeabi-v7a': <String>['armeabi-v7a', 'armv7', 'arm-v7a'],
  'x86_64': <String>['x86_64', 'x64'],
};

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
    final abi = _canonicalizeAndroidAbiImpl(value);
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
  final normalizedAbi = _canonicalizeAndroidAbiImpl(abi);
  final aliases = _androidAbiAliases[normalizedAbi] ?? <String>[normalizedAbi];
  for (final alias in aliases) {
    if (normalizedName.contains('-$alias-') ||
        normalizedName.endsWith('-$alias.apk') ||
        normalizedName.contains('_$alias.') ||
        normalizedName.contains('-$alias.')) {
      return true;
    }
  }
  return false;
}

bool _isAndroidUniversalApkNameImpl(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  final knownAbiMarkers =
      _androidAbiAliases.values.expand((aliases) => aliases);
  return normalized.startsWith('secondloop-android-') &&
      normalized.endsWith('.apk') &&
      !knownAbiMarkers.any(normalized.contains);
}

List<String> _androidManifestKeysImpl(List<String> supportedAbis) {
  final keys = <String>[];
  void add(String key) {
    if (!keys.contains(key)) {
      keys.add(key);
    }
  }

  for (final abi in supportedAbis) {
    switch (_canonicalizeAndroidAbiImpl(abi)) {
      case 'arm64-v8a':
        add('android-arm64-v8a');
        add('android-arm64');
        break;
      case 'armeabi-v7a':
        add('android-armeabi-v7a');
        add('android-armv7');
        add('android-arm-v7a');
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

String _canonicalizeAndroidAbiImpl(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return normalized;
  }
  for (final entry in _androidAbiAliases.entries) {
    if (entry.key == normalized || entry.value.contains(normalized)) {
      return entry.key;
    }
  }
  return normalized;
}
