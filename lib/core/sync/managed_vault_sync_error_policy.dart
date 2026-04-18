enum ManagedVaultPushFailureRecoveryAction {
  none,
  pullOnly,
  pullThenRetryPush,
}

int? extractManagedVaultSyncHttpStatusCode(Object error) {
  final message = error.toString();
  final statusText =
      RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message)?.group(1);
  if (statusText == null) return null;
  return int.tryParse(statusText);
}

String? extractManagedVaultSyncErrorCode(Object error) {
  final message = error.toString();
  return RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message)?.group(1);
}

ManagedVaultPushFailureRecoveryAction
    managedVaultPushFailureRecoveryActionForStatus({
  int? statusCode,
  String? errorCode,
}) {
  if (statusCode == 403) {
    if (errorCode == 'grace_readonly' ||
        errorCode == 'storage_quota_exceeded') {
      return ManagedVaultPushFailureRecoveryAction.pullOnly;
    }
    return ManagedVaultPushFailureRecoveryAction.none;
  }
  if (statusCode == 409) {
    if (errorCode == 'generation_mismatch' ||
        errorCode == 'generation_required') {
      return ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;
    }
  }
  return ManagedVaultPushFailureRecoveryAction.none;
}

ManagedVaultPushFailureRecoveryAction managedVaultPushFailureRecoveryAction(
  Object error,
) {
  return managedVaultPushFailureRecoveryActionForStatus(
    statusCode: extractManagedVaultSyncHttpStatusCode(error),
    errorCode: extractManagedVaultSyncErrorCode(error),
  );
}

bool managedVaultPushFailureAllowsPullForStatus({
  int? statusCode,
  String? errorCode,
}) {
  return managedVaultPushFailureRecoveryActionForStatus(
        statusCode: statusCode,
        errorCode: errorCode,
      ) !=
      ManagedVaultPushFailureRecoveryAction.none;
}

bool managedVaultPushFailureShouldRetryAfterPullForStatus({
  int? statusCode,
  String? errorCode,
}) {
  return managedVaultPushFailureRecoveryActionForStatus(
        statusCode: statusCode,
        errorCode: errorCode,
      ) ==
      ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;
}

bool managedVaultPushFailureAllowsPull(Object error) {
  return managedVaultPushFailureRecoveryAction(error) !=
      ManagedVaultPushFailureRecoveryAction.none;
}

bool managedVaultPushFailureShouldRetryAfterPull(Object error) {
  return managedVaultPushFailureRecoveryAction(error) ==
      ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;
}
