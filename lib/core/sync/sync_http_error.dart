export 'managed_vault_sync_error_policy.dart';

import 'managed_vault_sync_error_policy.dart';
import 'sync_engine.dart';

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

SyncWriteGateState? managedVaultWriteGateStateForError(Object error) {
  final statusCode = extractSyncHttpStatusCode(error);
  final errorCode = extractSyncErrorCode(error);
  if (statusCode == 403 && errorCode == 'grace_readonly') {
    final graceUntilMs = extractSyncErrorIntField(error, 'grace_until_ms');
    if (graceUntilMs != null) {
      return SyncWriteGateState.graceReadOnly(graceUntilMs);
    }
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

void reopenManagedVaultWriteGateOnSuccess(SyncEngine? engine) {
  engine?.writeGate.value = const SyncWriteGateState.open();
}

bool shouldRollbackManagedVaultBootstrapOnError(Object error) {
  final statusCode = extractSyncHttpStatusCode(error);
  final errorCode = extractSyncErrorCode(error);

  if (statusCode == 400 && errorCode == 'invalid_batch') {
    return true;
  }
  if (statusCode == 402) {
    return true;
  }
  if (statusCode == 403 && errorCode == 'storage_quota_exceeded') {
    return true;
  }
  return false;
}
