part of 'sync_settings_page.dart';

extension _SyncSettingsPageMediaActions on _SyncSettingsPageState {
  Future<void> _setCloudMediaBackupEnabled(bool enabled) async {
    await _store.writeCloudMediaBackupEnabled(enabled);
    if (!mounted) return;
    _setState(() => _cloudMediaBackupEnabled = enabled);
  }

  Future<void> _setAutoWifiOnly(bool enabled) async {
    await _store.writeAutoWifiOnly(enabled);
    if (!mounted) return;
    _setState(() => _autoWifiOnly = enabled);
  }

  Future<void> _setMediaDownloadsWifiOnly(bool enabled) async {
    await _store.writeMediaDownloadsWifiOnly(enabled);
    if (!mounted) return;
    _setState(() => _mediaDownloadsWifiOnly = enabled);
  }

  Future<void> _setCloudMediaBackupWifiOnly(bool enabled) async {
    await _store.writeCloudMediaBackupWifiOnly(enabled);
    if (!mounted) return;
    _setState(() => _cloudMediaBackupWifiOnly = enabled);
  }

  Future<void> _copyText(String value) async {
    final copied = context.t.common.actions.copy;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showSnack(copied);
  }

  Future<void> _backfillCloudMediaBackupFiles() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final now = DateTime.now().millisecondsSinceEpoch;
      final syncKey = await _resolveSyncKeyForCurrentBackend(backend);
      if (!mounted) return;
      final scopeId = await _currentSyncStateScopeId(syncKey: syncKey);
      final enqueued = await backend.backfillCloudMediaBackupImages(
        sessionKey,
        desiredVariant: 'original',
        nowMs: now,
        scopeId: scopeId,
      );
      if (scopeId != null) {
        await _store.writeCloudMediaBackupBackfillDone(
          scopeId: scopeId,
          done: true,
        );
      }
      if (!mounted) return;
      _showSnack(t.sync.mediaBackup.backfillEnqueued(count: enqueued));
      _refreshCloudMediaBackupSummary(scopeId: scopeId);
    } catch (e) {
      if (!mounted) return;
      _showSnack(t.sync.mediaBackup.backfillFailed(error: '$e'));
    } finally {
      if (mounted) _setState(() => _busy = false);
    }
  }

  Future<void> _uploadCloudMediaBackupNow() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
    try {
      if (!_cloudMediaBackupEnabled) {
        _showSnack(t.sync.mediaBackup.notEnabled);
        return;
      }

      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final cloudAuthController =
          _effectiveBackendType == SyncBackendType.managedVault
              ? CloudAuthScope.of(context).controller
              : null;

      final syncKey = await _resolveSyncKeyForCurrentBackend(backend);
      if (!mounted) return;
      final scopeId = await _currentSyncStateScopeId(syncKey: syncKey);

      CloudMediaBackupRunner? runner;
      switch (_effectiveBackendType) {
        case SyncBackendType.webdav:
          final baseUrl = _requiredTrimmed(_baseUrlController);
          if (baseUrl.isEmpty) {
            _showSnack(t.sync.baseUrlRequired);
            return;
          }
          runner = CloudMediaBackupRunner(
            store: BackendCloudMediaBackupStore(
              backend: backend,
              sessionKey: sessionKey,
              scopeId: scopeId,
            ),
            client: WebDavCloudMediaBackupClient(
              backend: backend,
              sessionKey: sessionKey,
              syncKey: syncKey,
              baseUrl: baseUrl,
              username: _optionalTrimmed(_usernameController),
              password: _optionalTrimmed(_passwordController),
              remoteRoot: _requiredTrimmed(_remoteRootController),
            ),
            settings: CloudMediaBackupRunnerSettings(
              enabled: true,
              wifiOnly: _cloudMediaBackupWifiOnly,
            ),
            getNetwork: ConnectivityCloudMediaBackupNetworkProvider().call,
          );
          break;
        case SyncBackendType.managedVault:
          if (_usesCloudSessionModel) {
            _showSnack(t.sync.mediaBackup.notEnabled);
            return;
          }
          final idToken = await readCloudAuthIdToken(
            cloudAuthController!,
            mode: CloudAuthAccessMode.interactive,
          );
          if (!mounted) return;
          if (idToken == null || idToken.trim().isEmpty) {
            _showSnack(t.sync.cloudManagedVault.signInRequired);
            return;
          }

          final vaultId = cloudAuthController.uid ?? '';
          final baseUrl = await _store.resolveManagedVaultBaseUrl();
          if (!mounted) return;
          if (baseUrl == null || baseUrl.trim().isEmpty) {
            _showSnack(t.sync.baseUrlRequired);
            return;
          }

          runner = CloudMediaBackupRunner(
            store: BackendCloudMediaBackupStore(
              backend: backend,
              sessionKey: sessionKey,
              scopeId: scopeId,
            ),
            client: ManagedVaultCloudMediaBackupClient(
              backend: backend,
              sessionKey: sessionKey,
              syncKey: syncKey,
              baseUrl: baseUrl,
              vaultId: vaultId,
              idToken: idToken,
            ),
            settings: CloudMediaBackupRunnerSettings(
              enabled: true,
              wifiOnly: _cloudMediaBackupWifiOnly,
            ),
            getNetwork: ConnectivityCloudMediaBackupNetworkProvider().call,
          );
          break;
        case SyncBackendType.localDir:
          _showSnack(t.sync.mediaBackup.managedVaultOnly);
          return;
      }

      var result = await runner.runOnce(allowCellular: false);
      if (!mounted) return;
      if (result.needsCellularConfirmation) {
        final allow = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(t.sync.mediaBackup.cellularDialog.title),
              content: Text(t.sync.mediaBackup.cellularDialog.message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.common.actions.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.sync.mediaBackup.cellularDialog.confirm),
                ),
              ],
            );
          },
        );
        if (!mounted) return;
        if (allow == true) {
          result = await runner.runOnce(allowCellular: true);
          if (!mounted) return;
        } else {
          _showSnack(t.sync.mediaBackup.wifiOnlyBlocked);
          return;
        }
      }

      if (result.didUploadAny) {
        _showSnack(t.sync.mediaBackup.uploaded);
      } else {
        _showSnack(t.sync.mediaBackup.nothingToUpload);
      }
      _refreshCloudMediaBackupSummary(scopeId: scopeId);
    } catch (e) {
      if (!mounted) return;
      _showSnack(t.sync.mediaBackup.uploadFailed(error: '$e'));
    } finally {
      if (mounted) _setState(() => _busy = false);
    }
  }

  Future<void> _clearLocalAttachmentCache() async {
    if (_busy) return;

    final t = context.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.sync.localCache.dialog.title),
          content: Text(t.sync.localCache.dialog.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.sync.localCache.dialog.confirm),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (confirmed != true) return;

    _setState(() => _busy = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      await backend.clearLocalAttachmentCache(sessionKey);
      if (!mounted) return;
      _showSnack(t.sync.localCache.cleared);
    } catch (e) {
      if (!mounted) return;
      _showSnack(t.sync.localCache.failed(error: '$e'));
    } finally {
      if (mounted) _setState(() => _busy = false);
    }
  }

  Future<void> _deleteLocalSyncData() async {
    if (_busy) return;

    final t = context.t;
    final confirmed = await _confirmDeleteAction(
      title: t.sync.localData.dialog.title,
      message: t.sync.localData.dialog.message,
      secondTitle: t.sync.localData.secondDialog.title,
      secondMessage: t.sync.localData.secondDialog.message,
    );
    if (!mounted || confirmed != true) return;

    _setState(() {
      _busy = true;
      _deleteProgressMessage = t.sync.deleteProgress.localData;
    });
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final engine = SyncEngineScope.maybeOf(context);
      final wasRunning = engine?.isRunning ?? false;
      var shouldRestartEngine = wasRunning;

      try {
        await engine?.stopImmediatelyAndWait(
          timeout: kDestructiveSyncStopTimeout,
        );
        await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
        shouldRestartEngine = false;
        engine?.writeGate.value = const SyncWriteGateState.open();
        await _disableAutoSyncAndRefreshSchedule(backend);
      } catch (e) {
        if (_isVaultResetCommittedCleanupFailure(e)) {
          shouldRestartEngine = false;
          engine?.writeGate.value = const SyncWriteGateState.open();
          await _disableAutoSyncAndRefreshSchedule(backend);
          if (!mounted) return;
          engine?.notifyExternalChange();
          _showSnack(t.sync.localData.failed(
            error: _deleteActionErrorMessage(e),
          ));
          return;
        }
        if (_isDestructiveSyncStopTimeout(e)) {
          shouldRestartEngine = false;
        }
        if (shouldRestartEngine) {
          engine?.start();
        }
        rethrow;
      }

      if (!mounted) return;
      engine?.notifyExternalChange();
      _showSnack(t.sync.localData.deleted);
    } catch (e) {
      if (!mounted) return;
      _showSnack(t.sync.localData.failed(error: '$e'));
    } finally {
      if (mounted) {
        _setState(() {
          _busy = false;
          _deleteProgressMessage = null;
        });
      } else {
        _busy = false;
        _deleteProgressMessage = null;
      }
    }
  }
}
