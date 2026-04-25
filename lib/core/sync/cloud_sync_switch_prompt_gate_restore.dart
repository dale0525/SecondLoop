part of 'cloud_sync_switch_prompt_gate.dart';

Future<void> _restoreCloudSyncPreviousSyncConfig(
  _CloudSyncSwitchPromptGateState state, {
  required AppBackend backend,
  required SyncBackendType previousBackendType,
  required String? previousWebdavBaseUrl,
  required String? previousWebdavUsername,
  required String? previousWebdavPassword,
  required String? previousLocalDir,
  required String? previousManagedVaultBaseUrl,
  required String? previousRemoteRoot,
  required bool previousAutoEnabled,
  required Uint8List? previousSyncKey,
  required SyncEngine? engine,
  bool refreshSchedule = true,
}) async {
  switch (previousBackendType) {
    case SyncBackendType.webdav:
      await state._store.writeWebdavPassword(previousWebdavPassword);
      await state._store.writeWebdavSyncSettings(
        baseUrl: previousWebdavBaseUrl ?? '',
        username: previousWebdavUsername,
        remoteRoot: previousRemoteRoot ?? '',
        autoEnabled: previousAutoEnabled,
      );
      break;
    case SyncBackendType.localDir:
      await state._store.writeLocalDirSyncSettings(
        localDir: previousLocalDir ?? '',
        remoteRoot: previousRemoteRoot ?? '',
        autoEnabled: previousAutoEnabled,
      );
      break;
    case SyncBackendType.managedVault:
      await state._store.writeManagedVaultBaseUrl(previousManagedVaultBaseUrl);
      await state._store.writeManagedVaultSyncSettings(
        baseUrl: previousManagedVaultBaseUrl,
        remoteRoot: previousRemoteRoot ?? '',
        autoEnabled: previousAutoEnabled,
      );
      break;
  }
  if (previousSyncKey != null) {
    await SyncKeyManager.save(
      write: state._store.writeSyncKey,
      key: previousSyncKey,
    );
  } else {
    await state._store.clearSyncKey();
  }
  if (previousBackendType != SyncBackendType.managedVault) {
    engine?.writeGate.value = const SyncWriteGateState.open();
  }
  if (refreshSchedule) {
    await _refreshCloudSyncSwitchBackgroundScheduleBestEffort(
      backend: backend,
      store: state._store,
    );
  }
}

Future<void> _refreshCloudSyncSwitchBackgroundScheduleBestEffort({
  required AppBackend backend,
  required SyncConfigStore store,
}) async {
  try {
    await BackgroundSync.refreshSchedule(
      backend: backend,
      configStore: store,
    );
  } catch (e) {
    debugPrint(
      'cloud sync switch: failed to refresh background sync schedule: $e',
    );
  }
}
