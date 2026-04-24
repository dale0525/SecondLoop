part of 'sync_settings_page.dart';

extension _SyncSettingsPageSwitchDirection on _SyncSettingsPageState {
  bool _shouldRunSaveSyncForConfigChange({
    required SyncBackendType oldBackendType,
    required String oldWebdavBaseUrl,
    required String oldRemoteRoot,
    required String oldLocalDir,
    required SyncBackendType newBackendType,
    required String newWebdavBaseUrl,
    required String newRemoteRoot,
    required String newLocalDir,
  }) {
    if (newBackendType == SyncBackendType.webdav) {
      return oldBackendType != newBackendType ||
          oldWebdavBaseUrl != newWebdavBaseUrl ||
          oldRemoteRoot != newRemoteRoot;
    }
    if (newBackendType == SyncBackendType.localDir) {
      return oldBackendType != newBackendType ||
          oldLocalDir != newLocalDir ||
          oldRemoteRoot != newRemoteRoot;
    }
    if (newBackendType == SyncBackendType.managedVault) {
      return oldBackendType != SyncBackendType.managedVault ||
          oldRemoteRoot != newRemoteRoot;
    }
    return false;
  }

  bool _shouldPromptSyncDirectionForConfigChange({
    required SyncBackendType oldBackendType,
    required String oldWebdavBaseUrl,
    required String oldRemoteRoot,
    required String oldLocalDir,
    required SyncBackendType newBackendType,
    required String newWebdavBaseUrl,
    required String newRemoteRoot,
    required String newLocalDir,
  }) {
    final oldTargetConfigured = switch (oldBackendType) {
      SyncBackendType.webdav =>
        oldWebdavBaseUrl.isNotEmpty && oldRemoteRoot.isNotEmpty,
      SyncBackendType.localDir =>
        oldLocalDir.isNotEmpty && oldRemoteRoot.isNotEmpty,
      SyncBackendType.managedVault => oldRemoteRoot.isNotEmpty,
    };
    if (!oldTargetConfigured) return false;

    return _shouldRunSaveSyncForConfigChange(
      oldBackendType: oldBackendType,
      oldWebdavBaseUrl: oldWebdavBaseUrl,
      oldRemoteRoot: oldRemoteRoot,
      oldLocalDir: oldLocalDir,
      newBackendType: newBackendType,
      newWebdavBaseUrl: newWebdavBaseUrl,
      newRemoteRoot: newRemoteRoot,
      newLocalDir: newLocalDir,
    );
  }

  Future<void> _runWebdavSwitchSyncWithProgress({
    required SyncSwitchDirection direction,
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String? username,
    required String? password,
    required String remoteRoot,
  }) {
    final t = context.t;
    return _runSaveSyncWithProgress(
      run: (stage, progress) async {
        var stageProgress = _makeSmoothStageProgressReporter(progress);
        switch (direction) {
          case SyncSwitchDirection.localReplacesRemote:
            stage.value = t.sync.progressDialog.pushing;
            progress.value = null;
            await backend.syncWebdavClearRemoteRoot(
              baseUrl: baseUrl,
              username: username,
              password: password,
              remoteRoot: remoteRoot,
            );
            await backend.syncWebdavPush(
              sessionKey,
              syncKey,
              baseUrl: baseUrl,
              username: username,
              password: password,
              remoteRoot: remoteRoot,
            );
            break;
          case SyncSwitchDirection.remoteReplacesLocal:
            stage.value = t.sync.progressDialog.pulling;
            progress.value = null;
            await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncWebdavPullProgress(
                sessionKey,
                syncKey,
                baseUrl: baseUrl,
                username: username,
                password: password,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );
            stageProgress.complete();
            break;
          case SyncSwitchDirection.merge:
            stage.value = t.sync.progressDialog.pulling;
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncWebdavPullProgress(
                sessionKey,
                syncKey,
                baseUrl: baseUrl,
                username: username,
                password: password,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );

            stageProgress = _makeSmoothStageProgressReporter(progress);
            stage.value = t.sync.progressDialog.pushing;
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncWebdavPushOpsOnlyProgress(
                sessionKey,
                syncKey,
                baseUrl: baseUrl,
                username: username,
                password: password,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );

            if (_cloudMediaBackupEnabled) {
              await _runWebdavMediaBackupStage(
                backend: backend,
                sessionKey: sessionKey,
                syncKey: syncKey,
                baseUrl: baseUrl,
                username: username,
                password: password,
                remoteRoot: remoteRoot,
                stage: stage,
                progress: progress,
              );
            }
            break;
        }
        stage.value = t.sync.progressDialog.finalizing;
        stageProgress.complete();
      },
    );
  }

  Future<void> _runWebdavMediaBackupStage({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String? username,
    required String? password,
    required String remoteRoot,
    required ValueNotifier<String> stage,
    required ValueNotifier<double?> progress,
  }) async {
    stage.value = context.t.sync.progressDialog.uploadingMedia;
    progress.value = null;

    final runner = CloudMediaBackupRunner(
      store: BackendCloudMediaBackupStore(
        backend: backend,
        sessionKey: sessionKey,
        scopeId: _store.syncStateScopeIdForFields(
          backendType: SyncBackendType.webdav,
          baseUrl: baseUrl,
          username: username,
          remoteRoot: remoteRoot,
          syncKey: syncKey,
        ),
      ),
      client: WebDavCloudMediaBackupClient(
        backend: backend,
        sessionKey: sessionKey,
        syncKey: syncKey,
        baseUrl: baseUrl,
        username: username,
        password: password,
        remoteRoot: remoteRoot,
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
        progress.value =
            totalBytes <= 0 ? 1.0 : (doneBytes / totalBytes).clamp(0.0, 1.0);
      },
    );
    if (result.needsCellularConfirmation) {
      progress.value = 1.0;
    }
  }

  Future<void> _runLocalDirSwitchSyncWithProgress({
    required SyncSwitchDirection direction,
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String localDir,
    required String remoteRoot,
  }) {
    final t = context.t;
    return _runSaveSyncWithProgress(
      run: (stage, progress) async {
        var stageProgress = _makeSmoothStageProgressReporter(progress);
        switch (direction) {
          case SyncSwitchDirection.localReplacesRemote:
            stage.value = t.sync.progressDialog.pushing;
            progress.value = null;
            await backend.syncLocaldirClearRemoteRoot(
              localDir: localDir,
              remoteRoot: remoteRoot,
            );
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncLocaldirPushProgress(
                sessionKey,
                syncKey,
                localDir: localDir,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );
            stageProgress.complete();
            break;
          case SyncSwitchDirection.remoteReplacesLocal:
            stage.value = t.sync.progressDialog.pulling;
            progress.value = null;
            await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncLocaldirPullProgress(
                sessionKey,
                syncKey,
                localDir: localDir,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );
            stageProgress.complete();
            break;
          case SyncSwitchDirection.merge:
            stage.value = t.sync.progressDialog.pulling;
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncLocaldirPullProgress(
                sessionKey,
                syncKey,
                localDir: localDir,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );

            stageProgress = _makeSmoothStageProgressReporter(progress);
            stage.value = t.sync.progressDialog.pushing;
            progress.value = 0.0;
            await _consumeRustProgressStream(
              backend.syncLocaldirPushProgress(
                sessionKey,
                syncKey,
                localDir: localDir,
                remoteRoot: remoteRoot,
              ),
              onProgress: stageProgress.onProgress,
            );
            break;
        }
        stage.value = t.sync.progressDialog.finalizing;
        stageProgress.complete();
      },
    );
  }
}
