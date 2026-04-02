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

  test('generateUpdateManifest records exact windows app id', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_appid_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('stable');
    await File(
      '${tempDir.path}/com.secondloop.secondloopdev-1.2.3-devwin-full.nupkg',
    ).writeAsString('dev');
    await File('${tempDir.path}/releases.win.json').writeAsString('{}');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(windows['name'], 'com.secondloop.secondloop-1.2.3-full.nupkg');
    expect(windows['app_id'], 'com.secondloop.secondloop');
  });

  test('generateUpdateManifest rejects unsupported windows app ids', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_invalid_appid_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('stable');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
        windowsAppId: 'com.secondloop.secondloopbeta',
      ),
      throwsArgumentError,
    );
  });

  test(
      'generateUpdateManifest picks matching windows package for manifest version',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_latest_pkg_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.2-full.nupkg')
        .writeAsString('older');
    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('newer');
    await File('${tempDir.path}/releases.win.json').writeAsString('{}');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.2',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(windows['name'], 'com.secondloop.secondloop-1.2.2-full.nupkg');
  });

  test('generateUpdateManifest rejects mixed-version macOS and Linux assets',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_mixed_archive_versions_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-macos-v1.2.2.app.tar.gz')
        .writeAsString('macos-older');
    await File('${tempDir.path}/SecondLoop-macos-v1.2.3.app.tar.gz')
        .writeAsString('macos-newer');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.2.tar.gz')
        .writeAsString('linux-older');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux-newer');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.2',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final macos = platforms['macos-universal'] as Map<String, Object?>;
    final linux = platforms['linux-x64'] as Map<String, Object?>;

    expect(macos['name'], 'SecondLoop-macos-v1.2.2.app.tar.gz');
    expect(linux['name'], 'SecondLoop-linux-x64-v1.2.2.tar.gz');
  });

  test(
      'generateUpdateManifest accepts architecture-specific macOS managed archives',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_macos_archives_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-macos-arm64-v1.2.3.app.tar.gz')
        .writeAsString('macos-arm64');
    await File('${tempDir.path}/SecondLoop-macos-x64-v1.2.3.app.tar.gz')
        .writeAsString('macos-x64');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final macos = platforms['macos-universal'] as List<Object?>;

    expect(macos, hasLength(2));
    expect(
      macos.whereType<Map<String, Object?>>().map((entry) => entry['name']),
      containsAll(<String>[
        'SecondLoop-macos-arm64-v1.2.3.app.tar.gz',
        'SecondLoop-macos-x64-v1.2.3.app.tar.gz',
      ]),
    );
  });

  test(
      'generateUpdateManifest rejects missing matching windows package version',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_missing_windows_version_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.4-full.nupkg')
        .writeAsString('newer');
    await File('${tempDir.path}/releases.win.json').writeAsString('{}');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
      ),
      throwsStateError,
    );
  });

  test(
      'generateUpdateManifest picks releases metadata for selected package channel',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_release_channel_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File(
      '${tempDir.path}/com.secondloop.secondloopdev-1.2.3-devwin-full.nupkg',
    ).writeAsString('dev');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');
    await File('${tempDir.path}/releases.devwin.json').writeAsString('dev');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
      windowsAppId: 'com.secondloop.secondloopdev',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(
      windows['releases_url'],
      'https://example.com/downloads/releases.devwin.json',
    );
  });

  test('generateUpdateManifest normalizes uppercase V version prefixes',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_uppercase_v_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: 'V1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    expect(generated.manifest['version'], '1.2.3');
    expect(generated.manifest['tag_name'], 'v1.2.3');
  });

  test('generateUpdateManifest rejects non-strict manifest versions', () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_reject_non_strict_versions_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3.4',
        baseDownloadUrl: 'https://example.com/downloads/',
      ),
      throwsArgumentError,
    );

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3-rc.1',
        baseDownloadUrl: 'https://example.com/downloads/',
      ),
      throwsArgumentError,
    );
  });

  test(
      'generateUpdateManifest rejects explicit windows channel with prerelease package names',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('update_manifest_prerelease_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File(
      '${tempDir.path}/com.secondloop.secondloopdev-1.2.3-rc.1-devwin-full.nupkg',
    ).writeAsString('rc');
    await File('${tempDir.path}/releases.devwin.json').writeAsString('{}');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
        windowsAppId: 'com.secondloop.secondloopdev',
        windowsChannel: 'devwin',
      ),
      throwsStateError,
    );
  });

  test(
      'generateUpdateManifest rejects explicit windows channel when package is missing',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_missing_explicit_windows_channel_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-win-full.nupkg')
        .writeAsString('stable');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');
    await File('${tempDir.path}/releases.nightly.json')
        .writeAsString('nightly');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
        windowsChannel: 'nightly',
      ),
      throwsStateError,
    );
  });

  test(
      'generateUpdateManifest ignores unknown channel-suffixed windows package when stable package is unambiguous',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_unknown_windows_channel_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('stable');
    await File(
            '${tempDir.path}/com.secondloop.secondloop-1.2.3-nightly-full.nupkg')
        .writeAsString('nightly');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(windows['name'], 'com.secondloop.secondloop-1.2.3-full.nupkg');
    expect(
      windows['releases_url'],
      'https://example.com/downloads/releases.win.json',
    );
  });

  test(
      'generateUpdateManifest ignores unknown channel variants when no stable package matches the requested version',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_ignore_unknown_channel_variant_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File(
            '${tempDir.path}/com.secondloop.secondloop-1.2.3-mystery-full.nupkg')
        .writeAsString('mystery');
    await File('${tempDir.path}/SecondLoop-linux-x64-v1.2.3.tar.gz')
        .writeAsString('linux');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    expect(platforms.containsKey('windows-x64'), isFalse);
    expect(platforms['linux-x64'], isNotNull);
  });

  test(
      'generateUpdateManifest rejects explicit windows channel when releases metadata is missing',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_missing_explicit_windows_metadata_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File(
            '${tempDir.path}/com.secondloop.secondloop-1.2.3-nightly-full.nupkg')
        .writeAsString('nightly');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
        windowsChannel: 'nightly',
      ),
      throwsStateError,
    );
  });

  test(
      'generateUpdateManifest rejects ambiguous windows channels without explicit selection',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_ambiguous_windows_channel_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-win-full.nupkg')
        .writeAsString('stable');
    await File(
      '${tempDir.path}/com.secondloop.secondloop-1.2.3-nightly-full.nupkg',
    ).writeAsString('nightly');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');
    await File('${tempDir.path}/releases.nightly.json')
        .writeAsString('nightly');

    await expectLater(
      () => generateUpdateManifest(
        inputDirPath: tempDir.path,
        version: '1.2.3',
        baseDownloadUrl: 'https://example.com/downloads/',
      ),
      throwsStateError,
    );
  });

  test(
      'generateUpdateManifest selects the explicitly requested windows channel',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_explicit_windows_channel_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-win-full.nupkg')
        .writeAsString('stable');
    await File(
      '${tempDir.path}/com.secondloop.secondloop-1.2.4-nightly-full.nupkg',
    ).writeAsString('nightly');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');
    await File('${tempDir.path}/releases.nightly.json')
        .writeAsString('nightly');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.4',
      baseDownloadUrl: 'https://example.com/downloads/',
      windowsChannel: 'nightly',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(
      windows['name'],
      'com.secondloop.secondloop-1.2.4-nightly-full.nupkg',
    );
    expect(
      windows['releases_url'],
      'https://example.com/downloads/releases.nightly.json',
    );
  });

  test(
      'generateUpdateManifest ignores unrelated unknown channel variants when explicit windows channel matches',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_explicit_channel_unknown_variant_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File(
            '${tempDir.path}/com.secondloop.secondloop-1.2.4-nightly-full.nupkg')
        .writeAsString('nightly');
    await File(
            '${tempDir.path}/com.secondloop.secondloop-1.2.4-mystery-full.nupkg')
        .writeAsString('mystery');
    await File('${tempDir.path}/releases.nightly.json')
        .writeAsString('nightly');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.4',
      baseDownloadUrl: 'https://example.com/downloads/',
      windowsChannel: 'nightly',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(
      windows['name'],
      'com.secondloop.secondloop-1.2.4-nightly-full.nupkg',
    );
    expect(
      windows['releases_url'],
      'https://example.com/downloads/releases.nightly.json',
    );
  });

  test(
      'generateUpdateManifest prefers channel-specific stable package over legacy stable package',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('update_manifest_prefer_channel_specific_stable_');
    addTearDown(() => tempDir.delete(recursive: true));

    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-full.nupkg')
        .writeAsString('legacy-stable');
    await File('${tempDir.path}/com.secondloop.secondloop-1.2.3-win-full.nupkg')
        .writeAsString('channel-stable');
    await File('${tempDir.path}/releases.win.json').writeAsString('stable');

    final generated = await generateUpdateManifest(
      inputDirPath: tempDir.path,
      version: '1.2.3',
      baseDownloadUrl: 'https://example.com/downloads/',
    );

    final platforms = generated.manifest['platforms'] as Map<String, Object?>;
    final windows = platforms['windows-x64'] as Map<String, Object?>;

    expect(windows['name'], 'com.secondloop.secondloop-1.2.3-win-full.nupkg');
    expect(
      windows['package_url'],
      'https://example.com/downloads/com.secondloop.secondloop-1.2.3-win-full.nupkg',
    );
  });
}

String _hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
