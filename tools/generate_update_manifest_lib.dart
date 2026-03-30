import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:secondloop/core/update/app_update_models.dart';

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
  String windowsAppId = 'com.secondloop.secondloop',
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
    windowsAppId: windowsAppId,
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
  required String windowsAppId,
}) async {
  final entries = inputDir
      .listSync()
      .whereType<File>()
      .where((file) => !file.path.endsWith('.sha256'))
      .toList(growable: false);

  final platforms = <String, Object?>{};

  final windowsPackage = _selectNewestWindowsPackage(
    entries,
    windowsAppId: windowsAppId,
  );
  if (windowsPackage != null) {
    final windowsEntry = <String, Object?>{};
    windowsEntry['install_mode'] = 'velopack';
    windowsEntry['name'] = windowsPackage.uri.pathSegments.last;
    windowsEntry['app_id'] = windowsAppId;
    windowsEntry['package_url'] =
        '$baseDownloadUrl${windowsPackage.uri.pathSegments.last}';
    final releasesFile = _selectMatchingReleasesFile(
      entries,
      packageName: windowsPackage.uri.pathSegments.last,
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

File? _selectNewestWindowsPackage(
  List<File> files, {
  required String windowsAppId,
}) {
  File? newestFile;
  List<int>? newestVersion;

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final version = _extractWindowsPackageVersion(
      name,
      windowsAppId: windowsAppId,
    );
    if (version == null) {
      continue;
    }
    if (newestVersion == null ||
        _compareStrictVersionSegments(version, newestVersion) > 0) {
      newestFile = file;
      newestVersion = version;
    }
  }

  return newestFile;
}

File? _selectMatchingReleasesFile(
  List<File> files, {
  required String packageName,
}) {
  final packageChannel = _extractWindowsPackageChannel(packageName);
  if (packageChannel != null) {
    final expectedName = 'releases.$packageChannel.json'.toLowerCase();
    final exact = _firstFile(
      files,
      (name) => name.toLowerCase() == expectedName,
    );
    if (exact != null) {
      return exact;
    }
  }

  return _firstFile(
    files,
    (name) =>
        name.toLowerCase().startsWith('releases.') &&
        name.toLowerCase().endsWith('.json'),
  );
}

List<int>? _extractWindowsPackageVersion(
  String fileName, {
  required String windowsAppId,
}) {
  final normalizedName = fileName.trim();
  final normalizedAppId = windowsAppId.trim();
  if (normalizedName.isEmpty || normalizedAppId.isEmpty) {
    return null;
  }

  final prefix = '$normalizedAppId-';
  if (!normalizedName.toLowerCase().startsWith(prefix.toLowerCase()) ||
      !normalizedName.toLowerCase().endsWith('-full.nupkg')) {
    return null;
  }

  final versionWithOptionalChannel = normalizedName.substring(
    prefix.length,
    normalizedName.length - '-full.nupkg'.length,
  );
  final directVersion = tryParseStrictAppVersion(versionWithOptionalChannel);
  if (directVersion != null) {
    return directVersion;
  }

  final separatorIndex = versionWithOptionalChannel.indexOf('-');
  if (separatorIndex <= 0) {
    return null;
  }

  final versionPart = versionWithOptionalChannel.substring(0, separatorIndex);
  return tryParseStrictAppVersion(versionPart);
}

String? _extractWindowsPackageChannel(String fileName) {
  final normalizedName = fileName.trim();
  if (!normalizedName.toLowerCase().endsWith('-full.nupkg')) {
    return null;
  }

  final packageStem =
      normalizedName.substring(0, normalizedName.length - '-full.nupkg'.length);
  final versionMatch =
      RegExp(r'-(\d+\.\d+\.\d+)(?:-(.+))?$').firstMatch(packageStem);
  final channel = versionMatch?.group(2)?.trim();
  if (channel == null || channel.isEmpty) {
    return null;
  }
  return channel;
}

int _compareStrictVersionSegments(List<int> left, List<int> right) {
  for (var index = 0; index < 3; index += 1) {
    final compared = left[index].compareTo(right[index]);
    if (compared != 0) {
      return compared;
    }
  }
  return 0;
}

String _normalizeVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'version', 'version_must_not_be_empty');
  }
  return trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
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
