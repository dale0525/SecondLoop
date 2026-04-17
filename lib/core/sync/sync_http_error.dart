import 'sync_engine.dart';

int? extractSyncHttpStatusCode(Object error) {
  final message = error.toString();
  final statusText =
      RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message)?.group(1);
  if (statusText == null) return null;
  return int.tryParse(statusText);
}

String? extractSyncErrorCode(Object error) {
  final message = error.toString();
  return RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message)?.group(1);
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

bool managedVaultWriteGateShouldClearAfterPull(SyncWriteGateState state) {
  return state.kind == SyncWriteGateKind.paymentRequired ||
      state.kind == SyncWriteGateKind.storageQuotaExceeded;
}

bool managedVaultPushFailureAllowsPull(Object error) {
  final statusCode = extractSyncHttpStatusCode(error);
  final errorCode = extractSyncErrorCode(error);
  return statusCode == 403 &&
      (errorCode == 'grace_readonly' || errorCode == 'storage_quota_exceeded');
}
