part of 'sync_settings_page.dart';

final class _ManagedVaultManualPushResult {
  const _ManagedVaultManualPushResult({
    required this.pushed,
    required this.recoveredOnly,
    required this.recoveredMessage,
  });

  final int pushed;
  final bool recoveredOnly;
  final String? recoveredMessage;
}

extension _SyncSettingsPageManagedVaultSync on _SyncSettingsPageState {
  String _managedVaultRecoveredMessageForGate(SyncWriteGateState gate) {
    if (gate.kind == SyncWriteGateKind.paymentRequired) {
      return context.t.sync.cloudManagedVault.paymentRequired;
    }
    if (gate.kind == SyncWriteGateKind.graceReadOnly) {
      final untilMs = gate.graceUntilMs;
      if (untilMs != null && DateTime.now().millisecondsSinceEpoch < untilMs) {
        final dt = DateTime.fromMillisecondsSinceEpoch(untilMs).toLocal();
        final until = MaterialLocalizations.of(context).formatShortDate(dt);
        return context.t.sync.cloudManagedVault.graceReadonlyUntil(
          until: until,
        );
      }
      return context.t.sync.cloudManagedVault.serverUnavailable;
    }
    if (gate.kind == SyncWriteGateKind.storageQuotaExceeded) {
      final used = gate.quotaUsedBytes;
      final limit = gate.quotaLimitBytes;
      if (used != null && limit != null && limit > 0) {
        return context.t.sync.cloudManagedVault.storageQuotaExceededWithUsage(
          used: _formatBytes(used),
          limit: _formatBytes(limit),
        );
      }
      return context.t.sync.cloudManagedVault.storageQuotaExceeded;
    }
    return context.t.sync.cloudManagedVault.serverUnavailable;
  }

  String managedVaultUserFacingErrorMessage(Object error) {
    final status = extractSyncHttpStatusCode(error);
    final code = extractSyncErrorCode(error);
    if (status == 400 && code == 'invalid_batch') {
      return context.t.sync.cloudManagedVault.localSyncDataRepairRequired;
    }
    if (status == 402) {
      return context.t.sync.cloudManagedVault.paymentRequired;
    }
    if (status == 403 && code == 'storage_quota_exceeded') {
      return context.t.sync.cloudManagedVault.storageQuotaExceeded;
    }
    return '$error';
  }

  Future<_ManagedVaultManualPushResult> _runManagedVaultManualPushWithProgress({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required SyncEngine? engine,
    required ValueNotifier<String> stage,
    required ValueNotifier<double?> progress,
    required ValueNotifier<bool> hasTotal,
  }) async {
    final t = context.t;
    final cloudAuth = CloudAuthScope.of(context).controller;
    final idToken = await readCloudAuthIdToken(
      cloudAuth,
      mode: CloudAuthAccessMode.interactive,
    );
    if (idToken == null || idToken.trim().isEmpty) {
      throw StateError('missing_id_token');
    }
    final vaultId = cloudAuth.uid ?? '';
    final baseUrl = await _store.resolveManagedVaultBaseUrl();
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      throw StateError('missing_managed_vault_base_url');
    }

    var pushed = 0;
    var recoveredOnly = false;
    var retryPushAfterPull = false;
    String? recoveredMessage;
    try {
      pushed = await _consumeRustProgressStream(
        backend.syncManagedVaultPushProgress(
          sessionKey,
          syncKey,
          baseUrl: baseUrl,
          vaultId: vaultId,
          idToken: idToken,
        ),
        onProgress: _makeSmoothStageProgressReporter(
          progress,
          onHasTotal: () => hasTotal.value = true,
        ).onProgress,
      );
      reopenManagedVaultWriteGateOnSuccess(engine);
    } catch (error) {
      final recoveryAction = managedVaultPushFailureRecoveryAction(error);
      final nextWriteGate = managedVaultWriteGateStateForError(error);
      if (nextWriteGate != null) {
        engine?.writeGate.value = nextWriteGate;
        recoveredMessage = _managedVaultRecoveredMessageForGate(nextWriteGate);
      }
      if (recoveryAction == ManagedVaultPushFailureRecoveryAction.none) {
        rethrow;
      }
      retryPushAfterPull = recoveryAction ==
          ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;
      recoveredOnly = !retryPushAfterPull;
    }

    stage.value = t.sync.progressDialog.pulling;
    progress.value = 0.0;
    hasTotal.value = false;
    final pullProgressReporter = _makeSmoothStageProgressReporter(
      progress,
      onHasTotal: () => hasTotal.value = true,
    );
    await _consumeRustProgressStream(
      backend.syncManagedVaultPullProgress(
        sessionKey,
        syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      ),
      onProgress: pullProgressReporter.onProgress,
    );
    if (retryPushAfterPull) {
      stage.value = t.sync.progressDialog.pushing;
      progress.value = 0.0;
      hasTotal.value = false;
      final retryProgressReporter = _makeSmoothStageProgressReporter(
        progress,
        onHasTotal: () => hasTotal.value = true,
      );
      pushed = await _consumeRustProgressStream(
        backend.syncManagedVaultPushProgress(
          sessionKey,
          syncKey,
          baseUrl: baseUrl,
          vaultId: vaultId,
          idToken: idToken,
        ),
        onProgress: retryProgressReporter.onProgress,
      );
      retryProgressReporter.complete();
      reopenManagedVaultWriteGateOnSuccess(engine);
      recoveredOnly = false;
    }
    stage.value = t.sync.progressDialog.finalizing;
    pullProgressReporter.complete();
    return _ManagedVaultManualPushResult(
      pushed: pushed,
      recoveredOnly: recoveredOnly,
      recoveredMessage: recoveredMessage,
    );
  }
}
