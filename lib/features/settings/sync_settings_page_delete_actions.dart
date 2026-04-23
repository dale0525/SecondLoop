part of 'sync_settings_page.dart';

extension _SyncSettingsPageDeleteActions on _SyncSettingsPageState {
  bool _isOperationTimeoutError(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('operation timeout') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  Widget _buildDeleteActionsRow({
    required bool canClearLocalCache,
  }) {
    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );

    Widget actionButton({
      required String label,
      required VoidCallback? onPressed,
    }) {
      return Expanded(
        child: OutlinedButton(
          onPressed: onPressed,
          style: buttonStyle,
          child: Text(
            label,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Row(
      key: const ValueKey('sync_delete_actions'),
      children: [
        actionButton(
          label: context.t.sync.localCache.button,
          onPressed:
              _busy || !canClearLocalCache ? null : _clearLocalAttachmentCache,
        ),
        const SizedBox(width: 8),
        actionButton(
          label: context.t.sync.localData.button,
          onPressed: _busy ? null : _deleteLocalSyncData,
        ),
        const SizedBox(width: 8),
        actionButton(
          label: context.t.sync.allData.button,
          onPressed: _busy ? null : _deleteAllSyncData,
        ),
      ],
    );
  }

  String _remoteRootForDeleteAction() {
    final remoteRoot = _requiredTrimmed(_remoteRootController);
    if (remoteRoot.isEmpty) {
      throw StateError(context.t.sync.remoteRootRequired);
    }
    return remoteRoot;
  }

  Future<String> _managedVaultBaseUrlForDeleteAction() async {
    final baseUrlRequired = context.t.sync.baseUrlRequired;
    final override = _optionalTrimmed(_managedVaultBaseUrlController);
    if (kDebugMode && _showManagedVaultEndpointOverride && override != null) {
      return override;
    }
    final resolved = (await _store.resolveManagedVaultBaseUrl())?.trim();
    if (resolved == null || resolved.isEmpty) {
      throw StateError(baseUrlRequired);
    }
    return resolved;
  }

  Future<void> _clearRemoteSyncDataForCurrentBackend() async {
    final backend = AppBackendScope.of(context);
    final signInRequired = context.t.sync.cloudManagedVault.signInRequired;

    switch (_effectiveBackendType) {
      case SyncBackendType.webdav:
        final baseUrl = _requiredTrimmed(_baseUrlController);
        if (baseUrl.isEmpty) {
          throw StateError(context.t.sync.baseUrlRequired);
        }
        await backend.syncWebdavClearRemoteRoot(
          baseUrl: baseUrl,
          username: _optionalTrimmed(_usernameController),
          password: _optionalTrimmed(_passwordController),
          remoteRoot: _remoteRootForDeleteAction(),
        );
        return;
      case SyncBackendType.localDir:
        final localDir = _requiredTrimmed(_localDirController);
        if (localDir.isEmpty) {
          throw StateError(context.t.sync.localDirRequired);
        }
        await backend.syncLocaldirClearRemoteRoot(
          localDir: localDir,
          remoteRoot: _remoteRootForDeleteAction(),
        );
        return;
      case SyncBackendType.managedVault:
        final controller = CloudAuthScope.maybeOf(context)?.controller;
        final idToken = await readCloudAuthIdToken(
          controller,
          mode: CloudAuthAccessMode.interactive,
        );
        if (idToken == null || idToken.trim().isEmpty) {
          throw StateError(signInRequired);
        }
        await backend.syncManagedVaultClearVault(
          baseUrl: await _managedVaultBaseUrlForDeleteAction(),
          vaultId: _remoteRootForDeleteAction(),
          idToken: idToken,
        );
        return;
    }
  }

  Future<void> _deleteAllSyncData() async {
    if (_busy) return;

    final t = context.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.sync.allData.dialog.title),
          content: Text(t.sync.allData.dialog.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.sync.allData.dialog.confirm),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (confirmed != true) return;

    final engine = SyncEngineScope.maybeOf(context);
    engine?.stop();
    _setState(() => _busy = true);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      try {
        await _clearRemoteSyncDataForCurrentBackend();
      } catch (e) {
        if (!_isOperationTimeoutError(e)) {
          rethrow;
        }
        debugPrint(
          'sync settings delete-all: ignored remote clear timeout: $e',
        );
      }
      await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
      unawaited(
          BackgroundSync.refreshSchedule(backend: backend).catchError((e) {
        debugPrint(
          'sync settings delete-all: failed to refresh schedule after reset: $e',
        );
      }));

      if (!mounted) return;
      engine?.notifyExternalChange();
      _showSnack(t.sync.allData.deleted);
    } catch (e) {
      if (!mounted) return;
      _showSnack(t.sync.allData.failed(error: '$e'));
    } finally {
      if (mounted) {
        _setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }
}
