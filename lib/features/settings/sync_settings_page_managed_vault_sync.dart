part of 'sync_settings_page.dart';

final class _ManagedVaultManualPushResult {
  const _ManagedVaultManualPushResult({
    required this.pushed,
    required this.pulled,
    required this.recoveredOnly,
    required this.recoveredMessage,
    required this.refreshedLocalState,
  });

  final int pushed;
  final int pulled;
  final bool recoveredOnly;
  final String? recoveredMessage;
  final bool refreshedLocalState;
}

final class _ManagedVaultPushStageResult {
  const _ManagedVaultPushStageResult({
    required this.pushed,
    required this.recoveryAction,
    required this.recoveredMessage,
  });

  const _ManagedVaultPushStageResult.success(int pushed)
      : this(
          pushed: pushed,
          recoveryAction: ManagedVaultPushFailureRecoveryAction.none,
          recoveredMessage: null,
        );

  final int pushed;
  final ManagedVaultPushFailureRecoveryAction recoveryAction;
  final String? recoveredMessage;
}

extension _SyncSettingsPageManagedVaultSync on _SyncSettingsPageState {
  Future<void> _clearManagedVaultBackgroundSyncBlockers({
    required String baseUrl,
    required String vaultId,
    required Uint8List syncKey,
  }) async {
    final scopeId = _store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: baseUrl,
      remoteRoot: vaultId,
      syncKey: syncKey,
    );
    await _store.writeBackgroundSyncRepairRequired(
      false,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
    await _store.writeBackgroundSyncBackoffState(
      null,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
  }

  Future<void> _persistManagedVaultBackgroundRepairBlock(
    Object error, {
    required String baseUrl,
    required String vaultId,
    required Uint8List syncKey,
  }) {
    return _store.writeBackgroundSyncRepairRequired(
      shouldPersistManagedVaultBackgroundRepairBlock(error),
      backendType: SyncBackendType.managedVault,
      scopeId: _store.syncStateScopeIdForFields(
        backendType: SyncBackendType.managedVault,
        baseUrl: baseUrl,
        remoteRoot: vaultId,
        syncKey: syncKey,
      ),
    );
  }

  String _managedVaultRecoveredMessageForGate(SyncWriteGateState gate) {
    if (gate.kind == SyncWriteGateKind.localRepairRequired) {
      return context.t.sync.cloudManagedVault.localSyncDataRepairRequired;
    }
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
    final recoveryBlockedReason =
        extractManagedVaultRecoveryBlockedReason(error);
    if (recoveryBlockedReason == 'local_unpushed_changes') {
      return context.t.sync.cloudManagedVault.localChangesUploadRequired;
    }
    if (recoveryBlockedReason == 'local_media_backfill_pending') {
      return context.t.sync.cloudManagedVault.localMediaBackfillRequired;
    }
    final details = inspectManagedVaultPushFailure(error);
    final gate = details.writeGateState;
    if (gate != null) {
      return _managedVaultRecoveredMessageForGate(gate);
    }
    return '$error';
  }

  ManagedVaultPushFailureDetails _applyManagedVaultPushFailure(
    Object error, {
    required SyncEngine? engine,
  }) {
    final details = inspectManagedVaultPushFailure(error);
    final nextWriteGate = details.writeGateState;
    if (nextWriteGate != null) {
      engine?.writeGate.value = nextWriteGate;
    }
    return details;
  }

  Future<_ManagedVaultPushStageResult> _runManagedVaultPushStageWithProgress({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required SyncEngine? engine,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required ValueNotifier<String> stage,
    required ValueNotifier<double?> progress,
    required ValueNotifier<bool> hasTotal,
    required bool allowRecovery,
  }) async {
    final reporter = _makeSmoothStageProgressReporter(
      progress,
      onHasTotal: () => hasTotal.value = true,
    );
    stage.value = context.t.sync.progressDialog.pushing;
    progress.value = 0.0;
    hasTotal.value = false;
    try {
      final pushed = await _consumeRustProgressStream(
        backend.syncManagedVaultPushProgress(
          sessionKey,
          syncKey,
          baseUrl: baseUrl,
          vaultId: vaultId,
          idToken: idToken,
        ),
        onProgress: reporter.onProgress,
      );
      reporter.complete();
      await _clearManagedVaultBackgroundSyncBlockers(
        baseUrl: baseUrl,
        vaultId: vaultId,
        syncKey: syncKey,
      );
      reopenManagedVaultWriteGateOnSuccess(engine);
      return _ManagedVaultPushStageResult.success(pushed);
    } catch (error) {
      final details = _applyManagedVaultPushFailure(error, engine: engine);
      await _persistManagedVaultBackgroundRepairBlock(
        error,
        baseUrl: baseUrl,
        vaultId: vaultId,
        syncKey: syncKey,
      );
      if (!allowRecovery ||
          details.recoveryAction ==
              ManagedVaultPushFailureRecoveryAction.none) {
        rethrow;
      }
      return _ManagedVaultPushStageResult(
        pushed: 0,
        recoveryAction: details.recoveryAction,
        recoveredMessage: details.writeGateState == null
            ? null
            : _managedVaultRecoveredMessageForGate(details.writeGateState!),
      );
    }
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
    var pulled = 0;
    var recoveredOnly = false;
    var retryPushAfterPull = false;
    var refreshedLocalState = false;
    String? recoveredMessage;
    final initialPush = await _runManagedVaultPushStageWithProgress(
      backend: backend,
      sessionKey: sessionKey,
      syncKey: syncKey,
      engine: engine,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
      stage: stage,
      progress: progress,
      hasTotal: hasTotal,
      allowRecovery: true,
    );
    pushed = initialPush.pushed;
    retryPushAfterPull = initialPush.recoveryAction ==
        ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;
    recoveredOnly = initialPush.recoveryAction ==
        ManagedVaultPushFailureRecoveryAction.pullOnly;
    recoveredMessage = initialPush.recoveredMessage;

    pulled = await _runManagedVaultPullStageWithProgress(
      backend: backend,
      sessionKey: sessionKey,
      syncKey: syncKey,
      baseUrl: baseUrl,
      vaultId: vaultId,
      idToken: idToken,
      stage: stage,
      progress: progress,
      hasTotal: hasTotal,
    );
    refreshedLocalState = true;
    if (retryPushAfterPull) {
      final retryPush = await _runManagedVaultPushStageWithProgress(
        backend: backend,
        sessionKey: sessionKey,
        syncKey: syncKey,
        engine: engine,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
        stage: stage,
        progress: progress,
        hasTotal: hasTotal,
        allowRecovery: false,
      );
      pushed = retryPush.pushed;
      recoveredOnly = false;
      pulled = await _runManagedVaultPullStageWithProgress(
        backend: backend,
        sessionKey: sessionKey,
        syncKey: syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
        stage: stage,
        progress: progress,
        hasTotal: hasTotal,
      );
      refreshedLocalState = true;
    }
    stage.value = t.sync.progressDialog.finalizing;
    return _ManagedVaultManualPushResult(
      pushed: pushed,
      pulled: pulled,
      recoveredOnly: recoveredOnly,
      recoveredMessage: recoveredMessage,
      refreshedLocalState: refreshedLocalState,
    );
  }

  Future<int> _runManagedVaultPullStageWithProgress({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required ValueNotifier<String> stage,
    required ValueNotifier<double?> progress,
    required ValueNotifier<bool> hasTotal,
  }) async {
    final t = context.t;
    stage.value = t.sync.progressDialog.pulling;
    progress.value = 0.0;
    hasTotal.value = false;
    final pullProgressReporter = _makeSmoothStageProgressReporter(
      progress,
      onHasTotal: () => hasTotal.value = true,
    );
    final pulled = await _consumeRustProgressStream(
      backend.syncManagedVaultPullProgress(
        sessionKey,
        syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      ),
      onProgress: pullProgressReporter.onProgress,
    );
    pullProgressReporter.complete();
    return pulled;
  }
}
