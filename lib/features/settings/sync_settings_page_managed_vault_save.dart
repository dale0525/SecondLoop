part of 'sync_settings_page.dart';

final class _ManagedVaultSaveConfigurationException implements Exception {
  const _ManagedVaultSaveConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _SyncSettingsPageManagedVaultSave on _SyncSettingsPageState {
  Future<bool> _runManagedVaultSaveSync({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required SyncEngine? engine,
    required SyncSwitchDirection direction,
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
      if (direction == SyncSwitchDirection.merge) {
        // Non-destructive merge can still fall back to regular engine scheduling.
        return false;
      }
      final message = baseUrl == null || baseUrl.trim().isEmpty
          ? context.t.sync.baseUrlRequired
          : context.t.sync.cloudManagedVault.signInRequired;
      throw _ManagedVaultSaveConfigurationException(message);
    }

    if (!mounted) {
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
          var allowMediaUploads = false;
          final hasTotal = ValueNotifier(false);

          switch (direction) {
            case SyncSwitchDirection.localReplacesRemote:
              await backend.syncManagedVaultClearVault(
                baseUrl: baseUrlTrimmed,
                vaultId: vaultId,
                idToken: idTokenTrimmed,
              );
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
              break;
            case SyncSwitchDirection.remoteReplacesLocal:
              stage.value = pullingLabel;
              progress.value = 0.0;
              hasTotal.value = false;
              await runDestructiveReplaceLocalWithRollback<void>(
                backend: backend,
                sessionKey: sessionKey,
                run: () => _runManagedVaultPullStageWithProgress(
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: syncKey,
                  baseUrl: baseUrlTrimmed,
                  vaultId: vaultId,
                  idToken: idTokenTrimmed,
                  stage: stage,
                  progress: progress,
                  hasTotal: hasTotal,
                ),
              );
              if (mounted) {
                engine?.notifyExternalChange();
              }
              break;
            case SyncSwitchDirection.merge:
              var retryPushAfterPull = false;
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

              await _runManagedVaultPullStageWithProgress(
                backend: backend,
                sessionKey: sessionKey,
                syncKey: syncKey,
                baseUrl: baseUrlTrimmed,
                vaultId: vaultId,
                idToken: idTokenTrimmed,
                stage: stage,
                progress: progress,
                hasTotal: hasTotal,
              );
              if (mounted) {
                engine?.notifyExternalChange();
              }
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
                await _runManagedVaultPullStageWithProgress(
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: syncKey,
                  baseUrl: baseUrlTrimmed,
                  vaultId: vaultId,
                  idToken: idTokenTrimmed,
                  stage: stage,
                  progress: progress,
                  hasTotal: hasTotal,
                );
                if (mounted) {
                  engine?.notifyExternalChange();
                }
              }
              break;
          }

          if (allowMediaUploads && _cloudMediaBackupEnabled) {
            stage.value = uploadingMediaLabel;
            progress.value = null;

            final runner = CloudMediaBackupRunner(
              store: BackendCloudMediaBackupStore(
                backend: backend,
                sessionKey: sessionKey,
                scopeId: _store.syncStateScopeIdForFields(
                  backendType: SyncBackendType.managedVault,
                  baseUrl: baseUrlTrimmed,
                  remoteRoot: vaultId,
                  syncKey: syncKey,
                ),
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
        },
      );
      return true;
    } finally {
      await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, false);
    }
  }
}
