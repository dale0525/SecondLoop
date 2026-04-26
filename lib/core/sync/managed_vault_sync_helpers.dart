import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'stage_progress_smoother.dart';
import 'sync_http_error.dart';

const kCloudSyncProgressKey = ValueKey('cloud_sync_switch_progress');
const kCloudSyncPercentKey = ValueKey('cloud_sync_switch_progress_percent');
const kNoManagedVaultSyncFailureMessage = Object();

SyncStageProgressReporter makeManagedVaultStageProgressReporter(
  ValueNotifier<double> progress,
) {
  return SyncStageProgressReporter((value) => progress.value = value);
}

Future<int> consumeRustProgressStream(
  Stream<String> stream, {
  required void Function(int done, int total) onProgress,
}) async {
  var count = 0;
  await for (final msg in stream) {
    Map<String, dynamic>? ev;
    try {
      final decoded = jsonDecode(msg);
      ev = decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      ev = null;
    }
    if (ev == null) continue;

    final type = ev['type'];
    if (type == 'progress') {
      final done = (ev['done'] as num?)?.toInt();
      final total = (ev['total'] as num?)?.toInt();
      if (done != null && total != null) {
        onProgress(done, total);
      }
    } else if (type == 'result') {
      final v = (ev['count'] as num?)?.toInt();
      if (v != null) count = v;
    }
  }
  return count;
}

bool shouldRollbackManagedVaultBootstrapAfterFailure(Object error) {
  if (shouldRollbackManagedVaultBootstrapOnError(error)) {
    return true;
  }
  if (extractManagedVaultRecoveryBlockedReason(error) != null) {
    return true;
  }
  return inspectManagedVaultPushFailure(error).writeGateState != null;
}
