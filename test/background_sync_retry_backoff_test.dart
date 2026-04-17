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
  });

  test('managed-vault media uploads stop after write-blocking push failures',
      () {
    expect(
      BackgroundSync.shouldSkipManagedVaultMediaUploadsAfterPushFailure(
        statusCode: 403,
        errorCode: 'grace_readonly',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldSkipManagedVaultMediaUploadsAfterPushFailure(
        statusCode: 403,
        errorCode: 'storage_quota_exceeded',
      ),
      isTrue,
    );
    expect(
      BackgroundSync.shouldSkipManagedVaultMediaUploadsAfterPushFailure(
        statusCode: 503,
        errorCode: null,
      ),
      isFalse,
    );
    expect(
      BackgroundSync.shouldSkipManagedVaultMediaUploadsAfterPushFailure(
        statusCode: null,
        errorCode: null,
      ),
      isFalse,
    );
  });
}
