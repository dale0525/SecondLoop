import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/app_backend.dart';

const _kPendingVaultRollbackSnapshotCleanupPrefsKey =
    'vault_rollback_snapshot_cleanup_pending_v1';

Future<T> runDestructiveReplaceLocalWithRollback<T>({
  required AppBackend backend,
  required Uint8List sessionKey,
  required Future<T> Function() run,
}) async {
  await _retryPendingVaultRollbackSnapshotCleanup(backend);

  String? snapshotPath;
  try {
    snapshotPath = await backend.createVaultRollbackSnapshot(sessionKey);
  } on UnimplementedError catch (error) {
    throw StateError('replace-local rollback snapshot unavailable: $error');
  }
  if (snapshotPath == null || snapshotPath.trim().isEmpty) {
    throw StateError('replace-local rollback snapshot unavailable');
  }

  late final T result;
  try {
    await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
    result = await run();
  } catch (error, stackTrace) {
    try {
      await backend.restoreVaultRollbackSnapshot(
        sessionKey,
        snapshotPath: snapshotPath,
      );
    } catch (rollbackError) {
      Error.throwWithStackTrace(
        StateError(
          'replace-local failed: $error; rollback failed: $rollbackError',
        ),
        stackTrace,
      );
    }
    await _cleanupRestoredVaultRollbackSnapshot(backend, snapshotPath);
    rethrow;
  }

  try {
    await backend.deleteVaultRollbackSnapshot(snapshotPath: snapshotPath);
  } catch (error) {
    await _recordPendingVaultRollbackSnapshotCleanup(snapshotPath);
    debugPrint(
      'sync replace-local: failed to remove rollback snapshot after success: $error',
    );
  }

  return result;
}

Future<void> _cleanupRestoredVaultRollbackSnapshot(
  AppBackend backend,
  String snapshotPath,
) async {
  try {
    await backend.deleteVaultRollbackSnapshot(snapshotPath: snapshotPath);
  } catch (error) {
    if (_rollbackSnapshotAlreadyRemoved(error)) {
      return;
    }
    try {
      await _recordPendingVaultRollbackSnapshotCleanup(snapshotPath);
    } catch (recordError) {
      debugPrint(
        'sync replace-local: failed to record pending rollback snapshot cleanup: $recordError',
      );
    }
    debugPrint(
      'sync replace-local: failed to remove rollback snapshot after restore: $error',
    );
  }
}

bool _rollbackSnapshotAlreadyRemoved(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('not active') ||
      message.contains('not found') ||
      message.contains('no such file');
}

Future<void> _retryPendingVaultRollbackSnapshotCleanup(
    AppBackend backend) async {
  final prefs = await SharedPreferences.getInstance();
  final pending = _dedupeSnapshotPaths(
    prefs.getStringList(_kPendingVaultRollbackSnapshotCleanupPrefsKey) ??
        const <String>[],
  );
  if (pending.isEmpty) return;

  final remaining = <String>[];
  for (final snapshotPath in pending) {
    try {
      await backend.deleteVaultRollbackSnapshot(snapshotPath: snapshotPath);
    } catch (error) {
      if (_rollbackSnapshotAlreadyRemoved(error)) {
        continue;
      }
      remaining.add(snapshotPath);
      debugPrint(
        'sync replace-local: failed to remove pending rollback snapshot '
        '$snapshotPath: $error',
      );
    }
  }

  await prefs.setStringList(
    _kPendingVaultRollbackSnapshotCleanupPrefsKey,
    remaining,
  );
}

Future<void> _recordPendingVaultRollbackSnapshotCleanup(
  String snapshotPath,
) async {
  final prefs = await SharedPreferences.getInstance();
  final pending = _dedupeSnapshotPaths(
    prefs.getStringList(_kPendingVaultRollbackSnapshotCleanupPrefsKey) ??
        const <String>[],
  );
  if (!pending.contains(snapshotPath)) {
    pending.add(snapshotPath);
  }
  await prefs.setStringList(
    _kPendingVaultRollbackSnapshotCleanupPrefsKey,
    pending,
  );
}

List<String> _dedupeSnapshotPaths(Iterable<String> paths) {
  final seen = <String>{};
  final result = <String>[];
  for (final path in paths) {
    if (path.trim().isEmpty) continue;
    if (seen.add(path)) {
      result.add(path);
    }
  }
  return result;
}
