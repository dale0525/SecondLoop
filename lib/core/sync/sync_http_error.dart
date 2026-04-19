export 'managed_vault_sync_error_policy.dart';

import 'managed_vault_sync_error_policy.dart';
import 'sync_engine.dart';

final class ManagedVaultPushFailureDetails {
  const ManagedVaultPushFailureDetails({
    required this.recoveryAction,
    required this.writeGateState,
  });

  final ManagedVaultPushFailureRecoveryAction recoveryAction;
  final SyncWriteGateState? writeGateState;
}

int? extractSyncHttpStatusCode(Object error) {
  return extractManagedVaultSyncHttpStatusCode(error);
}

String? extractSyncErrorCode(Object error) {
  return extractManagedVaultSyncErrorCode(error);
}

int? extractSyncErrorIntField(Object error, String fieldName) {
  final message = error.toString();
  final valueText =
      RegExp('"$fieldName"\\s*:\\s*(\\d+)').firstMatch(message)?.group(1);
  if (valueText == null) return null;
  return int.tryParse(valueText);
}

String? extractManagedVaultRecoveryBlockedReason(Object error) {
  return RegExp(
    r'managed-vault v2 recovery blocked:\s*([a-z_]+)',
  ).firstMatch(error.toString())?.group(1);
}

SyncWriteGateState? managedVaultWriteGateStateForError(Object error) {
  final statusCode = extractSyncHttpStatusCode(error);
  final errorCode = extractSyncErrorCode(error);
  if (statusCode == 400 && errorCode == 'invalid_batch') {
    return const SyncWriteGateState.localRepairRequired();
  }
  if (statusCode == 403 && errorCode == 'grace_readonly') {
    final graceUntilMs = extractSyncErrorIntField(error, 'grace_until_ms');
    return SyncWriteGateState.graceReadOnly(graceUntilMs);
  }
  if (statusCode == 403 && errorCode == 'storage_quota_exceeded') {
    return SyncWriteGateState.storageQuotaExceeded(
      usedBytes: extractSyncErrorIntField(error, 'used_bytes'),
      limitBytes: extractSyncErrorIntField(error, 'limit_bytes'),
    );
  }
  if (statusCode == 402) {
    return const SyncWriteGateState.paymentRequired();
  }
  return null;
}

ManagedVaultPushFailureDetails inspectManagedVaultPushFailure(Object error) {
  return ManagedVaultPushFailureDetails(
    recoveryAction: managedVaultPushFailureRecoveryAction(error),
    writeGateState: managedVaultWriteGateStateForError(error),
  );
}

void reopenManagedVaultWriteGateOnSuccess(SyncEngine? engine) {
  engine?.writeGate.value = const SyncWriteGateState.open();
}

bool shouldRollbackManagedVaultBootstrapOnError(Object error) {
  final statusCode = extractSyncHttpStatusCode(error);
  final errorCode = extractSyncErrorCode(error);
  final recoveryBlockedReason = extractManagedVaultRecoveryBlockedReason(error);

  if (statusCode == 400 && errorCode == 'invalid_batch') {
    return true;
  }
  if (statusCode == 402) {
    return true;
  }
  if (statusCode == 403 && errorCode == 'storage_quota_exceeded') {
    return true;
  }
  if (recoveryBlockedReason == 'local_unpushed_changes' ||
      recoveryBlockedReason == 'local_media_backfill_pending') {
    return true;
  }
  return false;
}
