import 'dart:io';

import 'prepare_bundled_ffmpeg_lib.dart';

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);

  if (config.showHelp) {
    _printUsage();
    return;
  }

  final platform = config.platform ?? _detectHostDesktopPlatform();
  final sourcePath = config.sourceBin ??
      resolveFfmpegFromProjectPaths(
        projectRoot: Directory.current.path,
        platform: platform,
        isFile: (candidate) => File(candidate).existsSync(),
      ) ??
      resolveFfmpegFromPath(
        pathEnv: Platform.environment['PATH'] ?? '',
        platform: platform,
        pathSeparator: platform == DesktopPlatform.windows ? ';' : ':',
        isFile: (candidate) => File(candidate).existsSync(),
      );

  if (sourcePath == null || sourcePath.trim().isEmpty) {
    stderr.writeln(
      'prepare-bundled-ffmpeg: unable to locate ffmpeg in '
      'project paths (.tool/.pixi) or PATH. '
      'Provide --source-bin=/absolute/path/to/ffmpeg',
    );
    exit(2);
  }

  final resolvedSourcePath = resolveBundledFfmpegSource(
    sourcePath: sourcePath,
    platform: platform,
    chocolateyInstall: Platform.environment['ChocolateyInstall'],
    isFile: (candidate) => File(candidate).existsSync(),
  );
  final sourceFile = File(resolvedSourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln(
      'prepare-bundled-ffmpeg: source ffmpeg does not exist: $resolvedSourcePath',
    );
    exit(2);
  }

  if (!_pathsEqual(sourcePath, resolvedSourcePath, platform)) {
    stdout.writeln(
      'prepare-bundled-ffmpeg: resolved source $sourcePath -> $resolvedSourcePath',
    );
  }

  final outputRoot = config.outputRoot ??
      _joinAll(
        Directory.current.path,
        <String>['assets', 'bin', 'ffmpeg'],
      );
  final targetPath = _joinAll(
    outputRoot,
    <String>[
      desktopPlatformFolderName(platform),
      bundledExecutableName(platform),
    ],
  );

  if (config.dryRun) {
    stdout.writeln('prepare-bundled-ffmpeg dry-run');
    stdout.writeln('platform: ${desktopPlatformFolderName(platform)}');
    stdout.writeln('source:   ${sourceFile.absolute.path}');
    stdout.writeln('target:   $targetPath');
    return;
  }

  final sourceVerify = await Process.run(
    sourceFile.absolute.path,
    const <String>['-version'],
  );
  if (sourceVerify.exitCode != 0) {
    stderr.writeln(
      'prepare-bundled-ffmpeg: source ffmpeg verification failed '
      '(exit=${sourceVerify.exitCode})',
    );
    final sourceVerifyStderr = '${sourceVerify.stderr}'.trim();
    if (sourceVerifyStderr.isNotEmpty) {
      stderr.writeln(sourceVerifyStderr);
    }
    exit(sourceVerify.exitCode == 0 ? 1 : sourceVerify.exitCode);
  }

  final targetFile = File(targetPath);
  targetFile.parent.createSync(recursive: true);

  sourceFile.copySync(targetPath);

  if (platform != DesktopPlatform.windows) {
    final chmodResult =
        await Process.run('chmod', <String>['0755', targetPath]);
    if (chmodResult.exitCode != 0) {
      stderr.writeln('prepare-bundled-ffmpeg: chmod failed for $targetPath');
      stderr.writeln('${chmodResult.stderr}'.trim());
      exit(chmodResult.exitCode == 0 ? 1 : chmodResult.exitCode);
    }
  }

  final verify = await Process.run(targetPath, const <String>['-version']);
  if (verify.exitCode != 0) {
    stderr.writeln(
      'prepare-bundled-ffmpeg: bundled ffmpeg verification failed '
      '(exit=${verify.exitCode})',
    );
    final verifyStderr = '${verify.stderr}'.trim();
    final verifyStdout = '${verify.stdout}'.trim();
    if (verifyStderr.isNotEmpty) {
      stderr.writeln(verifyStderr);
    } else if (verifyStdout.isNotEmpty) {
      stderr.writeln(verifyStdout);
    }
    exit(verify.exitCode == 0 ? 1 : verify.exitCode);
  }

  final firstLine = '${verify.stdout}'.split('\n').first.trim();
  stdout.writeln(
    'prepare-bundled-ffmpeg: copied ${sourceFile.absolute.path} -> $targetPath',
  );
  if (firstLine.isNotEmpty) {
    stdout.writeln('prepare-bundled-ffmpeg: $firstLine');
  }
}

class _Config {
  const _Config({
    required this.showHelp,
    required this.dryRun,
    required this.platform,
    required this.sourceBin,
    required this.outputRoot,
  });

  final bool showHelp;
  final bool dryRun;
  final DesktopPlatform? platform;
  final String? sourceBin;
  final String? outputRoot;
}

_Config _parseArgs(List<String> args) {
  var showHelp = false;
  var dryRun = false;
  DesktopPlatform? platform;
  String? sourceBin;
  String? outputRoot;

  String? takeValue(int index, String flagName) {
    if (index + 1 >= args.length) {
      stderr.writeln('prepare-bundled-ffmpeg: missing value for $flagName');
      exit(2);
    }
    return args[index + 1];
  }

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      showHelp = true;
      continue;
    }
    if (arg == '--') {
      continue;
    }
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }

    if (arg.startsWith('--platform=')) {
      final value = arg.substring('--platform='.length);
      platform = parseDesktopPlatform(value);
      continue;
    }
    if (arg == '--platform') {
      platform = parseDesktopPlatform(takeValue(i, '--platform')!);
      i += 1;
      continue;
    }

    if (arg.startsWith('--source-bin=')) {
      sourceBin = arg.substring('--source-bin='.length);
      continue;
    }
    if (arg == '--source-bin') {
      sourceBin = takeValue(i, '--source-bin');
      i += 1;
      continue;
    }

    if (arg.startsWith('--output-root=')) {
      outputRoot = arg.substring('--output-root='.length);
      continue;
    }
    if (arg == '--output-root') {
      outputRoot = takeValue(i, '--output-root');
      i += 1;
      continue;
    }

    stderr.writeln('prepare-bundled-ffmpeg: unknown argument: $arg');
    exit(2);
  }

  return _Config(
    showHelp: showHelp,
    dryRun: dryRun,
    platform: platform,
    sourceBin: sourceBin,
    outputRoot: outputRoot,
  );
}

DesktopPlatform _detectHostDesktopPlatform() {
  if (Platform.isMacOS) return DesktopPlatform.macos;
  if (Platform.isLinux) return DesktopPlatform.linux;
  if (Platform.isWindows) return DesktopPlatform.windows;
  throw UnsupportedError(
    'prepare-bundled-ffmpeg only supports desktop hosts (macOS/Linux/Windows).',
  );
}

String _joinAll(String first, List<String> rest) {
  var out = first;
  for (final part in rest) {
    out = _join(out, part);
  }
  return out;
}

String _join(String base, String part) {
  final separator = Platform.pathSeparator;
  if (base.endsWith(separator)) return '$base$part';
  return '$base$separator$part';
}

bool _pathsEqual(String left, String right, DesktopPlatform platform) {
  if (platform != DesktopPlatform.windows) return left == right;
  return _normalizeWindowsPath(left) == _normalizeWindowsPath(right);
}

String _normalizeWindowsPath(String value) {
  return value.replaceAll('/', r'\').toLowerCase();
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tools/prepare_bundled_ffmpeg.dart [options]

Options:
  --platform <macos|linux|windows>  Target desktop platform (default: current host)
  --source-bin <path>               Source ffmpeg binary path (default: resolved from PATH)
  --output-root <path>              Output root (default: ./assets/bin/ffmpeg)
  --dry-run                         Print resolved values only
  -h, --help                        Show help
''');
}
