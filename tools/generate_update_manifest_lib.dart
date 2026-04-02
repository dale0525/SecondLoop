import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'package:secondloop/core/update/android/android_update_abi.dart';

class GeneratedUpdateManifest {
  const GeneratedUpdateManifest({
    required this.manifest,
    required this.jsonText,
    this.signatureBase64,
  });

  final Map<String, Object?> manifest;
  final String jsonText;
  final String? signatureBase64;
}

Future<GeneratedUpdateManifest> generateUpdateManifest({
  required String inputDirPath,
  required String version,
  required String baseDownloadUrl,
  String? releasePageUrl,
  DateTime? publishedAt,
  String? signingPrivateKeyBase64,
}) async {
  final inputDir = Directory(inputDirPath);
  if (!inputDir.existsSync()) {
    throw ArgumentError.value(
        inputDirPath, 'inputDirPath', 'directory_not_found');
  }

  final normalizedVersion = _normalizeVersion(version);
  final normalizedTag = 'v$normalizedVersion';
  final normalizedBaseUrl = _normalizeBaseDownloadUrl(baseDownloadUrl);
  final manifest = <String, Object?>{};
  manifest['version'] = normalizedVersion;
  manifest['tag_name'] = normalizedTag;
  manifest['release_page_url'] =
      releasePageUrl?.trim().isNotEmpty == true ? releasePageUrl!.trim() : null;
  manifest['pub_date'] =
      (publishedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String();
  manifest['platforms'] = await _buildPlatforms(
    inputDir,
    baseDownloadUrl: normalizedBaseUrl,
    normalizedVersion: normalizedVersion,
  );

  final jsonText = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  final signature = await _signManifest(
    utf8.encode(jsonText),
    signingPrivateKeyBase64?.trim(),
  );

  return GeneratedUpdateManifest(
    manifest: manifest,
    jsonText: jsonText,
    signatureBase64: signature,
  );
}

Future<Map<String, Object?>> _buildPlatforms(
  Directory inputDir, {
  required String baseDownloadUrl,
  required String normalizedVersion,
}) async {
  final entries = inputDir
      .listSync()
      .whereType<File>()
      .where((file) => !file.path.endsWith('.sha256'))
      .where((file) => _matchesRequestedVersion(file, normalizedVersion))
      .toList(growable: false)
    ..sort((left, right) => left.uri.pathSegments.last
        .toLowerCase()
        .compareTo(right.uri.pathSegments.last.toLowerCase()));

  final platforms = <String, Object?>{};

  final windowsPackage = _firstFile(
      entries,
      (name) =>
          name.toLowerCase().endsWith('-full.nupkg') &&
          name.toLowerCase().contains('secondloop'));
  if (windowsPackage != null) {
    final windowsEntry = <String, Object?>{};
    windowsEntry['install_mode'] = 'velopack';
    windowsEntry['name'] = windowsPackage.uri.pathSegments.last;
    windowsEntry['package_url'] =
        '$baseDownloadUrl${windowsPackage.uri.pathSegments.last}';
    final releasesFile = _firstFile(
      entries,
      _isWindowsReleasesMetadataFileName,
    );
    if (releasesFile != null) {
      windowsEntry['releases_url'] =
          '$baseDownloadUrl${releasesFile.uri.pathSegments.last}';
    }
    windowsEntry['sha256'] = await _sha256FileHex(windowsPackage);
    platforms['windows-x64'] = windowsEntry;
  }

  final macosArchive = _firstFile(
      entries,
      (name) =>
          name.toLowerCase().endsWith('.app.tar.gz') &&
          name.toLowerCase().contains('secondloop'));
  if (macosArchive != null) {
    platforms['macos-universal'] = await _buildArchiveEntry(
      file: macosArchive,
      baseDownloadUrl: baseDownloadUrl,
      installMode: 'app-tar-gz',
    );
  }

  final linuxArchive = _firstFile(
      entries,
      (name) =>
          name.toLowerCase().endsWith('.tar.gz') &&
          name.toLowerCase().contains('secondloop-linux-x64'));
  if (linuxArchive != null) {
    platforms['linux-x64'] = await _buildArchiveEntry(
      file: linuxArchive,
      baseDownloadUrl: baseDownloadUrl,
      installMode: 'bundle-tar-gz',
    );
  }

  final androidApks = entries.where((file) {
    final name = file.uri.pathSegments.last.toLowerCase();
    return name.endsWith('.apk') && name.contains('secondloop-android');
  }).toList(growable: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final androidApk in androidApks) {
    final androidKey =
        _resolveAndroidPlatformKey(androidApk.uri.pathSegments.last);
    if (androidKey.isEmpty) {
      continue;
    }
    if (platforms.containsKey(androidKey)) {
      throw StateError('duplicate_android_platform_asset_$androidKey');
    }
    platforms[androidKey] = await _buildArchiveEntry(
      file: androidApk,
      baseDownloadUrl: baseDownloadUrl,
      installMode: 'apk',
    );
  }

  if (platforms.isEmpty) {
    throw StateError('no_update_assets_found');
  }
  return platforms;
}

Future<Map<String, Object?>> _buildArchiveEntry({
  required File file,
  required String baseDownloadUrl,
  required String installMode,
}) async {
  return <String, Object?>{
    'install_mode': installMode,
    'name': file.uri.pathSegments.last,
    'archive_url': '$baseDownloadUrl${file.uri.pathSegments.last}',
    'sha256': await _sha256FileHex(file),
  };
}

Future<String?> _signManifest(
    List<int> payload, String? signingPrivateKeyBase64) async {
  if (signingPrivateKeyBase64 == null || signingPrivateKeyBase64.isEmpty) {
    return null;
  }

  final rawKey = base64Decode(signingPrivateKeyBase64);
  if (rawKey.length != 32 && rawKey.length != 64) {
    throw ArgumentError.value(
      rawKey.length,
      'signingPrivateKeyBase64',
      'expected 32-byte seed or 64-byte secret key',
    );
  }

  final seed = rawKey.length == 32 ? rawKey : rawKey.sublist(0, 32);
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final signature = await algorithm.sign(payload, keyPair: keyPair);
  return base64Encode(signature.bytes);
}

Future<String> _sha256FileHex(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  final digest = await sink.hash();
  final buffer = StringBuffer();
  for (final byte in digest.bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

File? _firstFile(List<File> files, bool Function(String name) predicate) {
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    if (predicate(name)) {
      return file;
    }
  }
  return null;
}

bool _matchesRequestedVersion(File file, String normalizedVersion) {
  final name = file.uri.pathSegments.last.toLowerCase();
  final version = normalizedVersion.toLowerCase();
  if (name.startsWith('releases.') && name.endsWith('.json')) {
    return _matchesReleaseMetadataVersion(name, version);
  }
  return name.contains('-$version.') ||
      name.contains('-v$version.') ||
      name.contains('-$version-') ||
      name.contains('-v$version-');
}

bool _matchesReleaseMetadataVersion(String fileName, String normalizedVersion) {
  final versionMarkers = <String>{
    normalizedVersion,
    'v$normalizedVersion',
    normalizedVersion.replaceAll('.', '-'),
    'v${normalizedVersion.replaceAll('.', '-')}',
    normalizedVersion.replaceAll('.', '_'),
    'v${normalizedVersion.replaceAll('.', '_')}',
  };
  for (final marker in versionMarkers) {
    if (fileName.contains(marker)) {
      return true;
    }
  }

  return !RegExp(r'v?\d+(?:[._-]\d+){1,3}').hasMatch(fileName);
}

String _normalizeVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'version', 'version_must_not_be_empty');
  }
  final normalized = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'version', 'version_must_be_vX_Y_Z');
  }
  return normalized;
}

String _normalizeBaseDownloadUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(
      value,
      'baseDownloadUrl',
      'base_download_url_must_not_be_empty',
    );
  }
  return trimmed.endsWith('/') ? trimmed : '$trimmed/';
}

String _resolveAndroidPlatformKey(String fileName) {
  switch (extractLeadingAndroidAbi(fileName)) {
    case 'arm64-v8a':
      return 'android-arm64-v8a';
    case 'armeabi-v7a':
      return 'android-armeabi-v7a';
  }
  if (hasUnsupportedAndroidAbiStem(fileName)) {
    return '';
  }
  if (isUniversalAndroidApkName(fileName)) {
    return 'android-universal';
  }
  throw StateError('unsupported_android_platform_asset_$fileName');
}

String resolveAndroidPlatformKeyForTest(String fileName) =>
    _resolveAndroidPlatformKey(fileName);

bool _isWindowsReleasesMetadataFileName(String fileName) {
  final normalized = fileName.trim().toLowerCase();
  return RegExp(r'^releases\.win(?:[._-].+)?\.json$').hasMatch(normalized);
}
