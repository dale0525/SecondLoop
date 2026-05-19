part of 'settings_page.dart';

enum _ResetLocalDataVariant {
  thisDeviceOnly,
  runtimeHostedDataUnchanged,
}

extension _SettingsPageResetActions on _SettingsPageState {
  bool _isDestructiveSyncStopTimeout(Object error) {
    return error is TimeoutException &&
        (error.message?.contains(
              'sync engine did not stop before destructive operation',
            ) ??
            false);
  }

  Future<void> _resetLocalData({
    required _ResetLocalDataVariant variant,
  }) async {
    if (_busy) return;

    final t = context.t;
    final isRuntimeHostedDataUnchanged =
        variant == _ResetLocalDataVariant.runtimeHostedDataUnchanged;
    final dialogTitle = isRuntimeHostedDataUnchanged
        ? t.settingsReset.resetLocalDataRuntimeHostedDataUnchanged.dialogTitle
        : t.settingsReset.resetLocalDataThisDeviceOnly.dialogTitle;
    final dialogBody = isRuntimeHostedDataUnchanged
        ? t.settingsReset.resetLocalDataRuntimeHostedDataUnchanged.dialogBody
        : t.settingsReset.resetLocalDataThisDeviceOnly.dialogBody;
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
    final messenger = ScaffoldMessenger.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final engine = SyncEngineScope.maybeOf(context);
    final wasEngineRunning = engine?.isRunning ?? false;
    var shouldRestartEngine = wasEngineRunning;

    _setState(() => _busy = true);
    try {
      await engine?.stopImmediatelyAndWait(
        timeout: kDestructiveSyncStopTimeout,
      );

      Object? committedCleanupFailure;
      try {
        await backend.resetVaultDataPreservingLlmProfiles(sessionKey);
      } catch (e) {
        if (!isVaultResetCommittedCleanupFailure(e)) {
          rethrow;
        }
        committedCleanupFailure = e;
        debugPrint(
          'settings debug reset: local vault reset committed but cleanup failed: $e',
        );
      }
      shouldRestartEngine = false;

      final prefs = await SharedPreferences.getInstance();
      for (final prefsKey in const <String>[
        'app_lock_enabled_v1',
        'biometric_unlock_enabled_v1',
        'master_password_setup_required_v1',
      ]) {
        await prefs.remove(prefsKey);
      }

      if (committedCleanupFailure != null && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isRuntimeHostedDataUnchanged
                  ? t.settingsReset.resetLocalDataRuntimeHostedDataUnchanged
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(isRuntimeHostedDataUnchanged
              ? t.settingsReset.resetLocalDataRuntimeHostedDataUnchanged
                  .failed(error: '$e')
              : t.settingsReset.resetLocalDataThisDeviceOnly.failed(
                  error: '$e',
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
  }
}
