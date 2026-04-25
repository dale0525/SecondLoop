import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/sync/vault_replace_local_guard.dart';

import 'test_backend.dart';

void main() {
  test('replace-local succeeds when rollback snapshot cleanup fails', () async {
    final backend = _SnapshotCleanupFailureBackend();

    await runDestructiveReplaceLocalWithRollback<void>(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      run: () async {
        backend.calls.add('run');
      },
    );

    expect(
      backend.calls,
      <String>['createSnapshot', 'resetLocal', 'run', 'deleteSnapshot'],
    );
  });
}

final class _SnapshotCleanupFailureBackend extends TestAppBackend {
  final List<String> calls = <String>[];

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'snapshot-1';
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    calls.add('restoreSnapshot:$snapshotPath');
  }

  @override
  Future<void> deleteVaultRollbackSnapshot({
    required String snapshotPath,
  }) async {
    calls.add('deleteSnapshot');
    throw StateError('cleanup denied');
  }
}
