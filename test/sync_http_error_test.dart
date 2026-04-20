import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_http_error.dart';

void main() {
  test('managed-vault push failures allow pull for recoverable v2 state errors',
      () {
    expect(
      managedVaultPushFailureAllowsPull(
        Exception(
          'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
        ),
      ),
      isTrue,
    );
    expect(
      managedVaultPushFailureAllowsPull(
        Exception(
          'managed-vault v2 push failed: HTTP 409 {"error":"generation_required","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
        ),
      ),
      isTrue,
    );
  });

  test('managed-vault push failures still block pull for unrelated errors', () {
    expect(
      managedVaultPushFailureAllowsPull(
        Exception(
          'managed-vault push failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
      isFalse,
    );
    expect(
      managedVaultPushFailureAllowsPull(
        Exception(
          'managed-vault push failed: HTTP 403 {"error":"storage_quota_exceeded","used_bytes":10,"limit_bytes":9}',
        ),
      ),
      isFalse,
    );
    expect(
      managedVaultPushFailureAllowsPull(
        Exception(
            'managed-vault push failed: HTTP 503 {"error":"unavailable"}'),
      ),
      isFalse,
    );
    expect(managedVaultPushFailureAllowsPull(Exception('socket exception')),
        isFalse);
  });

  test('managed-vault push failure recovery distinguishes pull-only and retry',
      () {
    expect(
      managedVaultPushFailureRecoveryAction(
        Exception(
          'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
        ),
      ),
      ManagedVaultPushFailureRecoveryAction.pullThenRetryPush,
    );
    expect(
      managedVaultPushFailureRecoveryAction(
        Exception(
          'managed-vault v2 push failed: HTTP 409 {"error":"generation_required","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
        ),
      ),
      ManagedVaultPushFailureRecoveryAction.pullThenRetryPush,
    );
    expect(
      managedVaultPushFailureRecoveryAction(
        Exception(
          'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
        ),
      ),
      ManagedVaultPushFailureRecoveryAction.pullOnly,
    );
    expect(
      managedVaultPushFailureRecoveryAction(
        Exception(
          'managed-vault push failed: HTTP 403 {"error":"storage_quota_exceeded","used_bytes":10,"limit_bytes":9}',
        ),
      ),
      ManagedVaultPushFailureRecoveryAction.none,
    );
    expect(
      managedVaultPushFailureRecoveryAction(
        Exception(
          'managed-vault push failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
      ManagedVaultPushFailureRecoveryAction.none,
    );
  });

  test('managed-vault invalid batch errors are parsed explicitly', () {
    final error = Exception(
      'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"malformed_op"}',
    );

    expect(extractSyncHttpStatusCode(error), 400);
    expect(extractSyncErrorCode(error), 'invalid_batch');
    expect(managedVaultPushFailureAllowsPull(error), isFalse);
    expect(
      managedVaultPushFailureRecoveryAction(error),
      ManagedVaultPushFailureRecoveryAction.none,
    );
  });

  test('grace_readonly without grace_until_ms still maps to a blocking gate',
      () {
    final gate = managedVaultWriteGateStateForError(
      Exception(
        'managed-vault push failed: HTTP 403 {"error":"grace_readonly"}',
      ),
    );

    expect(gate, isNotNull);
    expect(gate!.kind, SyncWriteGateKind.graceReadOnly);
    expect(gate.graceUntilMs, isNull);
  });

  test('managed-vault bootstrap rollback only triggers for fatal setup errors',
      () {
    expect(
      shouldRollbackManagedVaultBootstrapOnError(
        Exception(
          'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"malformed_op"}',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRollbackManagedVaultBootstrapOnError(
        Exception(
          'managed-vault push failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRollbackManagedVaultBootstrapOnError(
        Exception(
          'managed-vault push failed: HTTP 403 {"error":"storage_quota_exceeded","used_bytes":10,"limit_bytes":9}',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRollbackManagedVaultBootstrapOnError(
        Exception(
          'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
        ),
      ),
      isFalse,
    );
    expect(
      shouldRollbackManagedVaultBootstrapOnError(
        Exception(
            'managed-vault push failed: HTTP 503 {"error":"unavailable"}'),
      ),
      isFalse,
    );
  });

  test(
      'managed-vault local recovery blockers persist a background repair block',
      () {
    expect(
      shouldPersistManagedVaultBackgroundRepairBlock(
        StateError(
          'managed-vault v2 recovery blocked: local_unpushed_changes',
        ),
      ),
      isTrue,
    );
    expect(
      shouldPersistManagedVaultBackgroundRepairBlock(
        StateError(
          'managed-vault v2 recovery blocked: local_media_backfill_pending',
        ),
      ),
      isTrue,
    );
    expect(
      shouldPersistManagedVaultBackgroundRepairBlock(
        Exception(
          'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"malformed_op"}',
        ),
      ),
      isTrue,
    );
  });
}
