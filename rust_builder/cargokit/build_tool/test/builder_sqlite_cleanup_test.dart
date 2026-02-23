import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/builder.dart';
import '../lib/src/cargo.dart';
import '../lib/src/options.dart';
import '../lib/src/target.dart';
import '../lib/src/util.dart';

void main() {
  TestRunCommandResult? _stubCargoBuildFailureThenSuccess(
    TestRunCommandArgs args,
    int attempt,
  ) {
    bool isCargoBuild = false;
    bool isCargoClean = false;

    if (args.executable == 'rustup' && args.arguments.length >= 4) {
      final cmd = args.arguments[2];
      final cargoSubcommand = args.arguments[3];
      isCargoBuild = cmd == 'cargo' && cargoSubcommand == 'build';
      isCargoClean = cmd == 'cargo' && cargoSubcommand == 'clean';
    } else if (args.executable == 'cargo' && args.arguments.isNotEmpty) {
      isCargoBuild = args.arguments.first == 'build';
      isCargoClean = args.arguments.first == 'clean';
    }

    if (isCargoBuild) {
      if (attempt == 1) {
        return TestRunCommandResult(
          exitCode: 101,
          stderr: 'error: could not read out/bindgen.rs: '
              'No such file or directory '
              '(os error 2) libsqlite3-sys',
        );
      }
      return TestRunCommandResult(exitCode: 0);
    }

    if (isCargoClean) {
      return TestRunCommandResult(exitCode: 0);
    }

    return null;
  }

  test('build retries missing bindgen output after deleting stale artifacts',
      () async {
    final previousOverride = testRunCommandOverride;
    addTearDown(() {
      testRunCommandOverride = previousOverride;
    });

    final tmp = await Directory.systemTemp.createTemp('cargokit-build-test-');
    addTearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    final targetTempDir = '${tmp.path}/target';
    final manifestDir = '${tmp.path}/manifest';
    await Directory(targetTempDir).create(recursive: true);
    await Directory(manifestDir).create(recursive: true);

    final staleDirs = <String>[
      '$targetTempDir/armv7-linux-androideabi/release/build/libsqlite3-sys-stale',
      '$targetTempDir/armv7-linux-androideabi/release/.fingerprint/libsqlite3-sys-stale',
      '$targetTempDir/release/build/libsqlite3-sys-stale',
      '$targetTempDir/release/.fingerprint/libsqlite3-sys-stale',
    ];

    for (final stale in staleDirs) {
      await Directory(stale).create(recursive: true);
      await File('$stale/tombstone').writeAsString('stale');
    }

    final staleFiles = <String>[
      '$targetTempDir/armv7-linux-androideabi/release/deps/libsqlite3_sys-stale.rmeta',
      '$targetTempDir/release/deps/libsqlite3_sys-stale.d',
    ];
    for (final stale in staleFiles) {
      final file = File(stale);
      await file.parent.create(recursive: true);
      await file.writeAsString('stale');
    }

    var buildAttempts = 0;
    testRunCommandOverride = (args) {
      final stubbed =
          _stubCargoBuildFailureThenSuccess(args, buildAttempts + 1);
      if (stubbed != null) {
        final isBuild = (args.executable == 'rustup' &&
                args.arguments.length >= 4
            ? args.arguments[3] == 'build'
            : (args.arguments.isNotEmpty && args.arguments.first == 'build'));
        if (isBuild) {
          buildAttempts += 1;
        }
        return stubbed;
      }
      return TestRunCommandResult(exitCode: 0);
    };

    final builder = RustBuilder(
      target: Target(rust: 'armv7-linux-androideabi'),
      environment: BuildEnvironment(
        configuration: BuildConfiguration.release,
        crateOptions: CargokitCrateOptions(
          cargo: {
            BuildConfiguration.release: CargoBuildOptions(
              toolchain: Toolchain.stable,
              flags: const [],
            ),
          },
        ),
        targetTempDir: targetTempDir,
        manifestDir: manifestDir,
        crateInfo: CrateInfo(packageName: 'secondloop_rust'),
        isAndroid: false,
      ),
    );

    final outputDir = await builder.build();
    expect(outputDir, '$targetTempDir/armv7-linux-androideabi/release');
    expect(buildAttempts, 2);

    for (final stale in [...staleDirs, ...staleFiles]) {
      expect(FileSystemEntity.typeSync(stale), FileSystemEntityType.notFound,
          reason: 'stale artifact should be deleted: $stale');
    }
  });
}
