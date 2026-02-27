import 'dart:convert';
import 'dart:io';

import 'sync_bench_lib.dart';

Future<void> main(List<String> args) async {
  late final SyncBenchConfig config;
  try {
    config = parseSyncBenchArgs(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(syncBenchUsage.trim());
    exit(2);
  }

  if (config.showHelp) {
    stdout.writeln(syncBenchUsage.trim());
    return;
  }

  try {
    final report = await runSyncBenchReport(config);
    final jsonText =
        const JsonEncoder.withIndent('  ').convert(report.toJson());

    final reportPath = config.reportPath?.trim();
    if (reportPath != null && reportPath.isNotEmpty) {
      final outFile = File(reportPath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsStringSync('$jsonText\n');
      stdout.writeln('sync-bench: wrote report to $reportPath');
      return;
    }

    stdout.writeln(jsonText);
  } on ProcessException catch (e) {
    stderr.writeln(
      'sync-bench: command failed (exit=${e.errorCode}): ${e.message}',
    );
    final exitCode = e.errorCode > 0 ? e.errorCode : 1;
    exit(exitCode);
  } catch (e) {
    stderr.writeln('sync-bench: failed: $e');
    exit(1);
  }
}
