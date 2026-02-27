import 'dart:io';

const Set<int> supportedSyncBenchOpsTiers = <int>{1000, 5000, 10000};

const String syncBenchUsage = '''
Usage:
  dart run scripts/bench/sync_bench.dart --backend=<managed-vault|webdav|localdir> --ops=<1000|5000|10000> [options]

Options:
  --latency <ms>          Network latency profile marker (default: 0)
  --report <path>         Output report json file path
  --push-cmd <command>    Shell command for push benchmark timing
  --pull-cmd <command>    Shell command for pull benchmark timing
  --dry-run               Do not execute benchmark commands
  --cpu-avg-pct <value>   Optional CPU average percent (default: 0)
  --mem-peak-mb <value>   Optional memory peak MB (default: 0)
  --retry-count <value>   Optional retry count (default: 0)
  --applied-count <value> Optional applied count (default: 0)
  --notes <text>          Optional report notes
  -h, --help              Show help
''';

enum SyncBenchBackend {
  managedVault('managed-vault'),
  webdav('webdav'),
  localdir('localdir');

  const SyncBenchBackend(this.wireName);

  final String wireName;

  static SyncBenchBackend parse(String raw) {
    final value = raw.trim().toLowerCase();
    return switch (value) {
      'managed-vault' ||
      'managed_vault' ||
      'managedvault' =>
        SyncBenchBackend.managedVault,
      'webdav' => SyncBenchBackend.webdav,
      'localdir' || 'local-dir' => SyncBenchBackend.localdir,
      _ => throw FormatException('Unsupported backend: $raw'),
    };
  }
}

final class SyncBenchConfig {
  const SyncBenchConfig({
    required this.showHelp,
    required this.backend,
    required this.ops,
    required this.latencyMs,
    required this.reportPath,
    required this.pushCommand,
    required this.pullCommand,
    required this.dryRun,
    required this.cpuAvgPct,
    required this.memPeakMb,
    required this.retryCount,
    required this.appliedCount,
    required this.notes,
  });

  final bool showHelp;
  final SyncBenchBackend backend;
  final int ops;
  final int latencyMs;
  final String? reportPath;
  final String? pushCommand;
  final String? pullCommand;
  final bool dryRun;
  final double cpuAvgPct;
  final int memPeakMb;
  final int retryCount;
  final int appliedCount;
  final String? notes;
}

SyncBenchConfig parseSyncBenchArgs(List<String> args) {
  var showHelp = false;
  var dryRun = false;
  SyncBenchBackend? backend;
  int? ops;
  var latencyMs = 0;
  String? reportPath;
  String? pushCommand;
  String? pullCommand;
  var cpuAvgPct = 0.0;
  var memPeakMb = 0;
  var retryCount = 0;
  var appliedCount = 0;
  String? notes;

  String takeValue(int index, String flagName) {
    if (index + 1 >= args.length) {
      throw FormatException('sync-bench: missing value for $flagName');
    }
    return args[index + 1];
  }

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      showHelp = true;
      continue;
    }
    if (arg == '--') continue;
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }

    if (arg.startsWith('--backend=')) {
      backend = SyncBenchBackend.parse(arg.substring('--backend='.length));
      continue;
    }
    if (arg == '--backend') {
      backend = SyncBenchBackend.parse(takeValue(i, '--backend'));
      i += 1;
      continue;
    }

    if (arg.startsWith('--ops=')) {
      ops = int.tryParse(arg.substring('--ops='.length));
      continue;
    }
    if (arg == '--ops') {
      ops = int.tryParse(takeValue(i, '--ops'));
      i += 1;
      continue;
    }

    if (arg.startsWith('--latency=')) {
      latencyMs = int.tryParse(arg.substring('--latency='.length)) ?? -1;
      continue;
    }
    if (arg == '--latency') {
      latencyMs = int.tryParse(takeValue(i, '--latency')) ?? -1;
      i += 1;
      continue;
    }

    if (arg.startsWith('--report=')) {
      reportPath = arg.substring('--report='.length);
      continue;
    }
    if (arg == '--report') {
      reportPath = takeValue(i, '--report');
      i += 1;
      continue;
    }

    if (arg.startsWith('--push-cmd=')) {
      pushCommand = arg.substring('--push-cmd='.length);
      continue;
    }
    if (arg == '--push-cmd') {
      pushCommand = takeValue(i, '--push-cmd');
      i += 1;
      continue;
    }

    if (arg.startsWith('--pull-cmd=')) {
      pullCommand = arg.substring('--pull-cmd='.length);
      continue;
    }
    if (arg == '--pull-cmd') {
      pullCommand = takeValue(i, '--pull-cmd');
      i += 1;
      continue;
    }

    if (arg.startsWith('--cpu-avg-pct=')) {
      cpuAvgPct = double.tryParse(arg.substring('--cpu-avg-pct='.length)) ?? -1;
      continue;
    }
    if (arg == '--cpu-avg-pct') {
      cpuAvgPct = double.tryParse(takeValue(i, '--cpu-avg-pct')) ?? -1;
      i += 1;
      continue;
    }

    if (arg.startsWith('--mem-peak-mb=')) {
      memPeakMb = int.tryParse(arg.substring('--mem-peak-mb='.length)) ?? -1;
      continue;
    }
    if (arg == '--mem-peak-mb') {
      memPeakMb = int.tryParse(takeValue(i, '--mem-peak-mb')) ?? -1;
      i += 1;
      continue;
    }

    if (arg.startsWith('--retry-count=')) {
      retryCount = int.tryParse(arg.substring('--retry-count='.length)) ?? -1;
      continue;
    }
    if (arg == '--retry-count') {
      retryCount = int.tryParse(takeValue(i, '--retry-count')) ?? -1;
      i += 1;
      continue;
    }

    if (arg.startsWith('--applied-count=')) {
      appliedCount =
          int.tryParse(arg.substring('--applied-count='.length)) ?? -1;
      continue;
    }
    if (arg == '--applied-count') {
      appliedCount = int.tryParse(takeValue(i, '--applied-count')) ?? -1;
      i += 1;
      continue;
    }

    if (arg.startsWith('--notes=')) {
      notes = arg.substring('--notes='.length);
      continue;
    }
    if (arg == '--notes') {
      notes = takeValue(i, '--notes');
      i += 1;
      continue;
    }

    throw FormatException('sync-bench: unknown argument: $arg');
  }

  final resolvedBackend = backend ?? SyncBenchBackend.webdav;
  final resolvedOps = ops ?? 1000;
  if (showHelp) {
    return SyncBenchConfig(
      showHelp: true,
      backend: resolvedBackend,
      ops: resolvedOps,
      latencyMs: latencyMs,
      reportPath: reportPath,
      pushCommand: pushCommand,
      pullCommand: pullCommand,
      dryRun: dryRun,
      cpuAvgPct: cpuAvgPct,
      memPeakMb: memPeakMb,
      retryCount: retryCount,
      appliedCount: appliedCount,
      notes: notes,
    );
  }

  if (backend == null) {
    throw const FormatException('sync-bench: --backend is required');
  }
  if (ops == null) {
    throw const FormatException('sync-bench: --ops is required');
  }
  if (!supportedSyncBenchOpsTiers.contains(ops)) {
    throw FormatException(
      'sync-bench: unsupported ops tiers. supported ops tiers: '
      '${supportedSyncBenchOpsTiers.join('/')}, got: $ops',
    );
  }
  if (latencyMs < 0) {
    throw const FormatException('sync-bench: --latency must be >= 0');
  }
  if (cpuAvgPct < 0) {
    throw const FormatException('sync-bench: --cpu-avg-pct must be >= 0');
  }
  if (memPeakMb < 0) {
    throw const FormatException('sync-bench: --mem-peak-mb must be >= 0');
  }
  if (retryCount < 0) {
    throw const FormatException('sync-bench: --retry-count must be >= 0');
  }
  if (appliedCount < 0) {
    throw const FormatException('sync-bench: --applied-count must be >= 0');
  }

  return SyncBenchConfig(
    showHelp: false,
    backend: backend,
    ops: ops,
    latencyMs: latencyMs,
    reportPath: reportPath,
    pushCommand: pushCommand,
    pullCommand: pullCommand,
    dryRun: dryRun,
    cpuAvgPct: cpuAvgPct,
    memPeakMb: memPeakMb,
    retryCount: retryCount,
    appliedCount: appliedCount,
    notes: notes,
  );
}

final class BenchCommandResult {
  const BenchCommandResult({
    required this.exitCode,
    required this.elapsed,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final Duration elapsed;
  final String stdout;
  final String stderr;
}

typedef BenchCommandRunner = Future<BenchCommandResult> Function(
    String command);

final class SyncBenchReport {
  const SyncBenchReport({
    required this.backend,
    required this.ops,
    required this.runId,
    required this.pushMs,
    required this.pullMs,
    required this.cpuAvgPct,
    required this.memPeakMb,
    required this.retryCount,
    required this.appliedCount,
    required this.latencyMs,
    required this.notes,
  });

  final String backend;
  final int ops;
  final String runId;
  final int pushMs;
  final int pullMs;
  final double cpuAvgPct;
  final int memPeakMb;
  final int retryCount;
  final int appliedCount;
  final int latencyMs;
  final String? notes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backend': backend,
      'ops': ops,
      'runId': runId,
      'pushMs': pushMs,
      'pullMs': pullMs,
      'cpuAvgPct': cpuAvgPct,
      'memPeakMb': memPeakMb,
      'retryCount': retryCount,
      'appliedCount': appliedCount,
      'latencyMs': latencyMs,
      'notes': notes,
    };
  }
}

final class _SyncBenchCommandPlan {
  const _SyncBenchCommandPlan({
    required this.pushCommand,
    required this.pullCommand,
    required this.usedDefaultDriver,
  });

  final String? pushCommand;
  final String? pullCommand;
  final bool usedDefaultDriver;
}

Future<SyncBenchReport> runSyncBenchReport(
  SyncBenchConfig config, {
  BenchCommandRunner? commandRunner,
  DateTime Function()? now,
}) async {
  final runner = commandRunner ?? _runShellCommand;
  final nowFn = now ?? DateTime.now;
  final commandPlan = _resolveCommandPlan(config);

  final pushResult = await _runOptionalCommand(commandPlan.pushCommand, runner);
  final pullResult = await _runOptionalCommand(commandPlan.pullCommand, runner);

  final notes = _composeNotes(
    baseNotes: config.notes,
    dryRun: config.dryRun,
    usedDefaultDriver: commandPlan.usedDefaultDriver,
    datasetOps: config.ops,
  );

  return SyncBenchReport(
    backend: config.backend.wireName,
    ops: config.ops,
    runId: nowFn().toUtc().toIso8601String(),
    pushMs: pushResult.elapsed.inMilliseconds,
    pullMs: pullResult.elapsed.inMilliseconds,
    cpuAvgPct: config.cpuAvgPct,
    memPeakMb: config.memPeakMb,
    retryCount: config.retryCount,
    appliedCount: config.appliedCount,
    latencyMs: config.latencyMs,
    notes: notes,
  );
}

_SyncBenchCommandPlan _resolveCommandPlan(SyncBenchConfig config) {
  if (config.dryRun) {
    return const _SyncBenchCommandPlan(
      pushCommand: null,
      pullCommand: null,
      usedDefaultDriver: false,
    );
  }

  final push = _normalizeCommand(config.pushCommand);
  final pull = _normalizeCommand(config.pullCommand);
  final usedDefaultPush = push == null;
  final usedDefaultPull = pull == null;

  return _SyncBenchCommandPlan(
    pushCommand: push ?? _defaultPushCommand(config.backend, ops: config.ops),
    pullCommand: pull ?? _defaultPullCommand(config.backend, ops: config.ops),
    usedDefaultDriver: usedDefaultPush || usedDefaultPull,
  );
}

String? _normalizeCommand(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String _defaultPushCommand(SyncBenchBackend backend, {required int ops}) {
  final base = switch (backend) {
    SyncBenchBackend.webdav =>
      'pixi run cargo test "-p secondloop_rust --test sync_push_retries_with_lower_parallelism"',
    SyncBenchBackend.localdir =>
      'pixi run cargo test "-p secondloop_rust --test sync_localdir_smoke"',
    SyncBenchBackend.managedVault =>
      'pixi run cargo test "-p secondloop_rust --test sync_managed_vault_push_batches_large_payload managed_vault_push_ops_only_splits_large_payload_into_batches"',
  };
  return _withBenchOpsEnv(base, ops);
}

String _defaultPullCommand(SyncBenchBackend backend, {required int ops}) {
  final base = switch (backend) {
    SyncBenchBackend.webdav =>
      'pixi run cargo test "-p secondloop_rust --test sync_end_to_end_inmemory_remote"',
    SyncBenchBackend.localdir =>
      'pixi run cargo test "-p secondloop_rust --test sync_localdir_smoke"',
    SyncBenchBackend.managedVault =>
      'pixi run cargo test "-p secondloop_rust --test sync_managed_vault_pull_bin_smoke managed_vault_pull_bin_copies_messages"',
  };
  return _withBenchOpsEnv(base, ops);
}

String _withBenchOpsEnv(String command, int ops) {
  if (Platform.isWindows) {
    return 'set SYNC_BENCH_OPS=$ops && $command';
  }
  return 'SYNC_BENCH_OPS=$ops $command';
}

Future<BenchCommandResult> _runOptionalCommand(
  String? command,
  BenchCommandRunner runner,
) async {
  final trimmed = command?.trim() ?? '';
  if (trimmed.isEmpty) {
    return const BenchCommandResult(
      exitCode: 0,
      elapsed: Duration.zero,
      stdout: '',
      stderr: '',
    );
  }

  final result = await runner(trimmed);
  if (result.exitCode != 0) {
    throw ProcessException(
      trimmed,
      const <String>[],
      result.stderr.isEmpty ? 'command failed' : result.stderr,
      result.exitCode,
    );
  }
  return result;
}

String? _composeNotes({
  required String? baseNotes,
  required bool dryRun,
  required bool usedDefaultDriver,
  required int datasetOps,
}) {
  final chunks = <String>[];
  final userNotes = baseNotes?.trim();
  if (userNotes != null && userNotes.isNotEmpty) {
    chunks.add(userNotes);
  }
  if (dryRun) {
    chunks.add('dry-run: benchmark commands skipped');
  } else if (usedDefaultDriver) {
    chunks.add('driver: backend default benchmark commands');
    chunks.add('dataset-ops:$datasetOps');
  }
  if (chunks.isEmpty) return null;
  return chunks.join('; ');
}

Future<BenchCommandResult> _runShellCommand(String command) async {
  final stopwatch = Stopwatch()..start();
  late final ProcessResult result;

  if (Platform.isWindows) {
    result = await Process.run('cmd', <String>['/C', command]);
  } else {
    result = await Process.run('/bin/sh', <String>['-lc', command]);
  }

  stopwatch.stop();
  return BenchCommandResult(
    exitCode: result.exitCode,
    elapsed: stopwatch.elapsed,
    stdout: '${result.stdout}',
    stderr: '${result.stderr}',
  );
}
