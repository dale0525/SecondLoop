part of 'sync_settings_page.dart';

bool _isVaultResetCommittedCleanupFailure(Object error) {
  return error
      .toString()
      .contains('filesystem cleanup failed after vault reset commit');
}

bool _isDestructiveSyncStopTimeout(Object error) {
  return error is TimeoutException &&
      (error.message?.contains(
            'sync engine did not stop before destructive operation',
          ) ??
          false);
}

final class _AutoSyncDisableAfterDestructiveCleanupException
    implements Exception {
  const _AutoSyncDisableAfterDestructiveCleanupException(this.cause);

  final Object cause;

  @override
  String toString() =>
      'failed to disable sync after destructive cleanup: $cause';
}

extension _SyncSettingsPageDeleteActions on _SyncSettingsPageState {
  bool _isOperationTimeoutError(Object error) {
    if (error is TimeoutException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('operation timeout') ||
        message.contains('timed out');
  }

  Future<void> _disableAutoSyncAndRefreshSchedule(AppBackend backend) async {
    await _store.writeAutoEnabled(false);
    if (mounted) {
      _setState(() => _autoEnabled = false);
    } else {
      _autoEnabled = false;
    }
    unawaited(BackgroundSync.refreshSchedule(
      backend: backend,
      configStore: _store,
    ).catchError((e) {
      debugPrint(
        'sync settings delete-all: failed to refresh schedule after disabling sync: $e',
      );
    }));
  }

  Future<void> _disableAutoSyncAfterDestructiveCleanup(
    AppBackend backend,
  ) async {
    try {
      await _disableAutoSyncAndRefreshSchedule(backend);
    } catch (e) {
      debugPrint(
        'sync settings delete-all: failed to disable sync after destructive cleanup: $e',
      );
      throw _AutoSyncDisableAfterDestructiveCleanupException(e);
    }
  }

  Future<bool> _confirmDeleteAction({
    required String title,
    required String message,
    required String secondTitle,
    required String secondMessage,
  }) async {
    final t = context.t;
    final firstConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.sync.localData.dialog.confirm),
            ),
          ],
        );
      },
    );
    if (!mounted || firstConfirmed != true) return false;

    final secondConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(secondTitle),
          content: Text(secondMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.common.actions.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.sync.localData.dialog.confirm),
            ),
          ],
        );
      },
    );
    if (!mounted) return false;
    return secondConfirmed == true;
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

  String _deleteActionErrorMessage(Object error) {
    if (error is StateError) {
      return error.message.toString();
    }
    return '$error';
  }

  Future<void> _clearRemoteSyncDataForSavedConfig() async {
    final backend = AppBackendScope.of(context);
    final cloudAuthController = CloudAuthScope.maybeOf(context)?.controller;
    final signInRequired = context.t.sync.cloudManagedVault.signInRequired;
    final notConfigured = context.t.sync.allData.notConfigured;
    final all = await _store.readAll();
    final backendType = await _store.readBackendType();

    switch (backendType) {
      case SyncBackendType.webdav:
        final baseUrl = (all[SyncConfigStore.kWebdavBaseUrl] ?? '').trim();
        final remoteRoot = (all[SyncConfigStore.kRemoteRoot] ?? '').trim();
        if (baseUrl.isEmpty) {
          throw StateError(notConfigured);
        }
        if (remoteRoot.isEmpty) {
          throw StateError(notConfigured);
        }
        await backend.syncWebdavClearRemoteRoot(
          baseUrl: baseUrl,
          username: (all[SyncConfigStore.kWebdavUsername] ?? '').trim().isEmpty
              ? null
              : all[SyncConfigStore.kWebdavUsername]!.trim(),
          password: await _store.readWebdavPassword(),
          remoteRoot: remoteRoot,
        );
        return;
      case SyncBackendType.localDir:
        final localDir = (all[SyncConfigStore.kLocalDir] ?? '').trim();
        final remoteRoot = (all[SyncConfigStore.kRemoteRoot] ?? '').trim();
        if (localDir.isEmpty) {
          throw StateError(notConfigured);
        }
        if (remoteRoot.isEmpty) {
          throw StateError(notConfigured);
        }
        await backend.syncLocaldirClearRemoteRoot(
          localDir: localDir,
          remoteRoot: remoteRoot,
        );
        return;
      case SyncBackendType.managedVault:
        final remoteRoot = (all[SyncConfigStore.kRemoteRoot] ?? '').trim();
        if (remoteRoot.isEmpty) {
          throw StateError(notConfigured);
        }
        final signedInUid = cloudAuthController?.uid?.trim();
        if (signedInUid == null ||
            signedInUid.isEmpty ||
            signedInUid != remoteRoot) {
          throw StateError(signInRequired);
        }
        final idToken = await readCloudAuthIdToken(
          cloudAuthController,
          mode: CloudAuthAccessMode.interactive,
        );
        if (idToken == null || idToken.trim().isEmpty) {
          throw StateError(signInRequired);
        }
        final baseUrl = await _store.resolveManagedVaultBaseUrl();
        if (baseUrl == null || baseUrl.trim().isEmpty) {
          throw StateError(notConfigured);
        }
        await backend.syncManagedVaultClearVault(
          baseUrl: baseUrl.trim(),
          vaultId: remoteRoot,
          idToken: idToken,
        );
        return;
    }
  }

  Future<void> _deleteAllSyncData() async {
    if (_busy) return;

    final t = context.t;
    final confirmed = await _confirmDeleteAction(
      title: t.sync.allData.dialog.title,
      message: t.sync.allData.dialog.message,
      secondTitle: t.sync.allData.secondDialog.title,
      secondMessage: t.sync.allData.secondDialog.message,
    );
    if (!mounted || confirmed != true) return;

    final engine = SyncEngineScope.maybeOf(context);
    final wasRunning = engine?.isRunning ?? false;
    var shouldRestartEngine = wasRunning;
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    _setState(() {
      _busy = true;
      _deleteProgressMessage = t.sync.deleteProgress.allData;
    });
    var shouldNotifyExternalChange = false;
    var remoteClearSucceeded = false;
    var remoteClearTimedOut = false;
    try {
      await engine?.stopImmediatelyAndWait(
        timeout: kDestructiveSyncStopTimeout,
      );
      try {
        await _clearRemoteSyncDataForSavedConfig();
        remoteClearSucceeded = true;
      } catch (e) {
        if (!_isOperationTimeoutError(e)) {
          rethrow;
        }
        remoteClearTimedOut = true;
        debugPrint(
          'sync settings delete-all: ignored remote clear timeout: $e',
        );
      }
      await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
      engine?.writeGate.value = const SyncWriteGateState.open();
      if (remoteClearTimedOut) {
        shouldRestartEngine = false;
        await _disableAutoSyncAfterDestructiveCleanup(backend);
      }
      unawaited(BackgroundSync.refreshSchedule(
        backend: backend,
        configStore: _store,
      ).catchError((e) {
        debugPrint(
          'sync settings delete-all: failed to refresh schedule after reset: $e',
        );
      }));

      shouldNotifyExternalChange = true;
      if (mounted) {
        _showSnack(
          remoteClearTimedOut
              ? t.sync.allData.deletedLocalOnly
              : t.sync.allData.deleted,
        );
      }
    } catch (e) {
      if (_isDestructiveSyncStopTimeout(e)) {
        shouldRestartEngine = false;
      }
      if (_isVaultResetCommittedCleanupFailure(e)) {
        engine?.writeGate.value = const SyncWriteGateState.open();
        shouldNotifyExternalChange = true;
      }
      var displayError = e;
      final autoSyncDisableFailure =
          e is _AutoSyncDisableAfterDestructiveCleanupException;
      if (remoteClearSucceeded || remoteClearTimedOut) {
        shouldRestartEngine = false;
        if (!autoSyncDisableFailure) {
          try {
            await _disableAutoSyncAfterDestructiveCleanup(backend);
          } catch (disableError) {
            displayError = StateError(
              '${_deleteActionErrorMessage(e)}; '
              '${_deleteActionErrorMessage(disableError)}',
            );
          }
        }
      }
      if (mounted) {
        _showSnack(
          autoSyncDisableFailure
              ? t.sync.allData.failed(
                  error: _deleteActionErrorMessage(displayError),
                )
              : remoteClearTimedOut
                  ? t.sync.allData.remoteClearUnknownLocalCleanupFailed(
                      error: _deleteActionErrorMessage(displayError),
                    )
                  : remoteClearSucceeded
                      ? t.sync.allData.remoteDeletedLocalCleanupFailed(
                          error: _deleteActionErrorMessage(displayError),
                        )
                      : t.sync.allData.failed(
                          error: _deleteActionErrorMessage(displayError),
                        ),
        );
      }
    } finally {
      if (shouldRestartEngine) {
        engine?.start();
      }
      if (shouldNotifyExternalChange) {
        engine?.notifyExternalChange();
      }
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
