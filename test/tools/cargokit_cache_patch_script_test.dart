import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patch script retries cached Cargokit pub get and removes env dump', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'secondloop_cargokit_patch_test_',
    );

    try {
      final cargokitDir = Directory('${tempDir.path}/plugin/cargokit')
        ..createSync(recursive: true);
      final runBuildTool = File('${cargokitDir.path}/run_build_tool.sh')
        ..writeAsStringSync(_runBuildToolFixture);
      final buildPod = File('${cargokitDir.path}/build_pod.sh')
        ..writeAsStringSync(_buildPodFixture);

      final result = Process.runSync(
        'bash',
        ['scripts/patch_cargokit_pub_get.sh', tempDir.path],
        workingDirectory: Directory.current.path,
      );

      expect(
        result.exitCode,
        0,
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );

      final patchedRunBuildTool = runBuildTool.readAsStringSync();
      expect(
        patchedRunBuildTool,
        contains('clear_pub_advisories_cache()'),
      );
      expect(
        patchedRunBuildTool,
        contains('run_pub_get_with_retry()'),
      );
      expect(
        RegExp(r'"\$DART" pub get --no-precompile')
            .allMatches(patchedRunBuildTool),
        hasLength(2),
      );
      expect(
        RegExp(r'^\s*run_pub_get_with_retry\s*$', multiLine: true)
            .allMatches(patchedRunBuildTool),
        hasLength(2),
      );
      expect(
        patchedRunBuildTool,
        isNot(contains('if run_pub_get_with_retry; then')),
      );

      final patchedBuildPod = buildPod.readAsStringSync();
      expect(patchedBuildPod, isNot(contains('\nenv\n')));

      final rerun = Process.runSync(
        'bash',
        ['scripts/patch_cargokit_pub_get.sh', tempDir.path],
        workingDirectory: Directory.current.path,
      );
      expect(
        rerun.exitCode,
        0,
        reason: 'stdout: ${rerun.stdout}\nstderr: ${rerun.stderr}',
      );
      expect(runBuildTool.readAsStringSync(), patchedRunBuildTool);
      expect(buildPod.readAsStringSync(), patchedBuildPod);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('patch script repairs recursive retry function from older patch', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'secondloop_cargokit_repair_test_',
    );

    try {
      final cargokitDir = Directory('${tempDir.path}/plugin/cargokit')
        ..createSync(recursive: true);
      final runBuildTool = File('${cargokitDir.path}/run_build_tool.sh')
        ..writeAsStringSync(_recursivePatchFixture);

      final result = Process.runSync(
        'bash',
        ['scripts/patch_cargokit_pub_get.sh', tempDir.path],
        workingDirectory: Directory.current.path,
      );

      expect(
        result.exitCode,
        0,
        reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );

      final patchedRunBuildTool = runBuildTool.readAsStringSync();
      expect(
        patchedRunBuildTool,
        isNot(contains('if run_pub_get_with_retry; then')),
      );
      expect(
        RegExp(r'"\$DART" pub get --no-precompile')
            .allMatches(patchedRunBuildTool),
        hasLength(2),
      );
      expect(
        RegExp(r'^\s*run_pub_get_with_retry\s*$', multiLine: true)
            .allMatches(patchedRunBuildTool),
        hasLength(2),
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}

const _runBuildToolFixture = r'''#!/usr/bin/env bash

set -e

BASEDIR=$(dirname "$0")

mkdir -p "$CARGOKIT_TOOL_TEMP_DIR"

cd "$CARGOKIT_TOOL_TEMP_DIR"

BUILD_TOOL_PKG_DIR="$BASEDIR/build_tool"

if [[ -z $FLUTTER_ROOT ]]; then # not defined
  DART=dart
else
  DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
fi

cat << EOF > "pubspec.yaml"
name: build_tool_runner
EOF

if [ ! -f "$PACKAGE_HASH_FILE" ]; then
    "$DART" pub get --no-precompile
    "$DART" compile kernel bin/build_tool_runner.dart
fi

if [ $exit_code == 253 ]; then
  "$DART" pub get --no-precompile
fi
''';

const _buildPodFixture = r'''#!/bin/sh
set -e

BASEDIR=$(dirname "$0")

env

sh "$BASEDIR/run_build_tool.sh" build-pod "$@"
''';

const _recursivePatchFixture = r'''#!/usr/bin/env bash

set -e

if [[ -z $FLUTTER_ROOT ]]; then # not defined
  DART=dart
else
  DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
fi

clear_pub_advisories_cache() {
  return 0
}

run_pub_get_with_retry() {
  if run_pub_get_with_retry; then
    return 0
  fi

  clear_pub_advisories_cache
  run_pub_get_with_retry
}

if [ ! -f "$PACKAGE_HASH_FILE" ]; then
    run_pub_get_with_retry
fi

if [ $exit_code == 253 ]; then
  run_pub_get_with_retry
fi
''';
