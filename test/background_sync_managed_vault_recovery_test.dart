import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/background_sync.dart';
import 'package:secondloop/core/sync/managed_vault_sync_error_policy.dart';

void main() {
  test('background managed-vault recovery retry requires a final pull', () {
    expect(
      BackgroundSync.shouldRunManagedVaultFinalPullAfterRecoveryRetry(
        recoveryAction: ManagedVaultPushFailureRecoveryAction.pullThenRetryPush,
        initialPullSucceeded: true,
        retryPushSucceeded: true,
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultFinalPullAfterRecoveryRetry(
        recoveryAction: ManagedVaultPushFailureRecoveryAction.pullThenRetryPush,
        initialPullSucceeded: false,
        retryPushSucceeded: true,
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultFinalPullAfterRecoveryRetry(
        recoveryAction: ManagedVaultPushFailureRecoveryAction.pullOnly,
        initialPullSucceeded: true,
        retryPushSucceeded: true,
      ),
      isFalse,
    );
  });
}
