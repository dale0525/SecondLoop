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

  Future<void> _setChatThumbnailsWifiOnly(bool enabled) async {
    await _store.writeChatThumbnailsWifiOnly(enabled);
    if (!mounted) return;
    _setState(() => _chatThumbnailsWifiOnly = enabled);
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

  Future<void> _backfillCloudMediaBackupImages() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final now = DateTime.now().millisecondsSinceEpoch;
      final enqueued = await backend.backfillCloudMediaBackupImages(
        sessionKey,
        desiredVariant: 'original',
        nowMs: now,
      );
      if (!mounted) return;
      _showSnack(t.sync.mediaBackup.backfillEnqueued(count: enqueued));
      _refreshCloudMediaBackupSummary();
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

      final syncKey = await _loadSyncKey();
      if (!mounted) return;
      if (syncKey == null || syncKey.length != 32) {
        _showSnack(t.sync.missingSyncKey);
        return;
      }

      CloudMediaBackupRunner? runner;
      switch (_backendType) {
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
          final cloudAuth = CloudAuthScope.of(context).controller;
          final idToken = await cloudAuth.getIdToken();
          if (!mounted) return;
          if (idToken == null || idToken.trim().isEmpty) {
            _showSnack(t.sync.cloudManagedVault.signInRequired);
            return;
          }

          final vaultId = cloudAuth.uid ?? '';
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
      _refreshCloudMediaBackupSummary();
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
}
