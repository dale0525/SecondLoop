import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
        <String, Object>{'asset': 'assets/icon/tray_icon.png', 'dpr': 2.0},
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

    final result = await _runPruneTool(buildDir);

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
    expect(
      updatedAssetManifestBin['assets/icon/tray_icon.png'],
      <Map<Object?, Object?>>[
        <Object?, Object?>{
          'asset': 'assets/icon/tray_icon.png',
          'dpr': 2.0,
        },
      ],
    );

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
    expect(
      updatedAssetManifestBinJson['assets/icon/tray_icon.png'],
      <Map<Object?, Object?>>[
        <Object?, Object?>{
          'asset': 'assets/icon/tray_icon.png',
          'dpr': 2.0,
        },
      ],
    );
  });

  test(
      'prune web build ffmpeg script preserves valid service worker syntax when first resource is pruned',
      () async {
    final buildDir = await _createTempBuildDir();
    final ffmpegDir = Directory(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}assets${Platform.pathSeparator}bin${Platform.pathSeparator}ffmpeg',
    );
    await ffmpegDir.create(recursive: true);
    await File(
      '${ffmpegDir.path}${Platform.pathSeparator}linux${Platform.pathSeparator}ffmpeg',
    ).create(recursive: true);

    final assetManifest = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.json',
    );
    await assetManifest.create(recursive: true);
    await assetManifest.writeAsString(jsonEncode(<String, Object>{
      'assets/bin/ffmpeg/linux/ffmpeg': <String>[
        'assets/bin/ffmpeg/linux/ffmpeg'
      ],
      'assets/icon/tray_icon.png': <String>['assets/icon/tray_icon.png'],
    }));

    final assetManifestBin = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin',
    );
    await assetManifestBin.writeAsBytes(
      _encodeBinaryManifest(<String, Object>{
        'assets/bin/ffmpeg/linux/ffmpeg': <Map<String, Object>>[
          <String, Object>{'asset': 'assets/bin/ffmpeg/linux/ffmpeg'},
        ],
        'assets/icon/tray_icon.png': <Map<String, Object>>[
          <String, Object>{'asset': 'assets/icon/tray_icon.png', 'dpr': 3.0},
        ],
      }),
    );

    final assetManifestBinJson = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin.json',
    );
    await assetManifestBinJson.create(recursive: true);
    await assetManifestBinJson.writeAsString(
      jsonEncode(
        base64.encode(
          _encodeBinaryManifest(<String, Object>{
            'assets/bin/ffmpeg/linux/ffmpeg': <Map<String, Object>>[
              <String, Object>{'asset': 'assets/bin/ffmpeg/linux/ffmpeg'},
            ],
            'assets/icon/tray_icon.png': <Map<String, Object>>[
              <String, Object>{
                'asset': 'assets/icon/tray_icon.png',
                'dpr': 3.0
              },
            ],
          }),
        ),
      ),
    );

    final serviceWorker = File(
      '${buildDir.path}${Platform.pathSeparator}flutter_service_worker.js',
    );
    await serviceWorker.writeAsString(
      'const RESOURCES = {"assets/assets/bin/ffmpeg/linux/ffmpeg": "hash-a",\n'
      '"assets/assets/icon/tray_icon.png": "hash-c"};\n',
    );

    final result = await _runPruneTool(buildDir);
    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );

    final updatedServiceWorker = await serviceWorker.readAsString();
    expect(updatedServiceWorker, contains('const RESOURCES = {'));
    expect(
        updatedServiceWorker, contains('"assets/assets/icon/tray_icon.png"'));
    expect(
      updatedServiceWorker,
      isNot(contains('"assets/assets/bin/ffmpeg/linux/ffmpeg"')),
    );
    expect(updatedServiceWorker.trimRight(), endsWith('};'));
  });

  test(
      'prune web build ffmpeg script refreshes manifest hashes in service worker',
      () async {
    final buildDir = await _createTempBuildDir();
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
        <String, Object>{'asset': 'assets/icon/tray_icon.png', 'dpr': 1.5},
      ],
    });
    await assetManifestBin.writeAsBytes(encodedAssetManifestBin);

    final assetManifestBinJson = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin.json',
    );
    await assetManifestBinJson.create(recursive: true);
    await assetManifestBinJson.writeAsString(
      jsonEncode(base64.encode(encodedAssetManifestBin)),
    );

    final serviceWorker = File(
      '${buildDir.path}${Platform.pathSeparator}flutter_service_worker.js',
    );
    await serviceWorker.writeAsString(
      'const RESOURCES = {"assets/AssetManifest.json": "manifest-json-before",\n'
      '"assets/AssetManifest.bin": "manifest-bin-before",\n'
      '"assets/AssetManifest.bin.json": "manifest-bin-json-before",\n'
      '"assets/assets/bin/ffmpeg/linux/ffmpeg": "hash-a",\n'
      '"assets/assets/bin/ffmpeg/README.md": "hash-b",\n'
      '"assets/assets/icon/tray_icon.png": "hash-c"};\n',
    );

    final result = await _runPruneTool(buildDir);
    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );

    final updatedServiceWorker = await serviceWorker.readAsString();
    expect(updatedServiceWorker, contains('"assets/AssetManifest.json": "'));
    expect(updatedServiceWorker, contains('"assets/AssetManifest.bin": "'));
    expect(
        updatedServiceWorker, contains('"assets/AssetManifest.bin.json": "'));
    expect(
      updatedServiceWorker,
      isNot(contains('"assets/AssetManifest.json": "manifest-json-before"')),
    );
    expect(
      updatedServiceWorker,
      isNot(contains('"assets/AssetManifest.bin": "manifest-bin-before"')),
    );
    expect(
      updatedServiceWorker,
      isNot(contains(
          '"assets/AssetManifest.bin.json": "manifest-bin-json-before"')),
    );
    expect(
        updatedServiceWorker, contains('"assets/assets/icon/tray_icon.png"'));
  });

  test(
      'prune web build ffmpeg script counts removed service worker resources without going negative',
      () async {
    final buildDir = await _createTempBuildDir();
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

    final assetManifestBinJson = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin.json',
    );
    await assetManifestBinJson.create(recursive: true);
    await assetManifestBinJson.writeAsString(
      jsonEncode(base64.encode(encodedAssetManifestBin)),
    );

    final serviceWorker = File(
      '${buildDir.path}${Platform.pathSeparator}flutter_service_worker.js',
    );
    await serviceWorker.writeAsString(
      'const RESOURCES = {"assets/assets/bin/ffmpeg/linux/ffmpeg": "hash-a",\n'
      '"assets/assets/bin/ffmpeg/README.md": "hash-b",\n'
      '"assets/assets/icon/tray_icon.png": "hash-c"};\n',
    );

    final result = await _runPruneTool(buildDir);
    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    expect(
      result.stdout,
      contains('2 service worker resources'),
    );
    expect(
      result.stdout,
      isNot(contains('pruned -')),
    );
  });

  test(
      'prune web build ffmpeg script accepts empty AssetManifest.bin.json payload',
      () async {
    final buildDir = await _createTempBuildDir();
    final assetManifest = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.json',
    );
    await assetManifest.create(recursive: true);
    await assetManifest.writeAsString('{}');

    final assetManifestBin = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin',
    );
    await assetManifestBin.writeAsBytes(
      _encodeBinaryManifest(<String, Object>{}),
    );

    final assetManifestBinJson = File(
      '${buildDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}AssetManifest.bin.json',
    );
    await assetManifestBinJson.create(recursive: true);
    await assetManifestBinJson.writeAsString('""');

    final serviceWorker = File(
      '${buildDir.path}${Platform.pathSeparator}flutter_service_worker.js',
    );
    await serviceWorker.writeAsString('const RESOURCES = {};\n');

    final result = await _runPruneTool(buildDir);
    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  });

  test(
      'prune web build ffmpeg helper prefers flutter on PATH when injected flutter is unset',
      () {
    final invocation = _resolvePruneToolInvocation(
      buildDirPath: '/tmp/build/web',
      environment: <String, String>{
        'PATH': '/usr/local/bin:/usr/bin',
      },
      executableExists: (candidate) =>
          candidate == '/usr/local/bin/flutter' || candidate == '/usr/bin/pixi',
    );

    expect(invocation.executable, 'flutter');
    expect(
      invocation.arguments,
      <String>[
        'pub',
        'run',
        'tools/prune_web_build_ffmpeg.dart',
        '--build-dir',
        '/tmp/build/web',
      ],
    );
  });

  test(
      'prune web build ffmpeg helper falls back to pixi when flutter is unavailable',
      () {
    final invocation = _resolvePruneToolInvocation(
      buildDirPath: '/tmp/build/web',
      environment: <String, String>{
        'PATH': '/usr/local/bin:/usr/bin',
      },
      executableExists: (candidate) => candidate == '/usr/bin/pixi',
    );

    expect(invocation.executable, 'pixi');
    expect(
      invocation.arguments,
      <String>[
        'run',
        'flutter',
        'pub',
        'run tools/prune_web_build_ffmpeg.dart --build-dir /tmp/build/web',
      ],
    );
  });
}

Future<Directory> _createTempBuildDir() async {
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
  await Directory(
    '${buildDir.path}${Platform.pathSeparator}assets',
  ).create(recursive: true);
  return buildDir;
}

Future<ProcessResult> _runPruneTool(Directory buildDir) {
  final invocation = _resolvePruneToolInvocation(
    buildDirPath: buildDir.path,
    environment: Platform.environment,
    executableExists: (candidate) => File(candidate).existsSync(),
  );
  return Process.run(
    invocation.executable,
    invocation.arguments,
    workingDirectory: Directory.current.path,
  );
}

_PruneToolInvocation _resolvePruneToolInvocation({
  required String buildDirPath,
  required Map<String, String> environment,
  required bool Function(String candidate) executableExists,
}) {
  final flutterBin = environment['SECONDLOOP_FLUTTER_BIN']?.trim();
  if (flutterBin != null && flutterBin.isNotEmpty) {
    return _PruneToolInvocation(
      executable: flutterBin,
      arguments: <String>[
        'pub',
        'run',
        'tools/prune_web_build_ffmpeg.dart',
        '--build-dir',
        buildDirPath,
      ],
    );
  }

  if (_hasExecutableOnPath(
    executableName: 'flutter',
    environment: environment,
    executableExists: executableExists,
  )) {
    return _PruneToolInvocation(
      executable: 'flutter',
      arguments: <String>[
        'pub',
        'run',
        'tools/prune_web_build_ffmpeg.dart',
        '--build-dir',
        buildDirPath,
      ],
    );
  }

  return _PruneToolInvocation(
    executable: 'pixi',
    arguments: <String>[
      'run',
      'flutter',
      'pub',
      'run tools/prune_web_build_ffmpeg.dart --build-dir $buildDirPath',
    ],
  );
}

bool _hasExecutableOnPath({
  required String executableName,
  required Map<String, String> environment,
  required bool Function(String candidate) executableExists,
}) {
  for (final candidate
      in _executableCandidatesOnPath(executableName, environment)) {
    if (executableExists(candidate)) {
      return true;
    }
  }
  return false;
}

Iterable<String> _executableCandidatesOnPath(
  String executableName,
  Map<String, String> environment,
) sync* {
  final path = environment['PATH'];
  if (path == null || path.isEmpty) {
    return;
  }

  final pathSeparator = Platform.isWindows ? ';' : ':';
  final pathext = Platform.isWindows
      ? (environment['PATHEXT']
              ?.split(';')
              .where((entry) => entry.isNotEmpty) ??
          const <String>['.EXE', '.BAT', '.CMD', '.COM'])
      : const <String>[''];
  final hasExplicitExtension =
      Platform.isWindows && executableName.contains('.');

  for (final rawDirectory in path.split(pathSeparator)) {
    final directory = rawDirectory.trim();
    if (directory.isEmpty) {
      continue;
    }

    if (hasExplicitExtension) {
      yield '$directory${Platform.pathSeparator}$executableName';
      continue;
    }

    for (final extension in pathext) {
      yield '$directory${Platform.pathSeparator}$executableName$extension';
    }
  }
}

class _PruneToolInvocation {
  const _PruneToolInvocation({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

List<int> _encodeBinaryManifest(Map<String, Object> manifest) {
  final message = const StandardMessageCodec().encodeMessage(manifest)!;
  return message.buffer.asUint8List(0, message.lengthInBytes);
}

Map<Object?, Object?> _decodeBinaryManifest(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return const StandardMessageCodec().decodeMessage(data)!
      as Map<Object?, Object?>;
}
