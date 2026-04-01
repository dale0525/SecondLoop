part of 'app_update_service.dart';

const Map<String, List<String>> _androidAbiAliases = <String, List<String>>{
  'arm64-v8a': <String>['arm64-v8a', 'arm64', 'aarch64'],
  'armeabi-v7a': <String>['armeabi-v7a', 'armv7', 'arm-v7a'],
};

const List<String> _unsupportedAndroidAbiAliases = <String>[
  'x86',
  'x86_64',
  'x64',
  'i686',
  'ia32',
];

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
  final apkAssets =
      assets.where(_isAndroidApkAssetImpl).toList(growable: false);
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
  final normalizedAbi = _canonicalizeAndroidAbiImpl(abi);
  return _extractLeadingAndroidAbiImpl(assetName) == normalizedAbi;
}

bool _isAndroidUniversalApkNameImpl(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  final stem = _androidApkStemImpl(assetName);
  if (stem == null || !_looksLikeUniversalAndroidStemImpl(stem)) {
    return false;
  }
  return normalized.startsWith('secondloop-android-') &&
      normalized.endsWith('.apk') &&
      !_hasUnsupportedAndroidAbiStemImpl(assetName) &&
      _extractLeadingAndroidAbiImpl(assetName) == null;
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

String? _extractLeadingAndroidAbiImpl(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  const prefix = 'secondloop-android-';
  if (!normalized.startsWith(prefix) || !normalized.endsWith('.apk')) {
    return null;
  }

  final stem = normalized.substring(prefix.length, normalized.length - 4);
  for (final entry in _androidAbiAliases.entries) {
    for (final alias in entry.value) {
      if (stem == alias || stem.startsWith('$alias-')) {
        return entry.key;
      }
    }
  }

  return null;
}

bool _hasUnsupportedAndroidAbiStemImpl(String assetName) {
  final stem = _androidApkStemImpl(assetName);
  if (stem == null) {
    return false;
  }

  for (final alias in _unsupportedAndroidAbiAliases) {
    if (stem == alias || stem.startsWith('$alias-')) {
      return true;
    }
  }
  return false;
}

String? _androidApkStemImpl(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  const prefix = 'secondloop-android-';
  if (!normalized.startsWith(prefix) || !normalized.endsWith('.apk')) {
    return null;
  }
  return normalized.substring(prefix.length, normalized.length - 4);
}

bool _looksLikeUniversalAndroidStemImpl(String stem) {
  if (stem == 'universal' || stem.startsWith('universal-')) {
    return true;
  }
  return RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(stem);
}

bool isAndroidApkAssetForUpdate(AppUpdateAsset asset) =>
    _isAndroidApkAssetImpl(asset);
