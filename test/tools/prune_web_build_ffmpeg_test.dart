import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/standard_message_codec_compat.dart';

void main() {
  test('prune web build ffmpeg script removes payloads and stale references',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('prune_web_build_ffmpeg_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final buildDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}build${Platform.pathSeparator}web',
    );
    final ffmpegDir = Directory(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}assets${Platform.pathSeparator}bin${Platform.pathSeparator}ffmpeg',
    );
    await ffmpegDir.create(recursive: true);
    await File(
      '${ffmpegDir.path}${Platform.pathSeparator}linux${Platform.pathSeparator}ffmpeg',
    ).create(recursive: true);
    await File(
      '${ffmpegDir.path}${Platform.pathSeparator}README.md',
    ).writeAsString('desktop ffmpeg payload');

    final assetManifest = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.json',
    );
    await assetManifest.create(recursive: true);
    await assetManifest.writeAsString(jsonEncode(<String, Object>{
      'assets/bin/ffmpeg/linux/ffmpeg': <String>[
        'assets/bin/ffmpeg/linux/ffmpeg'
      ],
      'assets/bin/ffmpeg/README.md': <String>['assets/bin/ffmpeg/README.md'],
      'assets/icon/tray_icon.png': <String>['assets/icon/tray_icon.png'],
    }));

    final assetManifestBinJson = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin.json',
    );
    await assetManifestBinJson.create(recursive: true);
    final assetManifestBin = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin',
    );
    final encodedAssetManifestBin = _encodeBinaryManifest(<String, Object>{
      'assets/bin/ffmpeg/linux/ffmpeg': <Map<String, Object>>[
        <String, Object>{'asset': 'assets/bin/ffmpeg/linux/ffmpeg'},
      ],
      'assets/bin/ffmpeg/README.md': <Map<String, Object>>[
        <String, Object>{'asset': 'assets/bin/ffmpeg/README.md'},
      ],
      'assets/icon/tray_icon.png': <Map<String, Object>>[
        <String, Object>{'asset': 'assets/icon/tray_icon.png'},
      ],
    });
    await assetManifestBin.writeAsBytes(encodedAssetManifestBin);
    await assetManifestBinJson.writeAsString(
      jsonEncode(base64.encode(encodedAssetManifestBin)),
    );

    final serviceWorker = File(
      '${buildDir.path}${Platform.pathSeparator}flutter_service_worker.js',
    );
    await serviceWorker.writeAsString('''
const RESOURCES = {
  "assets/assets/bin/ffmpeg/linux/ffmpeg": "hash-a",
  "assets/assets/bin/ffmpeg/README.md": "hash-b",
  "assets/assets/icon/tray_icon.png": "hash-c"
};
''');

    final result = await Process.run(
      'pixi',
      <String>[
        'run',
        'flutter',
        'pub',
        'run tools/prune_web_build_ffmpeg.dart --build-dir ${buildDir.path}',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    expect(await ffmpegDir.exists(), isFalse);

    final updatedAssetManifest = jsonDecode(
      await assetManifest.readAsString(),
    ) as Map<String, dynamic>;
    expect(updatedAssetManifest.containsKey('assets/bin/ffmpeg/linux/ffmpeg'),
        isFalse);
    expect(updatedAssetManifest.containsKey('assets/bin/ffmpeg/README.md'),
        isFalse);
    expect(updatedAssetManifest['assets/icon/tray_icon.png'],
        <String>['assets/icon/tray_icon.png']);

    final updatedServiceWorker = await serviceWorker.readAsString();
    expect(updatedServiceWorker, isNot(contains('assets/assets/bin/ffmpeg/')));
    expect(updatedServiceWorker, contains('assets/assets/icon/tray_icon.png'));

    final updatedAssetManifestBin = _decodeBinaryManifest(
      await assetManifestBin.readAsBytes(),
    );
    expect(
        updatedAssetManifestBin.containsKey('assets/bin/ffmpeg/linux/ffmpeg'),
        isFalse);
    expect(updatedAssetManifestBin.containsKey('assets/bin/ffmpeg/README.md'),
        isFalse);
    expect(updatedAssetManifestBin.containsKey('assets/icon/tray_icon.png'),
        isTrue);

    final updatedAssetManifestBinJson = _decodeBinaryManifest(
      base64.decode(
          jsonDecode(await assetManifestBinJson.readAsString()) as String),
    );
    expect(
        updatedAssetManifestBinJson
            .containsKey('assets/bin/ffmpeg/linux/ffmpeg'),
        isFalse);
    expect(
        updatedAssetManifestBinJson.containsKey('assets/bin/ffmpeg/README.md'),
        isFalse);
    expect(updatedAssetManifestBinJson.containsKey('assets/icon/tray_icon.png'),
        isTrue);
  });
}

List<int> _encodeBinaryManifest(Map<String, Object> manifest) {
  final message = const StandardMessageCodecCompat().encodeMessage(manifest)!;
  return message.buffer.asUint8List(0, message.lengthInBytes);
}

Map<Object?, Object?> _decodeBinaryManifest(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return const StandardMessageCodecCompat().decodeMessage(data)!
      as Map<Object?, Object?>;
}
