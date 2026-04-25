import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:secondloop/core/sync/vault_replace_local_guard.dart';

import 'test_backend.dart';

void main() {
  test('replace-local succeeds when rollback snapshot cleanup fails', () async {
    SharedPreferences.setMockInitialValues({});
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
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('vault_rollback_snapshot_cleanup_pending_v1'),
      <String>['snapshot-1'],
    );
  });

  test(
      'replace-local succeeds when rollback snapshot cleanup failure cannot be recorded',
      () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance =
        _FailingSnapshotCleanupPrefsStore();
    addTearDown(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
    });
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

  test('replace-local retries pending rollback snapshot cleanup', () async {
    SharedPreferences.setMockInitialValues({
      'vault_rollback_snapshot_cleanup_pending_v1': <String>[
        'pending-snapshot',
      ],
    });
    final backend = _SnapshotCleanupRetryBackend();

    await runDestructiveReplaceLocalWithRollback<void>(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      run: () async {
        backend.calls.add('run');
      },
    );

    expect(
      backend.calls,
      <String>[
        'deleteSnapshot:pending-snapshot',
        'createSnapshot',
        'resetLocal',
        'run',
        'deleteSnapshot:new-snapshot',
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('vault_rollback_snapshot_cleanup_pending_v1'),
      isEmpty,
    );
  });

  test('replace-local drops pending cleanup for already removed snapshots',
      () async {
    SharedPreferences.setMockInitialValues({
      'vault_rollback_snapshot_cleanup_pending_v1': <String>[
        'missing-snapshot',
      ],
    });
    final backend = _AlreadyRemovedPendingCleanupBackend();

    await runDestructiveReplaceLocalWithRollback<void>(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      run: () async {
        backend.calls.add('run');
      },
    );

    expect(
      backend.calls,
      <String>[
        'deleteSnapshot:missing-snapshot',
        'createSnapshot',
        'resetLocal',
        'run',
        'deleteSnapshot:new-snapshot',
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('vault_rollback_snapshot_cleanup_pending_v1'),
      isEmpty,
    );
  });

  test(
      'replace-local attempts rollback snapshot cleanup after restored failure',
      () async {
    SharedPreferences.setMockInitialValues({});
    final backend = _RollbackSuccessCleanupBackend();

    await expectLater(
      runDestructiveReplaceLocalWithRollback<void>(
        backend: backend,
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        run: () async {
          backend.calls.add('run');
          throw StateError('pull failed');
        },
      ),
      throwsStateError,
    );

    expect(
      backend.calls,
      <String>[
        'createSnapshot',
        'resetLocal',
        'run',
        'restoreSnapshot:snapshot-restore',
        'deleteSnapshot:snapshot-restore',
      ],
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

final class _FailingSnapshotCleanupPrefsStore
    extends InMemorySharedPreferencesStore {
  _FailingSnapshotCleanupPrefsStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.contains('vault_rollback_snapshot_cleanup_pending_v1')) {
      throw Exception('injected prefs write failure for $key');
    }
    return super.setValue(valueType, key, value);
  }
}

final class _AlreadyRemovedPendingCleanupBackend extends TestAppBackend {
  final List<String> calls = <String>[];

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'new-snapshot';
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<void> deleteVaultRollbackSnapshot({
    required String snapshotPath,
  }) async {
    calls.add('deleteSnapshot:$snapshotPath');
    if (snapshotPath == 'missing-snapshot') {
      throw StateError('rollback snapshot is not active');
    }
  }
}

final class _SnapshotCleanupRetryBackend extends TestAppBackend {
  final List<String> calls = <String>[];

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'new-snapshot';
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<void> deleteVaultRollbackSnapshot({
    required String snapshotPath,
  }) async {
    calls.add('deleteSnapshot:$snapshotPath');
  }
}

final class _RollbackSuccessCleanupBackend extends TestAppBackend {
  final List<String> calls = <String>[];

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'snapshot-restore';
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
    calls.add('deleteSnapshot:$snapshotPath');
  }
}
