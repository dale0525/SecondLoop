import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'standard_message_codec_compat.dart';

const String _kManifestAssetPrefix = 'assets/bin/ffmpeg/';
const String _kWebResourcePrefix = 'assets/assets/bin/ffmpeg/';

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
  final prunedServiceWorkerEntries =
      await _pruneServiceWorkerResources(serviceWorker);

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
  final decodedManifest =
      _decodeStandardMessageCodec(base64.decode(decodedJson));
  final pruned = _pruneBinaryManifest(decodedManifest);
  final removedEntries = decodedManifest.length - pruned.length;
  if (removedEntries > 0) {
    await file.writeAsString(
      jsonEncode(base64.encode(_encodeStandardMessageCodec(pruned))),
    );
  }
  return removedEntries;
}

Future<int> _pruneServiceWorkerResources(File file) async {
  if (!await file.exists()) {
    return 0;
  }
  final lines = await file.readAsLines();
  final filtered = <String>[];
  var removedEntries = 0;
  for (final line in lines) {
    if (line.contains('"$_kWebResourcePrefix')) {
      removedEntries += 1;
      continue;
    }
    filtered.add(line);
  }
  if (removedEntries > 0) {
    await file.writeAsString('${filtered.join('\n')}\n');
  }
  return removedEntries;
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
