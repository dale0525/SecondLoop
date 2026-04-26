part of 'cloud_sync_switch_prompt_gate.dart';

String _managedVaultRecoveredMessageForGate(
  Translations t,
  MaterialLocalizations materialLocalizations,
  SyncWriteGateState gate,
) {
  if (gate.kind == SyncWriteGateKind.localRepairRequired) {
    return t.sync.cloudManagedVault.localSyncDataRepairRequired;
  }
  if (gate.kind == SyncWriteGateKind.paymentRequired) {
    return t.sync.cloudManagedVault.paymentRequired;
  }
  if (gate.kind == SyncWriteGateKind.graceReadOnly) {
    final untilMs = gate.graceUntilMs;
    if (untilMs != null && DateTime.now().millisecondsSinceEpoch < untilMs) {
      final dt = DateTime.fromMillisecondsSinceEpoch(untilMs).toLocal();
      final until = materialLocalizations.formatShortDate(dt);
      return t.sync.cloudManagedVault.graceReadonlyUntil(until: until);
    }
    return t.sync.cloudManagedVault.serverUnavailable;
  }
  if (gate.kind == SyncWriteGateKind.storageQuotaExceeded) {
    return t.sync.cloudManagedVault.storageQuotaExceeded;
  }
  return t.sync.cloudManagedVault.serverUnavailable;
}

String _managedVaultUserFacingErrorMessage(
  Translations t,
  MaterialLocalizations materialLocalizations,
  Object error,
) {
  final status = extractSyncHttpStatusCode(error);
  final code = extractSyncErrorCode(error);
  if (status == 400 && code == 'invalid_batch') {
    return t.sync.cloudManagedVault.localSyncDataRepairRequired;
  }
  final recoveryBlockedReason = extractManagedVaultRecoveryBlockedReason(error);
  if (recoveryBlockedReason == 'local_unpushed_changes') {
    return t.sync.cloudManagedVault.localChangesUploadRequired;
  }
  if (recoveryBlockedReason == 'local_media_backfill_pending') {
    return t.sync.cloudManagedVault.localMediaBackfillRequired;
  }
  final gate = inspectManagedVaultPushFailure(error).writeGateState;
  if (gate != null) {
    return _managedVaultRecoveredMessageForGate(
      t,
      materialLocalizations,
      gate,
    );
  }
  return '$error';
}

String? _managedVaultSyncFailureMessage(
  Translations t,
  MaterialLocalizations materialLocalizations,
  Object error,
) {
  return _managedVaultUserFacingErrorMessage(
    t,
    materialLocalizations,
    error,
  );
}
