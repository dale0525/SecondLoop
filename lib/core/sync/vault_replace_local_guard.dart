import 'package:flutter/foundation.dart';

import '../backend/app_backend.dart';

Future<T> runDestructiveReplaceLocalWithRollback<T>({
  required AppBackend backend,
  required Uint8List sessionKey,
  required Future<T> Function() run,
}) async {
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
    rethrow;
  }

  try {
    await backend.deleteVaultRollbackSnapshot(snapshotPath: snapshotPath);
  } catch (error, stackTrace) {
    debugPrint(
      'sync replace-local: failed to remove rollback snapshot after success: $error',
    );
    Error.throwWithStackTrace(
      StateError('replace-local snapshot cleanup failed: $error'),
      stackTrace,
    );
  }

  return result;
}
