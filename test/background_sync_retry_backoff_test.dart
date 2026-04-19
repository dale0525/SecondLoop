import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/background_sync.dart';

void main() {
  test('retryBackoffDelayForFailureCount grows exponentially and caps', () {
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(1),
      const Duration(minutes: 1),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(2),
      const Duration(minutes: 2),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(3),
      const Duration(minutes: 4),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(6),
      const Duration(minutes: 32),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(7),
      const Duration(minutes: 60),
    );
    expect(
      BackgroundSync.retryBackoffDelayForFailureCount(20),
      const Duration(minutes: 60),
    );
  });

  test('retryable error classification follows sync policy', () {
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 429),
      isTrue,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 503),
      isTrue,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 401),
      isTrue,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(statusCode: 402),
      isFalse,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        message: 'SocketException: Failed host lookup',
      ),
      isTrue,
    );
  });

  test('userReadableSyncErrorMessage maps cloud failures', () {
    expect(
      BackgroundSync.userReadableSyncErrorMessage(statusCode: 402),
      contains('subscription'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      contains('read-only'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      contains('quota'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(statusCode: 429),
      contains('Retrying later'),
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      contains('Local sync data'),
    );
  });

  test('managed-vault media uploads only run after a successful final push',
      () {
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: true,
        statusCode: null,
        errorCode: null,
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        statusCode: 402,
        errorCode: 'payment_required',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        statusCode: 503,
        errorCode: null,
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldRunManagedVaultMediaUploads(
        pushSucceeded: false,
        statusCode: null,
        errorCode: null,
      ),
      isFalse,
    );
  });

  test(
      'managed-vault background pull-after-push policy matches interactive flows',
      () {
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 409,
        errorCode: 'generation_mismatch',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 409,
        errorCode: 'generation_required',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 402,
        errorCode: 'payment_required',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldContinueManagedVaultPullAfterPushFailure(
        statusCode: 503,
        errorCode: null,
      ),
      isFalse,
    );
  });

  test('invalid managed-vault batches are non-retryable and user visible', () {
    expect(
      BackgroundSync.isRetryableBackgroundSyncFailure(
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      isFalse,
    );
    expect(
      BackgroundSync.userReadableSyncErrorMessage(
        statusCode: 400,
        errorCode: 'invalid_batch',
      ),
      contains('Local sync data'),
    );
  });
}
