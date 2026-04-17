part of 'sync_settings_page.dart';

extension _SyncSettingsPageManagedVaultSync on _SyncSettingsPageState {
  Future<int> _runManagedVaultManualPushWithProgress({
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
    try {
      pushed = await _consumeRustProgressStream(
        backend.syncManagedVaultPushOpsOnlyProgress(
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
    } catch (error) {
      final nextWriteGate = managedVaultWriteGateStateForError(error);
      if (nextWriteGate != null) engine?.writeGate.value = nextWriteGate;
      if (!managedVaultPushFailureAllowsPull(error)) rethrow;
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
    if (engine != null &&
        managedVaultWriteGateShouldClearAfterPull(engine.writeGate.value)) {
      engine.writeGate.value = const SyncWriteGateState.open();
    }
    stage.value = t.sync.progressDialog.finalizing;
    pullProgressReporter.complete();
    return pushed;
  }
}
