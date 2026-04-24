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
    debugPrint(
      'sync replace-local: rollback snapshot unavailable; continuing without snapshot: $error',
    );
  }

  try {
    await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
    final result = await run();
    final path = snapshotPath;
    if (path != null) {
      unawaited(backend
          .deleteVaultRollbackSnapshot(snapshotPath: path)
          .catchError((error) {
        debugPrint(
          'sync replace-local: failed to remove rollback snapshot after success: $error',
        );
      }));
    }
    return result;
  } catch (error, stackTrace) {
    final path = snapshotPath;
    if (path != null) {
      try {
        await backend.restoreVaultRollbackSnapshot(
          sessionKey,
          snapshotPath: path,
        );
      } catch (rollbackError) {
        Error.throwWithStackTrace(
          StateError(
            'replace-local failed: $error; rollback failed: $rollbackError',
          ),
          stackTrace,
        );
      }
    }
    rethrow;
  }
}
