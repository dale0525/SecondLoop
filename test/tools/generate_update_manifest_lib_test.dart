import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tools/generate_update_manifest_lib.dart';

void main() {
  test('generateUpdateManifest emits platform entries and release metadata',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('update_manifest_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('windows');
    await File('${tempDir.path}/releases.win.json').writeAsString('legacy');
    await File('${tempDir.path}/SecondLoop-macos-v1.2.3.app.tar.gz')
        .writeAsString('macos');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');
    await File('${tempDir.path}/SecondLoop-android-v1.2.3.apk')
        .writeAsString('android');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
      releasePageUrl:
          'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3',
      publishedAt: DateTime.utc(2026, 3, 14, 10, 0, 0),
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;
    final macos = platforms['macos-universal'] as Map<String, Object?>;
    final linux = platforms['linux-x64'] as Map<String, Object?>;
    final android = platforms['android-universal'] as Map<String, Object?>;

    expect(generated.manifest['version'], '1.2.3');
    expect(generated.manifest['tag_name'], 'v1.2.3');
    expect(
      generated.manifest['release_page_url'],
      'https://github.com/dale0525/SecondLoop/releases/tag/v1.2.3',
    );
    expect(generated.manifest['pub_date'], '2026-03-14T10:00:00.000Z');

    expect(windows['install_mode'], 'velopack');
    expect(
      windows['package_url'],
      'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3/com.secondloop.secondloop-1.2.3-full.nupkg',
    );
    expect(
      windows['releases_url'],
      'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3/releases.win.json',
    );
    expect(
      windows['sha256'],
      _hexEncode((await Sha256().hash(utf8.encode('windows'))).bytes),
    );
    expect(macos['install_mode'], 'app-tar-gz');
    expect(
      macos['sha256'],
      _hexEncode((await Sha256().hash(utf8.encode('macos'))).bytes),
    );
    expect(linux['install_mode'], 'bundle-tar-gz');
    expect(
      linux['sha256'],
      _hexEncode((await Sha256().hash(utf8.encode('linux'))).bytes),
    );
    expect(android['install_mode'], 'apk');
    expect(
      android['archive_url'],
      'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3/SecondLoop-android-v1.2.3.apk',
    );
    expect(generated.signatureBase64, isNull);
  });

  test('generateUpdateManifest rejects invalid signing key lengths', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_invalid_sig_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
        signingPrivateKeyBase64: base64Encode(
          List<int>.generate(33, (index) => index + 1),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('generateUpdateManifest emits Android ABI-specific entries', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_android_multi_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-android-arm64-v8a-v1.2.3.apk')
        .writeAsString('arm64');
    await File('${tempDir.path}/SecondLoop-android-armeabi-v7a-v1.2.3.apk')
        .writeAsString('armeabi');
    await File('${tempDir.path}/SecondLoop-android-v1.2.3.apk')
        .writeAsString('universal');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    expect(platforms['android-arm64-v8a'], isNotNull);
    expect(platforms['android-armeabi-v7a'], isNotNull);
    expect(platforms['android-universal'], isNotNull);
  });

  test('generateUpdateManifest recognizes Android ABI alias file names',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_android_alias_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-android-arm64-v1.2.3.apk')
        .writeAsString('arm64');
    await File('${tempDir.path}/SecondLoop-android-x64-v1.2.3.apk')
        .writeAsString('x64');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    expect(platforms['android-arm64-v8a'], isNotNull);
    expect(platforms['android-x86_64'], isNull);
    expect(platforms['android-universal'], isNull);
  });

  test(
      'generateUpdateManifest ignores unsupported Android x86 alias file names',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_android_x86_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-android-i686-v1.2.3.apk')
        .writeAsString('x86');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: 'v1.2.3',
        baseDownloadUrl:
            'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('generateUpdateManifest rejects duplicate Android platform keys',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_android_dupe_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-android-arm64-v8a-v1.2.3.apk')
        .writeAsString('arm64-a');
    await File('${tempDir.path}/SecondLoop-android-arm64-v8a-hotfix-v1.2.3.apk')
        .writeAsString('arm64-b');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: 'v1.2.3',
        baseDownloadUrl:
            'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
      'generateUpdateManifest picks Velopack releases metadata json when present',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_releases_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('windows');
    await File('${tempDir.path}/releases.win.json').writeAsString('{}');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;
    expect(
      windows['releases_url'],
      'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3/releases.win.json',
    );
  });

  test(
      'generateUpdateManifest prefers Windows releases metadata over unrelated releases json files',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_releases_prefer_win_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('windows');
    await File('${tempDir.path}/releases.android.json').writeAsString('{}');
    await File('${tempDir.path}/releases.win.json').writeAsString('{}');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;
    expect(
      windows['releases_url'],
      'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3/releases.win.json',
    );
  });

  test(
      'generateUpdateManifest ignores stale Velopack releases metadata from other versions',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_releases_stale_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('windows');
    await File('${tempDir.path}/releases.win.1.2.2.json').writeAsString('{}');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;
    expect(windows['releases_url'], isNull);
  });

  test('generateUpdateManifest ignores stale assets from other versions',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_stale_version_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.2-full.nupkg')
        .writeAsString('old-windows');
    await File('${tempDir.path}/SecondLoop-macos-v1.2.3.app.tar.gz')
        .writeAsString('macos');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'v1.2.3',
      baseDownloadUrl:
          'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    expect(platforms['windows-x64'], isNull);
    expect(platforms['macos-universal'], isNotNull);
    expect(platforms['linux-x64'], isNotNull);
  });

  test('generateUpdateManifest rejects non-semver release versions', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_android_universal_tag_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-android-v1.2.3.apk')
        .writeAsString('android');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: 'v1.2.3-arm64-hotfix',
        baseDownloadUrl:
            'https://github.com/dale0525/SecondLoop/releases/download/v1.2.3-arm64-hotfix',
      ),
      throwsArgumentError,
    );
  });

  test('generateUpdateManifest signs latest.json with ed25519 seed', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_sig_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    final seed = List<int>.generate(32, (index) => index + 1);
    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
      signingPrivateKeyBase64: base64Encode(seed),
    );

    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final verified = await algorithm.verify(
      utf8.encode(generated.jsonText),
      signature: Signature(
        base64Decode(generated.signatureBase64!),
        publicKey: publicKey,
      ),
    );

    expect(verified, isTrue);
  });
}

String _hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
