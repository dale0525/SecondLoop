const Map<String, List<String>> supportedAndroidAbiAliases =
    <String, List<String>>{
  'arm64-v8a': <String>['arm64-v8a', 'arm64', 'aarch64'],
  'armeabi-v7a': <String>['armeabi-v7a', 'armv7', 'arm-v7a'],
};

const List<String> unsupportedAndroidAbiAliases = <String>[
  'x86',
  'x86_64',
  'x64',
  'i686',
  'ia32',
];

const String _androidApkPrefix = 'secondloop-android-';

String canonicalizeAndroidAbi(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return normalized;
  }
  for (final entry in supportedAndroidAbiAliases.entries) {
    if (entry.key == normalized || entry.value.contains(normalized)) {
      return entry.key;
    }
  }
  return normalized;
}

List<String> normalizeAndroidSupportedAbis(List<String> values) {
  final normalized = <String>[];
  for (final value in values) {
    final abi = canonicalizeAndroidAbi(value);
    if (abi.isEmpty || normalized.contains(abi)) {
      continue;
    }
    normalized.add(abi);
  }
  return normalized;
}

bool shouldRejectAndroidFallbackForSupportedAbis(List<String> values) {
  final normalized = normalizeAndroidSupportedAbis(values);
  if (normalized.isEmpty) {
    return false;
  }

  for (final abi in normalized) {
    if (supportedAndroidAbiAliases.containsKey(abi)) {
      return false;
    }
  }

  return true;
}

String? androidApkStem(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  if (!normalized.startsWith(_androidApkPrefix) ||
      !normalized.endsWith('.apk')) {
    return null;
  }
  return normalized.substring(_androidApkPrefix.length, normalized.length - 4);
}

String? extractLeadingAndroidAbi(String assetName) {
  final stem = androidApkStem(assetName);
  if (stem == null) {
    return null;
  }

  for (final entry in supportedAndroidAbiAliases.entries) {
    for (final alias in entry.value) {
      if (stem == alias || stem.startsWith('$alias-')) {
        return entry.key;
      }
    }
  }

  return null;
}

bool hasUnsupportedAndroidAbiStem(String assetName) {
  final stem = androidApkStem(assetName);
  if (stem == null) {
    return false;
  }

  for (final alias in unsupportedAndroidAbiAliases) {
    if (stem == alias || stem.startsWith('$alias-')) {
      return true;
    }
  }
  return false;
}

bool looksLikeUniversalAndroidStem(String stem) {
  if (stem == 'universal' || stem.startsWith('universal-')) {
    return true;
  }
  return RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(stem);
}

bool isUniversalAndroidApkName(String assetName) {
  final normalized = assetName.trim().toLowerCase();
  final stem = androidApkStem(assetName);
  if (stem == null || !looksLikeUniversalAndroidStem(stem)) {
    return false;
  }
  return normalized.startsWith(_androidApkPrefix) &&
      normalized.endsWith('.apk') &&
      !hasUnsupportedAndroidAbiStem(assetName) &&
      extractLeadingAndroidAbi(assetName) == null;
}
