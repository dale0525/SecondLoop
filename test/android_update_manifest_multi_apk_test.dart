import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/generate_update_manifest_lib.dart';

void main() {
  test('generateUpdateManifest emits multiple Android ABI entries', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_android_multi_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-android-arm64-v8a-v1.2.3.apk')
        .writeAsString('arm64');
    await File('${tempDir.path}/SecondLoop-android-armeabi-v7a-v1.2.3.apk')
        .writeAsString('armeabi');
    await File('${tempDir.path}/SecondLoop-android-x86_64-v1.2.3.apk')
        .writeAsString('x86_64');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    expect(platforms['android-arm64-v8a'], isNotNull);
    expect(platforms['android-armeabi-v7a'], isNotNull);
    expect(platforms['android-x86_64'], isNotNull);
  });
}
