part of 'sync_settings_page.dart';

extension _SyncSettingsPageManagedVaultSave on _SyncSettingsPageState {
  Future<bool> _runManagedVaultSaveSync({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required SyncEngine? engine,
  }) async {
    final cloudAuth = CloudAuthScope.maybeOf(context)?.controller;
    String? idToken;
    try {
      idToken = await readCloudAuthIdToken(
        cloudAuth,
        mode: CloudAuthAccessMode.interactive,
      );
    } catch (_) {
      idToken = null;
    }
    final vaultId = cloudAuth?.uid?.trim();
    final baseUrl = await _store.resolveManagedVaultBaseUrl();

    if (!mounted) return false;
    if (idToken == null ||
        idToken.trim().isEmpty ||
        vaultId == null ||
        vaultId.isEmpty ||
        baseUrl == null ||
        baseUrl.trim().isEmpty) {
      // If we can't get auth details, fall back to engine scheduling.
      return false;
    }

    final baseUrlTrimmed = baseUrl.trim();
    final idTokenTrimmed = idToken.trim();
    final pullingLabel = context.t.sync.progressDialog.pulling;
    final uploadingMediaLabel = context.t.sync.progressDialog.uploadingMedia;
    final finalizingLabel = context.t.sync.progressDialog.finalizing;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, true);
    try {
      await _runSaveSyncWithProgress(
        run: (stage, progress) async {
          var allowMediaUploads = true;
          var retryPushAfterPull = false;
          final hasTotal = ValueNotifier(false);
          final initialPush = await _runManagedVaultPushStageWithProgress(
            backend: backend,
            sessionKey: sessionKey,
            syncKey: syncKey,
            engine: engine,
            baseUrl: baseUrlTrimmed,
            vaultId: vaultId,
            idToken: idTokenTrimmed,
            stage: stage,
            progress: progress,
            hasTotal: hasTotal,
            allowRecovery: true,
          );
          allowMediaUploads = initialPush.recoveryAction ==
              ManagedVaultPushFailureRecoveryAction.none;
          retryPushAfterPull = initialPush.recoveryAction ==
              ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;

          final stageProgress = _makeSmoothStageProgressReporter(progress);
          stage.value = pullingLabel;
          progress.value = 0.0;
          await _consumeRustProgressStream(
            backend.syncManagedVaultPullProgress(
              sessionKey,
              syncKey,
              baseUrl: baseUrlTrimmed,
              vaultId: vaultId,
              idToken: idTokenTrimmed,
            ),
            onProgress: stageProgress.onProgress,
          );
          if (retryPushAfterPull) {
            await _runManagedVaultPushStageWithProgress(
              backend: backend,
              sessionKey: sessionKey,
              syncKey: syncKey,
              engine: engine,
              baseUrl: baseUrlTrimmed,
              vaultId: vaultId,
              idToken: idTokenTrimmed,
              stage: stage,
              progress: progress,
              hasTotal: hasTotal,
              allowRecovery: false,
            );
            allowMediaUploads = true;
          }

          if (allowMediaUploads && _cloudMediaBackupEnabled) {
            stage.value = uploadingMediaLabel;
            progress.value = null;

            final runner = CloudMediaBackupRunner(
              store: BackendCloudMediaBackupStore(
                backend: backend,
                sessionKey: sessionKey,
              ),
              client: ManagedVaultCloudMediaBackupClient(
                backend: backend,
                sessionKey: sessionKey,
                syncKey: syncKey,
                baseUrl: baseUrlTrimmed,
                vaultId: vaultId,
                idToken: idTokenTrimmed,
              ),
              settings: CloudMediaBackupRunnerSettings(
                enabled: true,
                wifiOnly: _cloudMediaBackupWifiOnly,
              ),
              getNetwork: ConnectivityCloudMediaBackupNetworkProvider().call,
            );
            final result = await runner.runOnce(
              allowCellular: false,
              onBytesProgress: (doneBytes, totalBytes) {
                progress.value = totalBytes <= 0
                    ? 1.0
                    : (doneBytes / totalBytes).clamp(0.0, 1.0);
              },
            );
            if (result.needsCellularConfirmation) {
              progress.value = 1.0;
            }
          }

          stage.value = finalizingLabel;
          stageProgress.complete();
        },
      );
      return true;
    } finally {
      await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, false);
    }
  }
}
