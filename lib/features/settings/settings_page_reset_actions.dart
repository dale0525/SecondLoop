part of 'settings_page.dart';

extension _SettingsPageResetActions on _SettingsPageState {
  String _joinRemotePath(String root, String child) {
    final r = root.trim().replaceAll(RegExp(r'/+$'), '');
    final c = child.trim().replaceAll(RegExp(r'^/+'), '');
    if (r.isEmpty) return c;
    if (c.isEmpty) return r;
    return '$r/$c';
  }

  bool _isOperationTimeoutError(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('operation timeout') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  bool _isDestructiveSyncStopTimeout(Object error) {
    return error is TimeoutException &&
        (error.message?.contains(
              'sync engine did not stop before destructive operation',
            ) ??
            false);
  }

  Future<void> _disableAutoSyncAfterDebugResetCleanup({
    required AppBackend backend,
    required SyncConfigStore store,
  }) async {
    await store.writeAutoEnabled(false);
    try {
      await BackgroundSync.refreshSchedule(
        backend: backend,
        configStore: store,
      );
    } catch (e) {
      debugPrint(
        'settings debug reset: failed to refresh schedule after disabling sync: $e',
      );
    }
  }

  SyncConfigStore _syncConfigStore(BuildContext context) {
    final webSettings = WebFormalSettingsScope.maybeOf(context)?.dependencies;
    return webSettings?.vaultConfigStore ?? SyncConfigStore();
  }

  Future<void> _resetLocalData({required bool clearAllRemoteData}) async {
    if (_busy) return;

    final t = context.t;
    final dialogTitle = clearAllRemoteData
        ? t.settingsReset.resetLocalDataAllDevices.dialogTitle
        : t.settingsReset.resetLocalDataThisDeviceOnly.dialogTitle;
    final dialogBody = _normalizeAppLockWording(clearAllRemoteData
        ? t.settingsReset.resetLocalDataAllDevices.dialogBody
        : t.settingsReset.resetLocalDataThisDeviceOnly.dialogBody);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: Text(dialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t.common.actions.reset),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final backend = AppBackendScope.of(context);
    final lock = SessionScope.of(context).lock;
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final engine = SyncEngineScope.maybeOf(context);
    final store = _syncConfigStore(context);
    final wasEngineRunning = engine?.isRunning ?? false;
    var shouldRestartEngine = wasEngineRunning;
    var remoteClearSucceeded = false;
    var remoteClearTimedOut = false;
    var localResetCommitted = false;
    var autoSyncDisabledAfterCleanup = false;

    _setState(() => _busy = true);
    try {
      await engine?.stopImmediatelyAndWait(
        timeout: kDestructiveSyncStopTimeout,
      );
      final sync = await store.loadConfiguredSync();
      if (sync != null) {
        final deviceId =
            clearAllRemoteData ? null : await backend.getOrCreateDeviceId();
        try {
          await switch (sync.backendType) {
            SyncBackendType.webdav => backend.syncWebdavClearRemoteRoot(
                baseUrl: sync.baseUrl ?? '',
                username: sync.username,
                password: sync.password,
                remoteRoot: deviceId == null
                    ? sync.remoteRoot
                    : _joinRemotePath(sync.remoteRoot, deviceId),
              ),
            SyncBackendType.localDir => backend.syncLocaldirClearRemoteRoot(
                localDir: sync.localDir ?? '',
                remoteRoot: deviceId == null
                    ? sync.remoteRoot
                    : _joinRemotePath(sync.remoteRoot, deviceId),
              ),
            SyncBackendType.managedVault => () async {
                final idToken = await readCloudAuthIdToken(
                  CloudAuthScope.maybeOf(context)?.controller,
                  mode: CloudAuthAccessMode.interactive,
                );
                if (idToken == null || idToken.trim().isEmpty) {
                  throw StateError('missing_cloud_id_token');
                }
                final baseUrl = sync.baseUrl ?? '';
                if (baseUrl.trim().isEmpty) {
                  throw StateError('missing_base_url');
                }

                if (deviceId == null) {
                  await backend.syncManagedVaultClearVault(
                    baseUrl: baseUrl,
                    vaultId: sync.remoteRoot,
                    idToken: idToken,
                  );
                  return;
                }

                await backend.syncManagedVaultClearDevice(
                  baseUrl: baseUrl,
                  vaultId: sync.remoteRoot,
                  idToken: idToken,
                  deviceId: deviceId,
                );
              }(),
          };
          remoteClearSucceeded = true;
        } catch (e) {
          if (!(clearAllRemoteData && _isOperationTimeoutError(e))) {
            rethrow;
          }
          remoteClearTimedOut = true;
          debugPrint(
            'settings debug reset: ignored remote clear timeout in all-devices mode: $e',
          );
        }
      }

      if (remoteClearTimedOut) {
        shouldRestartEngine = false;
        await _disableAutoSyncAfterDebugResetCleanup(
          backend: backend,
          store: store,
        );
        autoSyncDisabledAfterCleanup = true;
      }

      Object? committedCleanupFailure;
      try {
        await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
        localResetCommitted = true;
      } catch (e) {
        if (!isVaultResetCommittedCleanupFailure(e)) {
          rethrow;
        }
        localResetCommitted = true;
        committedCleanupFailure = e;
        debugPrint(
          'settings debug reset: local vault reset committed but cleanup failed: $e',
        );
      }
      shouldRestartEngine = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_SettingsPageState._kAppLockEnabledPrefsKey);
      await prefs.remove(_SettingsPageState._kBiometricUnlockEnabledPrefsKey);
      await backend.clearSavedSessionKey();

      await BackgroundSync.refreshSchedule(
        backend: backend,
        configStore: store,
      );

      if (committedCleanupFailure != null && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              clearAllRemoteData
                  ? t.settingsReset.resetLocalDataAllDevices
                      .cleanupFailedAfterCommit(
                      error: '$committedCleanupFailure',
                    )
                  : t.settingsReset.resetLocalDataThisDeviceOnly
                      .cleanupFailedAfterCommit(
                      error: '$committedCleanupFailure',
                    ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (_isDestructiveSyncStopTimeout(e)) {
        shouldRestartEngine = false;
      }
      var displayError = e;
      if (remoteClearSucceeded || remoteClearTimedOut || localResetCommitted) {
        shouldRestartEngine = false;
        if (!autoSyncDisabledAfterCleanup) {
          try {
            await _disableAutoSyncAfterDebugResetCleanup(
              backend: backend,
              store: store,
            );
            autoSyncDisabledAfterCleanup = true;
          } catch (disableError) {
            displayError = StateError(
              '$e; failed to disable sync after destructive cleanup: '
              '$disableError',
            );
          }
        }
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(clearAllRemoteData
              ? t.settingsReset.resetLocalDataAllDevices
                  .failed(error: '$displayError')
              : t.settingsReset.resetLocalDataThisDeviceOnly.failed(
                  error: '$displayError',
                )),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    } finally {
      if (shouldRestartEngine) {
        engine?.start();
      }
      _setState(() => _busy = false);
    }

    if (!mounted) return;
    lock();
  }
}
