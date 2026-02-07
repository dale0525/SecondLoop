import 'package:flutter_test/flutter_test.dart';

import '../../tools/prepare_bundled_ffmpeg_lib.dart';

void main() {
  test('parseDesktopPlatform parses supported names', () {
    expect(parseDesktopPlatform('macos'), DesktopPlatform.macos);
    expect(parseDesktopPlatform('linux'), DesktopPlatform.linux);
    expect(parseDesktopPlatform('windows'), DesktopPlatform.windows);
    expect(parseDesktopPlatform('win'), DesktopPlatform.windows);
  });

  test('parseDesktopPlatform throws on unsupported name', () {
    expect(
      () => parseDesktopPlatform('android'),
      throwsA(isA<FormatException>()),
    );
  });

  test('bundledRelativePath returns expected asset paths', () {
    expect(
      bundledRelativePath(DesktopPlatform.macos),
      'assets/bin/ffmpeg/macos/ffmpeg',
    );
    expect(
      bundledRelativePath(DesktopPlatform.linux),
      'assets/bin/ffmpeg/linux/ffmpeg',
    );
    expect(
      bundledRelativePath(DesktopPlatform.windows),
      'assets/bin/ffmpeg/windows/ffmpeg.exe',
    );
  });

  test('resolveFfmpegFromPath resolves first existing unix executable', () {
    final existing = <String>{
      '/opt/homebrew/bin/ffmpeg',
    };

    final resolved = resolveFfmpegFromPath(
      pathEnv: '/usr/bin:/opt/homebrew/bin:/bin',
      platform: DesktopPlatform.macos,
      pathSeparator: ':',
      isFile: existing.contains,
    );

    expect(resolved, '/opt/homebrew/bin/ffmpeg');
  });

  test('resolveFfmpegFromPath prioritizes ffmpeg.exe on windows', () {
    final existing = <String>{
      r'C:\tools\bin\ffmpeg.exe',
      r'C:\tools\bin\ffmpeg',
    };

    final resolved = resolveFfmpegFromPath(
      pathEnv: r'C:\Windows\System32;C:\tools\bin',
      platform: DesktopPlatform.windows,
      pathSeparator: ';',
      isFile: existing.contains,
    );

    expect(resolved, r'C:\tools\bin\ffmpeg.exe');
  });

  test('resolveFfmpegFromPath returns null when missing', () {
    final resolved = resolveFfmpegFromPath(
      pathEnv: '/usr/bin:/bin',
      platform: DesktopPlatform.linux,
      pathSeparator: ':',
      isFile: (_) => false,
    );

    expect(resolved, isNull);
  });

  test('resolveFfmpegFromProjectPaths prefers .tools platform binary', () {
    final existing = <String>{
      '/repo/.tools/ffmpeg/macos/ffmpeg',
      '/repo/.pixi/envs/default/bin/ffmpeg',
    };

    final resolved = resolveFfmpegFromProjectPaths(
      projectRoot: '/repo',
      platform: DesktopPlatform.macos,
      isFile: existing.contains,
    );

    expect(resolved, '/repo/.tools/ffmpeg/macos/ffmpeg');
  });

  test('resolveFfmpegFromProjectPaths falls back to .pixi env binary', () {
    final existing = <String>{
      '/repo/.pixi/envs/default/bin/ffmpeg',
    };

    final resolved = resolveFfmpegFromProjectPaths(
      projectRoot: '/repo',
      platform: DesktopPlatform.linux,
      isFile: existing.contains,
    );

    expect(resolved, '/repo/.pixi/envs/default/bin/ffmpeg');
  });

  test('resolveFfmpegFromProjectPaths uses windows Library/bin first', () {
    final existing = <String>{
      r'C:\repo\.pixi\envs\default\Library\bin\ffmpeg.exe',
      r'C:\repo\.pixi\envs\default\bin\ffmpeg.exe',
    };

    final resolved = resolveFfmpegFromProjectPaths(
      projectRoot: r'C:\repo',
      platform: DesktopPlatform.windows,
      isFile: existing.contains,
    );

    expect(resolved, r'C:\repo\.pixi\envs\default\Library\bin\ffmpeg.exe');
  });
}
