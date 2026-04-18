import 'package:flutter_test/flutter_test.dart';

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
          'managed-vault push failed: HTTP 402 {"error":"payment_required"}',
        ),
      ),
      ManagedVaultPushFailureRecoveryAction.none,
    );
  });
}
