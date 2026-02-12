/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'android_environment.dart';
import 'cargo.dart';
import 'environment.dart';
import 'options.dart';
import 'rustup.dart';
import 'target.dart';
import 'util.dart';

final _log = Logger('builder');

enum BuildConfiguration {
  debug,
  release,
  profile,
}

extension on BuildConfiguration {
  bool get isDebug => this == BuildConfiguration.debug;
  String get rustName => switch (this) {
        BuildConfiguration.debug => 'debug',
        BuildConfiguration.release => 'release',
        BuildConfiguration.profile => 'release',
      };
}

class BuildException implements Exception {
  final String message;

  BuildException(this.message);

  @override
  String toString() {
    return 'BuildException: $message';
  }
}

class BuildEnvironment {
  final BuildConfiguration configuration;
  final CargokitCrateOptions crateOptions;
  final String targetTempDir;
  final String manifestDir;
  final CrateInfo crateInfo;

  final bool isAndroid;
  final String? androidSdkPath;
  final String? androidNdkVersion;
  final int? androidMinSdkVersion;
  final String? javaHome;

  BuildEnvironment({
    required this.configuration,
    required this.crateOptions,
    required this.targetTempDir,
    required this.manifestDir,
    required this.crateInfo,
    required this.isAndroid,
    this.androidSdkPath,
    this.androidNdkVersion,
    this.androidMinSdkVersion,
    this.javaHome,
  });

  static BuildConfiguration parseBuildConfiguration(String value) {
    // XCode configuration adds the flavor to configuration name.
    final firstSegment = value.split('-').first;
    final buildConfiguration = BuildConfiguration.values.firstWhereOrNull(
      (e) => e.name == firstSegment,
    );
    if (buildConfiguration == null) {
      _log.warning('Unknown build configuraiton $value, will assume release');
      return BuildConfiguration.release;
    }
    return buildConfiguration;
  }

  static BuildEnvironment fromEnvironment({
    required bool isAndroid,
  }) {
    final buildConfiguration =
        parseBuildConfiguration(Environment.configuration);
    final manifestDir = Environment.manifestDir;
    final crateOptions = CargokitCrateOptions.load(
      manifestDir: manifestDir,
    );
    final crateInfo = CrateInfo.load(manifestDir);
    return BuildEnvironment(
      configuration: buildConfiguration,
      crateOptions: crateOptions,
      targetTempDir: Environment.targetTempDir,
      manifestDir: manifestDir,
      crateInfo: crateInfo,
      isAndroid: isAndroid,
      androidSdkPath: isAndroid ? Environment.sdkPath : null,
      androidNdkVersion: isAndroid ? Environment.ndkVersion : null,
      androidMinSdkVersion:
          isAndroid ? int.parse(Environment.minSdkVersion) : null,
      javaHome: isAndroid ? Environment.javaHome : null,
    );
  }
}

class RustBuilder {
  final Target target;
  final BuildEnvironment environment;

  RustBuilder({
    required this.target,
    required this.environment,
  });

  void prepare(
    Rustup rustup,
  ) {
    if (Rustup.executablePath() == null) {
      _log.info('rustup not found, skipping toolchain/target installation');
      return;
    }

    final toolchain = _toolchain;
    if (rustup.installedTargets(toolchain) == null) {
      rustup.installToolchain(toolchain);
    }
    if (toolchain == 'nightly') {
      rustup.installRustSrcForNightly();
    }
    if (!rustup.installedTargets(toolchain)!.contains(target.rust)) {
      rustup.installTarget(target.rust, toolchain: toolchain);
    }
  }

  CargoBuildOptions? get _buildOptions =>
      environment.crateOptions.cargo[environment.configuration];

  String get _toolchain => _buildOptions?.toolchain.name ?? 'stable';

  /// Returns the path of directory containing build artifacts.
  Future<String> build() async {
    final extraArgs = _buildOptions?.flags ?? [];
    final manifestPath = path.join(environment.manifestDir, 'Cargo.toml');
    final buildEnvironment = await _buildEnvironment();
    final buildArgs = <String>[
      'build',
      ...extraArgs,
      '--manifest-path',
      manifestPath,
      '-p',
      environment.crateInfo.packageName,
      if (!environment.configuration.isDebug) '--release',
      '--target',
      target.rust,
      '--target-dir',
      environment.targetTempDir,
    ];

    try {
      _runCargoCommand(buildArgs, environment: buildEnvironment);
    } on CommandFailedException catch (error) {
      if (!_isMissingLibsqliteBindgen(error)) {
        rethrow;
      }
      _log.warning(
        'Detected missing libsqlite3-sys bindgen output; cleaning stale '
        'artifacts and retrying once.',
      );
      _cleanLibsqliteBuildArtifacts(
        manifestPath,
        environment: buildEnvironment,
      );
      _runCargoCommand(buildArgs, environment: buildEnvironment);
    }

    return path.join(
      environment.targetTempDir,
      target.rust,
      environment.configuration.rustName,
    );
  }

  bool _isMissingLibsqliteBindgen(CommandFailedException error) {
    final stderr = error.result.stderr.toString();
    return stderr.contains('libsqlite3-sys') &&
        stderr.contains('out/bindgen.rs') &&
        stderr.contains('No such file or directory');
  }

  void _cleanLibsqliteBuildArtifacts(
    String manifestPath, {
    required Map<String, String> environment,
  }) {
    _runCargoCommand(
      [
        'clean',
        '--manifest-path',
        manifestPath,
        '-p',
        'libsqlite3-sys',
        '--target',
        target.rust,
        '--target-dir',
        this.environment.targetTempDir,
      ],
      environment: environment,
    );
  }

  void _runCargoCommand(
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    if (Rustup.executablePath() == null) {
      if (_toolchain != 'stable') {
        throw BuildException(
          'rustup is required for toolchain $_toolchain but was not found; '
          'install rustup or set cargo.toolchain=stable',
        );
      }
      runCommand(
        'cargo',
        arguments,
        environment: environment,
      );
      return;
    }

    runCommand(
      'rustup',
      [
        'run',
        _toolchain,
        'cargo',
        ...arguments,
      ],
      environment: environment,
    );
  }

  Future<Map<String, String>> _buildEnvironment() async {
    if (target.android == null) {
      return {};
    } else {
      final sdkPath = environment.androidSdkPath;
      final ndkVersion = environment.androidNdkVersion;
      final minSdkVersion = environment.androidMinSdkVersion;
      if (sdkPath == null) {
        throw BuildException('androidSdkPath is not set');
      }
      if (ndkVersion == null) {
        throw BuildException('androidNdkVersion is not set');
      }
      if (minSdkVersion == null) {
        throw BuildException('androidMinSdkVersion is not set');
      }
      final env = AndroidEnvironment(
        sdkPath: sdkPath,
        ndkVersion: ndkVersion,
        minSdkVersion: minSdkVersion,
        targetTempDir: environment.targetTempDir,
        target: target,
      );
      if (!env.ndkIsInstalled() && environment.javaHome != null) {
        env.installNdk(javaHome: environment.javaHome!);
      }
      return env.buildEnvironment();
    }
  }
}
