part of 'sync_config_store.dart';

extension SyncConfigStoreBackendSettings on SyncConfigStore {
  Future<SyncBackendType> readBackendType() async {
    final v = (await _loadConfigMap())[SyncConfigStore.kBackendType];
    return switch (v) {
      'localdir' => SyncBackendType.localDir,
      'managedvault' => SyncBackendType.managedVault,
      _ => SyncBackendType.webdav,
    };
  }

  Future<void> writeBackendType(SyncBackendType type) async {
    await _writeConfigUpdates({
      SyncConfigStore.kBackendType: SyncConfigStore._backendTypeToken(type)
    });
  }

  Future<void> writePrimarySyncSettings({
    required SyncBackendType backendType,
    required String remoteRoot,
    bool? autoEnabled,
  }) async {
    await _writeConfigUpdates({
      SyncConfigStore.kBackendType:
          SyncConfigStore._backendTypeToken(backendType),
      SyncConfigStore.kRemoteRoot: remoteRoot,
      if (autoEnabled != null)
        SyncConfigStore.kAutoEnabled: autoEnabled ? '1' : '0',
    });
  }

  Future<void> writeWebdavBaseUrl(String baseUrl) async {
    if (baseUrl.isEmpty) {
      await _writeConfigUpdates({SyncConfigStore.kWebdavBaseUrl: null});
      return;
    }
    await _writeConfigUpdates({SyncConfigStore.kWebdavBaseUrl: baseUrl});
  }

  Future<void> writeManagedVaultBaseUrl(String? baseUrl) async {
    if (baseUrl == null || baseUrl.isEmpty) {
      await _writeConfigUpdates({SyncConfigStore.kManagedVaultBaseUrl: null});
      return;
    }
    await _writeConfigUpdates({SyncConfigStore.kManagedVaultBaseUrl: baseUrl});
  }

  Future<void> writeRemoteRoot(String remoteRoot) async {
    await _writeConfigUpdates({SyncConfigStore.kRemoteRoot: remoteRoot});
  }

  Future<void> writeWebdavUsername(String? username) async {
    if (username == null || username.isEmpty) {
      await _writeConfigUpdates({SyncConfigStore.kWebdavUsername: null});
      return;
    }
    await _writeConfigUpdates({SyncConfigStore.kWebdavUsername: username});
  }

  Future<void> writeLocalDir(String? localDir) async {
    if (localDir == null || localDir.isEmpty) {
      await _writeConfigUpdates({SyncConfigStore.kLocalDir: null});
      return;
    }
    await _writeConfigUpdates({SyncConfigStore.kLocalDir: localDir});
  }

  Future<void> writeWebdavSyncSettings({
    required String baseUrl,
    required String? username,
    required String remoteRoot,
    bool? autoEnabled,
  }) async {
    await _writeConfigUpdates({
      SyncConfigStore.kBackendType:
          SyncConfigStore._backendTypeToken(SyncBackendType.webdav),
      SyncConfigStore.kWebdavBaseUrl: baseUrl.isEmpty ? null : baseUrl,
      SyncConfigStore.kWebdavUsername: username,
      SyncConfigStore.kRemoteRoot: remoteRoot,
      if (autoEnabled != null)
        SyncConfigStore.kAutoEnabled: autoEnabled ? '1' : '0',
    });
  }

  Future<void> writeLocalDirSyncSettings({
    required String localDir,
    required String remoteRoot,
    bool? autoEnabled,
  }) async {
    await _writeConfigUpdates({
      SyncConfigStore.kBackendType:
          SyncConfigStore._backendTypeToken(SyncBackendType.localDir),
      SyncConfigStore.kLocalDir: localDir.isEmpty ? null : localDir,
      SyncConfigStore.kRemoteRoot: remoteRoot,
      if (autoEnabled != null)
        SyncConfigStore.kAutoEnabled: autoEnabled ? '1' : '0',
    });
  }

  Future<void> writeManagedVaultSyncSettings({
    required String? baseUrl,
    required String remoteRoot,
    bool? autoEnabled,
  }) async {
    await _writeConfigUpdates({
      SyncConfigStore.kBackendType:
          SyncConfigStore._backendTypeToken(SyncBackendType.managedVault),
      SyncConfigStore.kManagedVaultBaseUrl: baseUrl,
      SyncConfigStore.kRemoteRoot: remoteRoot,
      if (autoEnabled != null)
        SyncConfigStore.kAutoEnabled: autoEnabled ? '1' : '0',
    });
  }
}
