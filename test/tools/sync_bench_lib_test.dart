import 'package:flutter_test/flutter_test.dart';

import '../../scripts/bench/sync_bench_lib.dart';

void main() {
  test('parseSyncBenchArgs parses baseline config', () {
    final config = parseSyncBenchArgs(
      const <String>[
        '--backend=webdav',
        '--ops=5000',
        '--latency=150',
        '--report=/tmp/webdav_sync_bench.json',
      ],
    );

    expect(config.backend, SyncBenchBackend.webdav);
    expect(config.ops, 5000);
    expect(config.latencyMs, 150);
    expect(config.reportPath, '/tmp/webdav_sync_bench.json');
    expect(config.pushCommand, isNull);
    expect(config.pullCommand, isNull);
  });

  test('parseSyncBenchArgs rejects unsupported ops tier', () {
    expect(
      () => parseSyncBenchArgs(
        const <String>['--backend=webdav', '--ops=2000'],
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('supported ops tiers'),
        ),
      ),
    );
  });

  test('runSyncBenchReport runs commands and writes measured durations',
      () async {
    final config = parseSyncBenchArgs(
      const <String>[
        '--backend=managed-vault',
        '--ops=1000',
        '--push-cmd=echo push',
        '--pull-cmd=echo pull',
      ],
    );

    final calls = <String>[];
    final report = await runSyncBenchReport(
      config,
      commandRunner: (command) async {
        calls.add(command);
        return const BenchCommandResult(
          exitCode: 0,
          elapsed: Duration(milliseconds: 12),
          stdout: 'ok',
          stderr: '',
        );
      },
      now: () => DateTime.parse('2026-02-27T00:00:00Z'),
    );

    expect(calls, <String>['echo push', 'echo pull']);
    expect(report.backend, 'managed-vault');
    expect(report.ops, 1000);
    expect(report.pushMs, 12);
    expect(report.pullMs, 12);
    expect(report.retryCount, 0);
    expect(report.appliedCount, 0);
    expect(report.runId, '2026-02-27T00:00:00.000Z');
  });

  test('runSyncBenchReport uses default backend driver commands', () async {
    final config = parseSyncBenchArgs(
      const <String>[
        '--backend=webdav',
        '--ops=1000',
      ],
    );

    final calls = <String>[];
    await runSyncBenchReport(
      config,
      commandRunner: (command) async {
        calls.add(command);
        return const BenchCommandResult(
          exitCode: 0,
          elapsed: Duration(milliseconds: 1),
          stdout: 'ok',
          stderr: '',
        );
      },
    );

    expect(calls.length, 2);
    expect(calls[0], contains('SYNC_BENCH_OPS=1000'));
    expect(
        calls[0], contains('--test sync_push_retries_with_lower_parallelism'));
    expect(calls[1], contains('SYNC_BENCH_OPS=1000'));
    expect(calls[1], contains('--test sync_end_to_end_inmemory_remote'));
  });

  test('runSyncBenchReport forwards ops tier to default driver commands',
      () async {
    final config = parseSyncBenchArgs(
      const <String>[
        '--backend=webdav',
        '--ops=5000',
      ],
    );

    final calls = <String>[];
    final report = await runSyncBenchReport(
      config,
      commandRunner: (command) async {
        calls.add(command);
        return const BenchCommandResult(
          exitCode: 0,
          elapsed: Duration(milliseconds: 2),
          stdout: 'ok',
          stderr: '',
        );
      },
    );

    expect(calls.length, 2);
    expect(calls[0], contains('SYNC_BENCH_OPS=5000'));
    expect(calls[1], contains('SYNC_BENCH_OPS=5000'));
    expect(report.pushMs, 2);
    expect(report.pullMs, 2);
    expect(report.notes, contains('dataset-ops:5000'));
  });

  test('runSyncBenchReport dry-run skips backend driver commands', () async {
    final config = parseSyncBenchArgs(
      const <String>[
        '--backend=localdir',
        '--ops=1000',
        '--dry-run',
      ],
    );

    final calls = <String>[];
    final report = await runSyncBenchReport(
      config,
      commandRunner: (command) async {
        calls.add(command);
        return const BenchCommandResult(
          exitCode: 0,
          elapsed: Duration(milliseconds: 1),
          stdout: 'ok',
          stderr: '',
        );
      },
    );

    expect(calls, isEmpty);
    expect(report.pushMs, 0);
    expect(report.pullMs, 0);
    expect(report.notes, contains('dry-run'));
  });
}
