import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'standard_message_codec_compat.dart';

const String _kManifestAssetPrefix = 'assets/bin/ffmpeg/';
const String _kWebResourcePrefix = 'assets/assets/bin/ffmpeg/';
const String _kAssetManifestJsonResource = 'assets/AssetManifest.json';
const String _kAssetManifestBinResource = 'assets/AssetManifest.bin';
const String _kAssetManifestBinJsonResource = 'assets/AssetManifest.bin.json';

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  await pruneWebBuildFfmpegArtifacts(
    buildDir: Directory(config.buildDir),
    stdoutSink: stdout,
  );
}

Future<void> pruneWebBuildFfmpegArtifacts({
  required Directory buildDir,
  required IOSink stdoutSink,
}) async {
  final ffmpegDir = Directory(
    '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}assets${Platform.pathSeparator}bin${Platform.pathSeparator}ffmpeg',
  );
  var removedFileCount = 0;
  if (await ffmpegDir.exists()) {
    removedFileCount = await ffmpegDir
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .length;
    await ffmpegDir.delete(recursive: true);
  }

  final assetDir = Directory(
    '${buildDir.path}${Platform.pathSeparator}assets',
  );
  final assetManifestJson = File(
    '${assetDir.path}${Platform.pathSeparator}AssetManifest.json',
  );
  final assetManifestBin = File(
    '${assetDir.path}${Platform.pathSeparator}AssetManifest.bin',
  );
  final assetManifestBinJson = File(
    '${assetDir.path}${Platform.pathSeparator}AssetManifest.bin.json',
  );
  final serviceWorker = File(
    '${buildDir.path}${Platform.pathSeparator}flutter_service_worker.js',
  );

  final prunedJsonEntries = await _pruneAssetManifestJson(assetManifestJson);
  final prunedBinEntries = await _pruneAssetManifestBin(assetManifestBin);
  final prunedBinJsonEntries =
      await _pruneAssetManifestBinJson(assetManifestBinJson);
  final prunedServiceWorkerEntries = await _pruneServiceWorkerResources(
    serviceWorker,
    refreshedHashes: await _computeUpdatedServiceWorkerHashes(<File, String>{
      assetManifestJson: _kAssetManifestJsonResource,
      assetManifestBin: _kAssetManifestBinResource,
      assetManifestBinJson: _kAssetManifestBinJsonResource,
    }),
  );

  stdoutSink.writeln(
    'prune-web-build-ffmpeg: removed $removedFileCount payload files; '
    'pruned $prunedJsonEntries json manifest entries, '
    '$prunedBinEntries bin manifest entries, '
    '$prunedBinJsonEntries web bin manifest entries, '
    '$prunedServiceWorkerEntries service worker resources',
  );
}

_Config _parseArgs(List<String> args) {
  var buildDir = 'build/web';
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--build-dir') {
      if (index + 1 >= args.length) {
        throw const FormatException('Missing value for --build-dir');
      }
      buildDir = args[index + 1];
      index += 1;
      continue;
    }
    throw FormatException('Unknown argument: $arg');
  }
  return _Config(buildDir: buildDir);
}

Future<int> _pruneAssetManifestJson(File file) async {
  if (!await file.exists()) {
    return 0;
  }
  final raw = await file.readAsString();
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected ${file.path} to contain a JSON object');
  }
  final pruned = _pruneJsonManifest(decoded);
  final removedEntries = decoded.length - pruned.length;
  if (removedEntries > 0) {
    await file.writeAsString(jsonEncode(pruned));
  }
  return removedEntries;
}

Future<int> _pruneAssetManifestBin(File file) async {
  if (!await file.exists()) {
    return 0;
  }
  final bytes = await file.readAsBytes();
  final decoded = _decodeStandardMessageCodec(bytes);
  final pruned = _pruneBinaryManifest(decoded);
  final removedEntries = decoded.length - pruned.length;
  if (removedEntries > 0) {
    await file.writeAsBytes(_encodeStandardMessageCodec(pruned));
  }
  return removedEntries;
}

Future<int> _pruneAssetManifestBinJson(File file) async {
  if (!await file.exists()) {
    return 0;
  }
  final raw = await file.readAsString();
  final decodedJson = jsonDecode(raw);
  if (decodedJson is! String) {
    throw FormatException(
      'Expected ${file.path} to contain a base64 JSON string',
    );
  }
  final decodedManifest = decodedJson.isEmpty
      ? <Object?, Object?>{}
      : _decodeStandardMessageCodec(base64.decode(decodedJson));
  final pruned = _pruneBinaryManifest(decodedManifest);
  final removedEntries = decodedManifest.length - pruned.length;
  if (removedEntries > 0) {
    await file.writeAsString(
      jsonEncode(base64.encode(_encodeStandardMessageCodec(pruned))),
    );
  }
  return removedEntries;
}

Future<int> _pruneServiceWorkerResources(
  File file, {
  required Map<String, String> refreshedHashes,
}) async {
  if (!await file.exists()) {
    return 0;
  }
  final raw = await file.readAsString();
  final match =
      RegExp(r'const RESOURCES = (?<resources>\{[\s\S]*?\});').firstMatch(raw);
  if (match == null) {
    throw FormatException(
      'Expected ${file.path} to contain a RESOURCES object literal',
    );
  }

  final resourcesLiteral = match.namedGroup('resources');
  if (resourcesLiteral == null) {
    throw FormatException(
      'Expected ${file.path} to contain a RESOURCES object literal',
    );
  }

  final decoded = jsonDecode(resourcesLiteral);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException(
      'Expected ${file.path} RESOURCES to decode to a JSON object',
    );
  }

  final resources = Map<String, String>.fromEntries(
    decoded.entries.map(
      (entry) => MapEntry(entry.key, entry.value as String),
    ),
  );
  final originalHashes = Map<String, String>.from(resources);
  final removedEntries = originalHashes.keys
      .where((key) => key.startsWith(_kWebResourcePrefix))
      .length;
  resources.removeWhere((key, _) => key.startsWith(_kWebResourcePrefix));
  resources.addAll(refreshedHashes);

  final hashesChanged = refreshedHashes.entries.any(
    (entry) => originalHashes[entry.key] != entry.value,
  );
  if (removedEntries > 0 || hashesChanged) {
    final updated = raw.replaceRange(
      match.start,
      match.end,
      'const RESOURCES = ${_encodeResourceMap(resources)};',
    );
    await file.writeAsString(updated);
  }
  return removedEntries;
}

String _encodeResourceMap(Map<String, String> resources) {
  final entries = resources.entries.map(
    (entry) => '${jsonEncode(entry.key)}: ${jsonEncode(entry.value)}',
  );
  return '{${entries.join(',\n')}}';
}

Future<Map<String, String>> _computeUpdatedServiceWorkerHashes(
  Map<File, String> filesByResourceKey,
) async {
  final hashes = <String, String>{};
  for (final entry in filesByResourceKey.entries) {
    if (!await entry.key.exists()) {
      continue;
    }
    hashes[entry.value] = await _sha256FileHex(entry.key);
  }
  return hashes;
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

Map<String, List<String>> _pruneJsonManifest(Map<String, dynamic> manifest) {
  final pruned = <String, List<String>>{};
  manifest.forEach((key, value) {
    if (key.startsWith(_kManifestAssetPrefix)) {
      return;
    }
    final variants = (value as List<dynamic>)
        .cast<String>()
        .where((entry) => !entry.startsWith(_kManifestAssetPrefix))
        .toList();
    if (variants.isEmpty) {
      return;
    }
    pruned[key] = variants;
  });
  return pruned;
}

Map<Object?, Object?> _pruneBinaryManifest(Map<Object?, Object?> manifest) {
  final pruned = <Object?, Object?>{};
  manifest.forEach((key, value) {
    if (key is String && key.startsWith(_kManifestAssetPrefix)) {
      return;
    }
    if (value is List<Object?>) {
      final variants = value.where((entry) {
        if (entry is! Map<Object?, Object?>) {
          return true;
        }
        final asset = entry['asset'];
        return asset is! String || !asset.startsWith(_kManifestAssetPrefix);
      }).toList();
      if (variants.isEmpty) {
        return;
      }
      pruned[key] = variants;
      return;
    }
    pruned[key] = value;
  });
  return pruned;
}

Map<Object?, Object?> _decodeStandardMessageCodec(List<int> bytes) {
  final message = ByteData.sublistView(Uint8List.fromList(bytes));
  final decoded = const StandardMessageCodecCompat().decodeMessage(message);
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('Expected StandardMessageCodec map payload');
  }
  return decoded;
}

List<int> _encodeStandardMessageCodec(Map<Object?, Object?> manifest) {
  final encoded = const StandardMessageCodecCompat().encodeMessage(manifest)!;
  return encoded.buffer.asUint8List(0, encoded.lengthInBytes);
}

class _Config {
  const _Config({required this.buildDir});

  final String buildDir;
}
