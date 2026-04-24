import 'dart:async';
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

  try {
    await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
    final result = await run();
    final path = snapshotPath;
    final deleteSnapshot = Future<void>.sync(
      () => backend.deleteVaultRollbackSnapshot(snapshotPath: path),
    ).catchError((error) {
      debugPrint(
        'sync replace-local: failed to remove rollback snapshot after success: $error',
      );
    });
    unawaited(deleteSnapshot);
    return result;
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
}
