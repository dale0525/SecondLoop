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

const _defaultWindowsChannel = 'win';

Future<GeneratedUpdateManifest> generateUpdateManifest({
  required String inputDirPath,
  required String version,
  required String baseDownloadUrl,
  String? releasePageUrl,
  String windowsAppId = 'com.secondloop.secondloop',
  String? windowsChannel,
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
  final normalizedVersionSegments =
      tryParseStrictAppVersion(normalizedVersion)!;
  manifest['platforms'] = await _buildPlatforms(
    inputDir,
    baseDownloadUrl: normalizedBaseUrl,
    requiredVersion: normalizedVersionSegments,
    windowsAppId: windowsAppId,
    windowsChannel: windowsChannel,
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
  required List<int> requiredVersion,
  required String windowsAppId,
  String? windowsChannel,
}) async {
  final entries = inputDir
      .listSync()
      .whereType<File>()
      .where((file) => !file.path.endsWith('.sha256'))
      .toList(growable: false);

  final platforms = <String, Object?>{};
  final knownWindowsChannels = _detectWindowsChannels(entries);
  final requestedWindowsChannel = _normalizeWindowsChannel(windowsChannel);

  final windowsPackage = _selectNewestWindowsPackage(
    entries,
    requiredVersion: requiredVersion,
    windowsAppId: windowsAppId,
    windowsChannel: windowsChannel,
    knownChannels: knownWindowsChannels,
  );
  if (windowsPackage == null && requestedWindowsChannel != null) {
    throw StateError(
      'missing_requested_windows_package_channel:$requestedWindowsChannel',
    );
  }
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
      windowsChannel: windowsChannel,
      knownChannels: knownWindowsChannels,
    );
    if (releasesFile == null && requestedWindowsChannel != null) {
      throw StateError(
        'missing_requested_windows_releases_channel:$requestedWindowsChannel',
      );
    }
    if (releasesFile != null) {
      windowsEntry['releases_url'] =
          '$baseDownloadUrl${releasesFile.uri.pathSegments.last}';
    }
    windowsEntry['sha256'] = await _sha256FileHex(windowsPackage);
    platforms['windows-x64'] = windowsEntry;
  }

  final macosArchives = _selectMatchingArchives(
    entries,
    requiredVersion: requiredVersion,
    platform: 'macos',
  );
  if (macosArchives.isNotEmpty) {
    platforms['macos-universal'] = await _buildArchiveEntries(
      files: macosArchives,
      baseDownloadUrl: baseDownloadUrl,
      installMode: 'app-tar-gz',
    );
  }

  final linuxArchives = _selectMatchingArchives(
    entries,
    requiredVersion: requiredVersion,
    platform: 'linux-x64',
  );
  if (linuxArchives.isNotEmpty) {
    platforms['linux-x64'] = await _buildArchiveEntries(
      files: linuxArchives,
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

Future<Object> _buildArchiveEntries({
  required List<File> files,
  required String baseDownloadUrl,
  required String installMode,
}) async {
  if (files.length == 1) {
    return _buildArchiveEntry(
      file: files.first,
      baseDownloadUrl: baseDownloadUrl,
      installMode: installMode,
    );
  }

  final entries = <Map<String, Object?>>[];
  for (final file in files) {
    entries.add(
      await _buildArchiveEntry(
        file: file,
        baseDownloadUrl: baseDownloadUrl,
        installMode: installMode,
      ),
    );
  }
  return entries;
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
  required List<int> requiredVersion,
  required String windowsAppId,
  String? windowsChannel,
  Iterable<String> knownChannels = const <String>[],
}) {
  final requestedChannel = _normalizeWindowsChannel(windowsChannel);
  final resolvedKnownChannels = <String>{
    ...knownChannels.map((channel) => channel.trim().toLowerCase()),
    if (requestedChannel != null) requestedChannel,
  };
  final matchingPackages = <File>[];
  var sawMismatchedStrictVersion = false;
  var sawUnknownChannelVariant = false;

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final packageInfo = _parseWindowsPackageInfo(
      name,
      windowsAppId: windowsAppId,
      knownChannels: resolvedKnownChannels,
    );
    if (packageInfo == null) {
      if (_isUnknownWindowsPackageChannelVariant(
        name,
        windowsAppId: windowsAppId,
        requiredVersion: requiredVersion,
      )) {
        sawUnknownChannelVariant = true;
      }
      continue;
    }
    final version = packageInfo.version;
    final packageChannel = _effectiveWindowsChannel(
      packageInfo.channel,
    );
    if (requestedChannel != null) {
      if (packageChannel != requestedChannel) {
        continue;
      }
    }
    if (_compareStrictVersionSegments(version, requiredVersion) != 0) {
      sawMismatchedStrictVersion = true;
      continue;
    }
    matchingPackages.add(file);
  }

  if (matchingPackages.isEmpty && sawMismatchedStrictVersion) {
    throw StateError(
      'missing_matching_windows_package_version:'
      '${requiredVersion.join('.')}',
    );
  }

  if (sawUnknownChannelVariant && matchingPackages.isEmpty) {
    throw StateError(
      'unknown_windows_package_channel_variant:${requiredVersion.join('.')}',
    );
  }

  if (matchingPackages.isEmpty && requestedChannel != null) {
    throw StateError(
      'missing_requested_windows_package_channel:$requestedChannel',
    );
  }

  if (requestedChannel == null) {
    final discoveredChannels = matchingPackages
        .map((file) => _effectiveWindowsChannel(
              _extractWindowsPackageChannel(
                file.uri.pathSegments.last,
                knownChannels: resolvedKnownChannels,
              ),
            ))
        .toSet();
    if (discoveredChannels.length > 1) {
      throw StateError(
          'ambiguous_windows_channels:${discoveredChannels.join(',')}');
    }
  }

  File? newestFile;
  List<int>? newestVersion;

  for (final file in matchingPackages) {
    final name = file.uri.pathSegments.last;
    final version = _extractWindowsPackageVersion(
      name,
      windowsAppId: windowsAppId,
      knownChannels: resolvedKnownChannels,
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

List<File> _selectMatchingArchives(
  List<File> files, {
  required List<int> requiredVersion,
  required String platform,
}) {
  final matches = <File>[];
  var sawMismatchedStrictVersion = false;
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final version = _extractArchiveVersion(name, platform: platform);
    if (version == null) {
      continue;
    }
    if (_compareStrictVersionSegments(version, requiredVersion) != 0) {
      sawMismatchedStrictVersion = true;
      continue;
    }
    matches.add(file);
  }

  if (matches.isEmpty && sawMismatchedStrictVersion) {
    throw StateError(
      'missing_matching_${platform}_archive_version:${requiredVersion.join('.')}',
    );
  }

  return matches;
}

List<int>? _extractArchiveVersion(String fileName, {required String platform}) {
  final normalizedName = fileName.trim();
  if (normalizedName.isEmpty) {
    return null;
  }

  final match = switch (platform) {
    'macos' => RegExp(
        r'^SecondLoop-macos-(?:(?:arm64|aarch64|x64|x86_64|universal)-)?v(\d+\.\d+\.\d+)\.app\.tar\.gz$',
        caseSensitive: false,
      ).firstMatch(normalizedName),
    'linux-x64' => RegExp(
        r'^SecondLoop-linux-(?:x64|x86_64)-v(\d+\.\d+\.\d+)\.tar\.gz$',
        caseSensitive: false,
      ).firstMatch(normalizedName),
    _ => null,
  };
  if (match == null) {
    return null;
  }

  return tryParseStrictAppVersion(match.group(1) ?? '');
}

File? _selectMatchingReleasesFile(
  List<File> files, {
  required String packageName,
  String? windowsChannel,
  Iterable<String> knownChannels = const <String>[],
}) {
  final requestedChannel = _normalizeWindowsChannel(windowsChannel);
  final resolvedKnownChannels = <String>{
    ...knownChannels.map((channel) => channel.trim().toLowerCase()),
    if (requestedChannel != null) requestedChannel,
  };
  final packageChannel = _effectiveWindowsChannel(_extractWindowsPackageChannel(
    packageName,
    knownChannels: resolvedKnownChannels,
  ));
  final resolvedChannel = requestedChannel ?? packageChannel;

  return _firstFile(
    files,
    (name) =>
        name.toLowerCase() == 'releases.$resolvedChannel.json'.toLowerCase(),
  );
}

String? _normalizeWindowsChannel(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.toLowerCase();
}

String _effectiveWindowsChannel(String? value) {
  return _normalizeWindowsChannel(value) ?? _defaultWindowsChannel;
}

List<int>? _extractWindowsPackageVersion(
  String fileName, {
  required String windowsAppId,
  Iterable<String> knownChannels = const <String>[],
}) {
  return _parseWindowsPackageInfo(
    fileName,
    windowsAppId: windowsAppId,
    knownChannels: knownChannels,
  )?.version;
}

String? _extractWindowsPackageChannel(
  String fileName, {
  Iterable<String> knownChannels = const <String>[],
}) {
  return _parseWindowsPackageInfo(
    fileName,
    windowsAppId: _extractWindowsAppIdPrefix(fileName) ?? '',
    knownChannels: knownChannels,
  )?.channel;
}

Set<String> _detectWindowsChannels(List<File> files) {
  final channels = <String>{};
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final releasesMatch =
        RegExp(r'^releases\.(.+)\.json$', caseSensitive: false)
            .firstMatch(name);
    final assetsMatch =
        RegExp(r'^assets\.(.+)\.json$', caseSensitive: false).firstMatch(name);
    final channel =
        releasesMatch?.group(1)?.trim() ?? assetsMatch?.group(1)?.trim() ?? '';
    if (channel.isNotEmpty) {
      channels.add(channel.toLowerCase());
    }
  }
  return channels;
}

_WindowsPackageInfo? _parseWindowsPackageInfo(
  String fileName, {
  required String windowsAppId,
  Iterable<String> knownChannels = const <String>[],
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
    return _WindowsPackageInfo(version: directVersion);
  }

  final resolvedKnownChannels = knownChannels
      .map((channel) => channel.trim().toLowerCase())
      .where((channel) => channel.isNotEmpty)
      .toList(growable: false)
    ..sort((left, right) => right.length.compareTo(left.length));
  final normalizedStem = versionWithOptionalChannel.toLowerCase();
  for (final channel in resolvedKnownChannels) {
    final suffix = '-$channel';
    if (!normalizedStem.endsWith(suffix) ||
        versionWithOptionalChannel.length <= suffix.length) {
      continue;
    }
    final versionPart = versionWithOptionalChannel.substring(
      0,
      versionWithOptionalChannel.length - suffix.length,
    );
    final parsedVersion = tryParseStrictAppVersion(versionPart);
    if (parsedVersion != null) {
      return _WindowsPackageInfo(version: parsedVersion, channel: channel);
    }
  }

  return null;
}

bool _isUnknownWindowsPackageChannelVariant(
  String fileName, {
  required String windowsAppId,
  required List<int> requiredVersion,
}) {
  final normalizedName = fileName.trim();
  final normalizedAppId = windowsAppId.trim();
  if (normalizedName.isEmpty || normalizedAppId.isEmpty) {
    return false;
  }

  final lowerName = normalizedName.toLowerCase();
  final lowerAppId = normalizedAppId.toLowerCase();
  const suffix = '-full.nupkg';
  if (!lowerName.startsWith('$lowerAppId-') || !lowerName.endsWith(suffix)) {
    return false;
  }

  final versionStart = normalizedAppId.length + 1;
  final versionEnd = normalizedName.length - suffix.length;
  if (versionEnd <= versionStart) {
    return false;
  }

  final stem = normalizedName.substring(versionStart, versionEnd);
  final dashIndex = stem.indexOf('-');
  if (dashIndex <= 0 || dashIndex >= stem.length - 1) {
    return false;
  }

  final version = tryParseStrictAppVersion(stem.substring(0, dashIndex));
  if (version == null) {
    return false;
  }

  return _compareStrictVersionSegments(version, requiredVersion) == 0;
}

String? _extractWindowsAppIdPrefix(String fileName) {
  final normalizedName = fileName.trim();
  final suffixIndex = normalizedName.toLowerCase().lastIndexOf('-full.nupkg');
  if (suffixIndex <= 0) {
    return null;
  }
  final firstVersionToken =
      RegExp(r'-(\d+\.\d+\.\d+)').firstMatch(normalizedName);
  if (firstVersionToken == null || firstVersionToken.start <= 0) {
    return null;
  }
  return normalizedName.substring(0, firstVersionToken.start);
}

class _WindowsPackageInfo {
  const _WindowsPackageInfo({required this.version, this.channel});

  final List<int> version;
  final String? channel;
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
  final parsedVersion = tryParseStrictAppVersion(trimmed);
  if (parsedVersion == null) {
    throw ArgumentError.value(value, 'version', 'version_must_be_strict_x_y_z');
  }
  return '${parsedVersion[0]}.${parsedVersion[1]}.${parsedVersion[2]}';
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
