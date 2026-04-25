part of 'sync_settings_page.dart';

extension _SyncSettingsPageSyncActions on _SyncSettingsPageState {
  Future<bool> _persistBackendConfig() async {
    final t = context.t;
    final backendType = _effectiveBackendType;
    final cloudUid = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    final resolvedRemoteRoot = switch (backendType) {
      SyncBackendType.managedVault =>
        cloudUid == null || cloudUid.isEmpty ? '' : cloudUid,
      _ => _requiredTrimmed(_remoteRootController),
    };
    if (resolvedRemoteRoot.isEmpty) {
      _showSnack(
        backendType == SyncBackendType.managedVault
            ? t.sync.cloudManagedVault.signInRequired
            : t.sync.remoteRootRequired,
      );
      return false;
    }

    switch (backendType) {
      case SyncBackendType.webdav:
        final baseUrl = _requiredTrimmed(_baseUrlController);
        if (baseUrl.isEmpty) {
          _showSnack(t.sync.baseUrlRequired);
          return false;
        }
        await _store.writeWebdavPassword(_optionalTrimmed(_passwordController));
        await _store.writeWebdavSyncSettings(
          baseUrl: baseUrl,
          username: _optionalTrimmed(_usernameController),
          remoteRoot: resolvedRemoteRoot,
          autoEnabled: _autoEnabled,
        );
        break;
      case SyncBackendType.localDir:
        final localDir = _requiredTrimmed(_localDirController);
        if (localDir.isEmpty) {
          _showSnack(t.sync.localDirRequired);
          return false;
        }
        await _store.writeLocalDirSyncSettings(
          localDir: localDir,
          remoteRoot: resolvedRemoteRoot,
          autoEnabled: _autoEnabled,
        );
        break;
      case SyncBackendType.managedVault:
        String? managedVaultBaseUrl;
        if (kDebugMode && _showManagedVaultEndpointOverride) {
          managedVaultBaseUrl =
              _requiredTrimmed(_managedVaultBaseUrlController);
          if (managedVaultBaseUrl.isEmpty) {
            _showSnack(t.sync.baseUrlRequired);
            return false;
          }
        } else {
          managedVaultBaseUrl = await _store.readManagedVaultBaseUrl();
        }
        final resolved = managedVaultBaseUrl ??
            (await _store.resolveManagedVaultBaseUrl())?.trim();
        if (resolved == null || resolved.trim().isEmpty) {
          _showSnack(t.sync.baseUrlRequired);
          return false;
        }
        await _store.writeManagedVaultSyncSettings(
          baseUrl: managedVaultBaseUrl,
          remoteRoot: resolvedRemoteRoot,
          autoEnabled: _autoEnabled,
        );
        break;
    }

    return true;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  int? _extractHttpStatusCode(Object error) {
    final message = error.toString();
    final statusText =
        RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message)?.group(1);
    if (statusText == null) return null;
    return int.tryParse(statusText);
  }

  Future<String?> _currentSyncStateScopeId({
    required Uint8List? syncKey,
  }) async {
    final backendType = _effectiveBackendType;
    final cloudUid = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    final remoteRoot = switch (backendType) {
      SyncBackendType.managedVault =>
        cloudUid == null || cloudUid.isEmpty ? '' : cloudUid,
      _ => _requiredTrimmed(_remoteRootController),
    };
    if (remoteRoot.isEmpty) return null;
    final baseUrl = switch (backendType) {
      SyncBackendType.managedVault =>
        (await _store.resolveManagedVaultBaseUrl())?.trim() ?? '',
      _ => _optionalTrimmed(_baseUrlController),
    };
    return _store.syncStateScopeIdForFields(
      backendType: backendType,
      baseUrl: baseUrl,
      localDir: _optionalTrimmed(_localDirController),
      username: _optionalTrimmed(_usernameController),
      remoteRoot: remoteRoot,
      syncKey: syncKey,
    );
  }

  Future<void> _writeLastSyncLog({
    required SyncBackgroundDirection direction,
    required SyncBackgroundResultStatus status,
    required int durationMs,
    required String? scopeId,
    int? statusCode,
    String? errorMessage,
    String? userMessage,
  }) async {
    try {
      await _store.writeBackgroundSyncResult(
        SyncBackgroundResult(
          backendType: _effectiveBackendType,
          direction: direction,
          status: status,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          statusCode: statusCode,
          errorCode: null,
          errorMessage: errorMessage,
          userMessage: userMessage,
          retryCount: null,
          durationMs: durationMs,
        ),
        backendType: _effectiveBackendType,
        scopeId: scopeId,
      );
    } catch (_) {
      // Diagnostics persistence is best-effort and should never block sync UX.
    }
  }

  Future<void> _runConnectionTest() async {
    final backend = AppBackendScope.of(context);
    final remoteRoot = _requiredTrimmed(_remoteRootController);

    switch (_effectiveBackendType) {
      case SyncBackendType.webdav:
        await backend.syncWebdavTestConnection(
          baseUrl: _requiredTrimmed(_baseUrlController),
          username: _optionalTrimmed(_usernameController),
          password: _optionalTrimmed(_passwordController),
          remoteRoot: remoteRoot,
        );
        break;
      case SyncBackendType.localDir:
        await backend.syncLocaldirTestConnection(
          localDir: _requiredTrimmed(_localDirController),
          remoteRoot: remoteRoot,
        );
        break;
      case SyncBackendType.managedVault:
        // Best-effort: managed vault connectivity is verified via push/pull.
        break;
    }
  }

  Future<void> _runSaveSyncWithProgress({
    required Future<void> Function(
      ValueNotifier<String> stage,
      ValueNotifier<double?> progress,
    ) run,
    Key progressKey = _SyncSettingsPageState._kSaveSyncProgressKey,
    Key progressPercentKey =
        _SyncSettingsPageState._kSaveSyncProgressPercentKey,
  }) async {
    final dialogContext = context;
    final t = dialogContext.t;

    final stage = ValueNotifier<String>(t.sync.progressDialog.preparing);
    final progress = ValueNotifier<double?>(0.0);
    Object? runError;
    StackTrace? runErrorStackTrace;

    bool started = false;
    try {
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) {
          if (!started) {
            started = true;
            unawaited(() async {
              try {
                await run(stage, progress);
              } catch (e, st) {
                runError = e;
                runErrorStackTrace = st;
              } finally {
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            }());
          }

          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text(t.sync.progressDialog.title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder(
                    valueListenable: stage,
                    builder: (context, value, _) => Text(value),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<double?>(
                    valueListenable: progress,
                    builder: (context, value, _) {
                      final percentLabel = value == null
                          ? ''
                          : '${(value * 100).floor().clamp(0, 100)}%';
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                key: progressKey,
                                value: value,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 48,
                            child: Text(
                              percentLabel,
                              key: progressPercentKey,
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (runError != null) {
        final error = runError!;
        final stackTrace = runErrorStackTrace;
        if (stackTrace != null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        throw error;
      }
    } finally {
      stage.dispose();
      progress.dispose();
    }
  }

  Future<Uint8List> _deriveManagedVaultSyncKey(AppBackend backend) async {
    final vaultId = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    if (vaultId == null || vaultId.isEmpty) {
      throw StateError('missing_managed_vault_uid');
    }
    final syncKey = await SyncKeyManager.deriveManagedVaultSyncKey(
      vaultId: vaultId,
      deriveSyncKey: backend.deriveSyncKey,
    );
    await SyncKeyManager.save(
      write: _store.writeSyncKey,
      key: syncKey,
    );
    return syncKey;
  }

  Future<Uint8List> _resolveSyncKeyForCurrentBackend(AppBackend backend) async {
    if (_effectiveBackendType != SyncBackendType.managedVault) {
      return _loadOrCreateSyncKey();
    }
    if (_usesCloudSessionModel) {
      return _loadOrCreateSyncKey();
    }
    return _deriveManagedVaultSyncKey(backend);
  }

  Future<void> _restorePrimarySyncConfigSnapshot({
    required AppBackend backend,
    required SyncBackendType backendType,
    required String webdavBaseUrl,
    required String? webdavUsername,
    required String? webdavPassword,
    required String localDir,
    required String? managedVaultBaseUrl,
    required String remoteRoot,
    required bool autoEnabled,
    required Uint8List? syncKey,
    required SyncEngine? engine,
    bool refreshSchedule = true,
  }) async {
    switch (backendType) {
      case SyncBackendType.webdav:
        await _store.writeWebdavPassword(webdavPassword);
        await _store.writeWebdavSyncSettings(
          baseUrl: webdavBaseUrl,
          username: webdavUsername,
          remoteRoot: remoteRoot,
          autoEnabled: autoEnabled,
        );
        break;
      case SyncBackendType.localDir:
        await _store.writeLocalDirSyncSettings(
          localDir: localDir,
          remoteRoot: remoteRoot,
          autoEnabled: autoEnabled,
        );
        break;
      case SyncBackendType.managedVault:
        await _store.writeManagedVaultBaseUrl(managedVaultBaseUrl);
        await _store.writeManagedVaultSyncSettings(
          baseUrl: managedVaultBaseUrl,
          remoteRoot: remoteRoot,
          autoEnabled: autoEnabled,
        );
        break;
    }
    if (syncKey != null) {
      await SyncKeyManager.save(
        write: _store.writeSyncKey,
        key: syncKey,
      );
    } else {
      await _store.clearSyncKey();
    }
    if (backendType != SyncBackendType.managedVault) {
      engine?.writeGate.value = const SyncWriteGateState.open();
    }
    if (refreshSchedule) {
      await _refreshBackgroundScheduleBestEffort(backend);
    }
  }

  Future<void> _refreshBackgroundScheduleBestEffort(AppBackend backend) async {
    try {
      await BackgroundSync.refreshSchedule(
        backend: backend,
        configStore: _store,
      );
    } catch (e) {
      debugPrint(
        'sync settings: failed to refresh background sync schedule: $e',
      );
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
    final engine = SyncEngineScope.maybeOf(context);
    var shouldHideRecoveryHint = false;
    var shouldRestartStoppedEngine = false;
    var engineRestartedAfterStop = false;
    var shouldRefreshBackgroundSchedule = false;
    AppBackend? backgroundScheduleBackend;

    void restartStoppedEngineIfNeeded() {
      if (!shouldRestartStoppedEngine || engineRestartedAfterStop) {
        return;
      }
      engine?.start();
      engineRestartedAfterStop = true;
    }

    try {
      final before = await _store.readAll();
      if (!mounted) return;
      final oldBackendType = switch (before[SyncConfigStore.kBackendType]) {
        'localdir' => SyncBackendType.localDir,
        'managedvault' => SyncBackendType.managedVault,
        _ => SyncBackendType.webdav,
      };
      final oldWebdavBaseUrl =
          (before[SyncConfigStore.kWebdavBaseUrl] ?? '').trim();
      final oldWebdavUsername = before[SyncConfigStore.kWebdavUsername];
      final oldWebdavTargetUsername = oldWebdavUsername?.trim() ?? '';
      final oldWebdavPassword = await _store.readWebdavPassword();
      final oldRemoteRoot = (before[SyncConfigStore.kRemoteRoot] ?? '').trim();
      final oldLocalDir = (before[SyncConfigStore.kLocalDir] ?? '').trim();
      final oldManagedVaultBaseUrl =
          before[SyncConfigStore.kManagedVaultBaseUrl];
      final oldManagedVaultTargetBaseUrl =
          (oldManagedVaultBaseUrl ?? await _store.resolveManagedVaultBaseUrl())
                  ?.trim() ??
              '';
      final oldAutoEnabled = before[SyncConfigStore.kAutoEnabled] == null ||
          before[SyncConfigStore.kAutoEnabled] == '1';
      final previousSyncKey = await _store.readSyncKey();
      if (!mounted) return;

      final backend = AppBackendScope.of(context);
      backgroundScheduleBackend = backend;
      final backendType = _effectiveBackendType;

      final requiresSyncKey = backendType == SyncBackendType.webdav ||
          backendType == SyncBackendType.localDir;
      final passphrase = _optionalTrimmed(_syncPassphraseController);
      final hasNewPassphrase = backendType != SyncBackendType.managedVault &&
          passphrase != null &&
          !_passphraseIsPlaceholder;

      final newBackendType = backendType;
      final newWebdavBaseUrl = _requiredTrimmed(_baseUrlController).trim();
      final newWebdavUsername = _optionalTrimmed(_usernameController) ?? '';
      final newManagedVaultBaseUrl = backendType == SyncBackendType.managedVault
          ? (kDebugMode && _showManagedVaultEndpointOverride
              ? _requiredTrimmed(_managedVaultBaseUrlController).trim()
              : (await _store.resolveManagedVaultBaseUrl())?.trim() ?? '')
          : '';
      if (!mounted) return;
      final newRemoteRoot = switch (backendType) {
        SyncBackendType.managedVault =>
          CloudAuthScope.maybeOf(context)?.controller.uid?.trim() ?? '',
        _ => _requiredTrimmed(_remoteRootController).trim(),
      };
      final newLocalDir = _requiredTrimmed(_localDirController).trim();
      final shouldSync = _shouldRunSaveSyncForConfigChange(
        oldBackendType: oldBackendType,
        oldWebdavBaseUrl: oldWebdavBaseUrl,
        oldWebdavUsername: oldWebdavTargetUsername,
        oldManagedVaultBaseUrl: oldManagedVaultTargetBaseUrl,
        oldRemoteRoot: oldRemoteRoot,
        oldLocalDir: oldLocalDir,
        newBackendType: newBackendType,
        newWebdavBaseUrl: newWebdavBaseUrl,
        newWebdavUsername: newWebdavUsername,
        newManagedVaultBaseUrl: newManagedVaultBaseUrl,
        newRemoteRoot: newRemoteRoot,
        newLocalDir: newLocalDir,
      );
      SyncSwitchDirection? switchDirection;
      if (_shouldPromptSyncDirectionForConfigChange(
        oldBackendType: oldBackendType,
        oldWebdavBaseUrl: oldWebdavBaseUrl,
        oldWebdavUsername: oldWebdavTargetUsername,
        oldManagedVaultBaseUrl: oldManagedVaultTargetBaseUrl,
        oldRemoteRoot: oldRemoteRoot,
        oldLocalDir: oldLocalDir,
        newBackendType: newBackendType,
        newWebdavBaseUrl: newWebdavBaseUrl,
        newWebdavUsername: newWebdavUsername,
        newManagedVaultBaseUrl: newManagedVaultBaseUrl,
        newRemoteRoot: newRemoteRoot,
        newLocalDir: newLocalDir,
      )) {
        _setState(() => _busy = false);
        switchDirection = await showSyncSwitchDirectionDialog(context);
        if (!mounted || switchDirection == null) return;
        _setState(() => _busy = true);
      }

      Uint8List? syncKey;
      if (backendType == SyncBackendType.managedVault) {
        syncKey = _usesCloudSessionModel
            ? await _loadOrCreateSyncKey()
            : await _deriveManagedVaultSyncKey(backend);
        shouldHideRecoveryHint = true;
        _syncPassphraseController.clear();
        _passphraseIsPlaceholder = false;
      } else {
        syncKey = await _loadSyncKey();
      }

      if (hasNewPassphrase) {
        final passphrase = _optionalTrimmed(_syncPassphraseController);
        if (passphrase == null) {
          _showSnack(t.sync.missingSyncKey);
          return;
        }

        Uint8List resolvedSyncKey;
        if (syncKey != null && syncKey.length == 32) {
          resolvedSyncKey = syncKey;
        } else {
          String? existingEnvelopeJson =
              await _store.readRecoveryEnvelopeJson();

          final hasEnvelope = existingEnvelopeJson != null &&
              existingEnvelopeJson.trim().isNotEmpty;
          if (hasEnvelope) {
            try {
              final recovered = await backend.recoverSyncKeyFromEnvelope(
                existingEnvelopeJson,
                passphrase,
              );
              if (recovered.length != 32) {
                _showSnack(
                  t.sync.recoveryHint.recoverFailed(error: 'invalid_sync_key'),
                );
                return;
              }
              resolvedSyncKey = recovered;
            } catch (e) {
              _showSnack(t.sync.recoveryHint.recoverFailed(error: '$e'));
              return;
            }
          } else {
            resolvedSyncKey = await backend.deriveSyncKey(passphrase);
          }
        }

        await SyncKeyManager.save(
          write: _store.writeSyncKey,
          key: resolvedSyncKey,
        );
        try {
          final envelopeJson = await backend.createSyncRecoveryEnvelope(
            resolvedSyncKey,
            passphrase,
          );
          await _store.writeRecoveryEnvelopeJson(envelopeJson);
        } catch (_) {
          // Best-effort: keep legacy deterministic flow working even if
          // recovery envelope generation is unavailable on current backend.
        }
        syncKey = resolvedSyncKey;
        shouldHideRecoveryHint = true;
        _syncPassphraseController.text =
            _SyncSettingsPageState._kPassphrasePlaceholder;
        _passphraseIsPlaceholder = true;
      } else if (requiresSyncKey && (syncKey == null || syncKey.length != 32)) {
        syncKey = await _loadOrCreateSyncKey();
        shouldHideRecoveryHint = true;
        _syncPassphraseController.text =
            _SyncSettingsPageState._kPassphrasePlaceholder;
        _passphraseIsPlaceholder = true;
      }

      final wasEngineRunning = engine?.isRunning ?? false;
      if (shouldSync && engine != null) {
        await engine.stopImmediatelyAndWait(
          timeout: kDestructiveSyncStopTimeout,
        );
        shouldRestartStoppedEngine = wasEngineRunning;
      }

      final persisted = await _persistBackendConfig();
      if (!persisted) {
        restartStoppedEngineIfNeeded();
        return;
      }
      shouldRefreshBackgroundSchedule = true;
      if (!mounted) return;

      try {
        await _runConnectionTest();
        if (!mounted) return;
        _showSnack(t.sync.connectionOk);

        var didSync = false;
        if (shouldSync) {
          final sessionScope =
              context.getInheritedWidgetOfExactType<SessionScope>();
          final sessionKey = sessionScope?.sessionKey;
          if (sessionKey != null &&
              syncKey != null &&
              syncKey.length == 32 &&
              mounted) {
            final activeSyncKey = syncKey;
            switch (newBackendType) {
              case SyncBackendType.webdav:
                await _runWebdavSwitchSyncWithProgress(
                  direction: switchDirection ?? SyncSwitchDirection.merge,
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: activeSyncKey,
                  baseUrl: newWebdavBaseUrl,
                  username: _optionalTrimmed(_usernameController),
                  password: _optionalTrimmed(_passwordController),
                  remoteRoot: newRemoteRoot,
                );
                didSync = true;
                break;
              case SyncBackendType.localDir:
                await _runLocalDirSwitchSyncWithProgress(
                  direction: switchDirection ?? SyncSwitchDirection.merge,
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: activeSyncKey,
                  localDir: newLocalDir,
                  remoteRoot: newRemoteRoot,
                );
                didSync = true;
                break;
              case SyncBackendType.managedVault:
                didSync = await _runManagedVaultSaveSync(
                  backend: backend,
                  sessionKey: sessionKey,
                  syncKey: activeSyncKey,
                  engine: engine,
                  direction: switchDirection ?? SyncSwitchDirection.merge,
                );
                break;
            }
          }
        }

        if (!mounted) return;
        if (!shouldSync || shouldRestartStoppedEngine) {
          restartStoppedEngineIfNeeded();
        }
        if (!(didSync && newBackendType == SyncBackendType.managedVault)) {
          engine?.notifyExternalChange();
        }
        final canScheduleFallbackSync = switchDirection == null ||
            switchDirection == SyncSwitchDirection.merge;
        if (!didSync && canScheduleFallbackSync) {
          engine?.triggerPushNow();
          engine?.triggerPullNow();
        }
      } catch (e) {
        if (!mounted) return;
        final remoteReplaceCommitted = e is SyncRemoteReplaceCommittedException;
        final displayError = remoteReplaceCommitted ? e.cause : e;
        if (remoteReplaceCommitted) {
          shouldRestartStoppedEngine = false;
          await _disableAutoSyncAfterDestructiveCleanup(backend);
        }
        final shouldRestorePrimarySnapshot = !remoteReplaceCommitted &&
            (switchDirection != null ||
                (newBackendType == SyncBackendType.managedVault &&
                    e is _ManagedVaultSaveConfigurationException));
        var restoredPrimarySnapshot = false;
        if (shouldRestorePrimarySnapshot) {
          await _restorePrimarySyncConfigSnapshot(
            backend: backend,
            backendType: oldBackendType,
            webdavBaseUrl: oldWebdavBaseUrl,
            webdavUsername: oldWebdavUsername,
            webdavPassword: oldWebdavPassword,
            localDir: oldLocalDir,
            managedVaultBaseUrl: oldManagedVaultBaseUrl,
            remoteRoot: oldRemoteRoot,
            autoEnabled: oldAutoEnabled,
            syncKey: previousSyncKey,
            engine: engine,
            refreshSchedule: false,
          );
          restoredPrimarySnapshot = true;
          shouldRefreshBackgroundSchedule = true;
        }
        if (shouldRestartStoppedEngine &&
            (switchDirection != SyncSwitchDirection.remoteReplacesLocal ||
                restoredPrimarySnapshot)) {
          restartStoppedEngineIfNeeded();
        }
        if (backendType == SyncBackendType.managedVault) {
          final details = inspectManagedVaultPushFailure(displayError);
          if (details.writeGateState != null &&
              !remoteReplaceCommitted &&
              !restoredPrimarySnapshot) {
            return;
          }
          _showSnack(
            t.sync.connectionFailed(
              error: managedVaultUserFacingErrorMessage(displayError),
            ),
          );
          return;
        }
        _showSnack(t.sync.connectionFailed(error: '$displayError'));
      }
    } catch (e) {
      _showSnack(t.sync.saveFailed(error: '$e'));
    } finally {
      final backend = backgroundScheduleBackend;
      if (shouldRefreshBackgroundSchedule && backend != null) {
        await _refreshBackgroundScheduleBestEffort(backend);
      }
      restartStoppedEngineIfNeeded();
      if (mounted) {
        _setState(() {
          _busy = false;
          if (shouldHideRecoveryHint) {
            _showRecoveryHintBanner = false;
          }
        });
      }
    }
  }

  Future<void> _push() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
    final stopwatch = Stopwatch()..start();
    String? stateScopeId;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final backendType = _effectiveBackendType;
      final engine = SyncEngineScope.maybeOf(context);

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final syncKey = await _resolveSyncKeyForCurrentBackend(backend);
      stateScopeId = await _currentSyncStateScopeId(syncKey: syncKey);

      var pushed = 0;
      var pulled = 0;
      var recoveredOnly = false;
      var refreshedLocalState = false;
      String? recoveredMessage;
      await _runSaveSyncWithProgress(
        progressKey: _SyncSettingsPageState._kManualSyncProgressKey,
        progressPercentKey:
            _SyncSettingsPageState._kManualSyncProgressPercentKey,
        run: (stage, progress) async {
          final hasTotal = ValueNotifier(false);
          var runCompleted = false;
          stage.value = t.sync.progressDialog.pushing;
          progress.value = 0.0;
          unawaited(() async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (runCompleted) return;
            if (hasTotal.value) return;
            if (progress.value != 0.0) return;
            progress.value = null;
          }());

          try {
            if (backendType == SyncBackendType.managedVault) {
              final result = await _runManagedVaultManualPushWithProgress(
                backend: backend,
                sessionKey: sessionKey,
                syncKey: syncKey,
                engine: engine,
                stage: stage,
                progress: progress,
                hasTotal: hasTotal,
              );
              pushed = result.pushed;
              pulled = result.pulled;
              recoveredOnly = result.recoveredOnly;
              recoveredMessage = result.recoveredMessage;
              refreshedLocalState = result.refreshedLocalState;
            } else {
              final progressReporter = _makeSmoothStageProgressReporter(
                progress,
                onHasTotal: () => hasTotal.value = true,
              );
              pushed = await (switch (backendType) {
                SyncBackendType.webdav => _consumeRustProgressStream(
                    backend.syncWebdavPushOpsOnlyProgress(
                      sessionKey,
                      syncKey,
                      baseUrl: _requiredTrimmed(_baseUrlController),
                      username: _optionalTrimmed(_usernameController),
                      password: _optionalTrimmed(_passwordController),
                      remoteRoot: _requiredTrimmed(_remoteRootController),
                    ),
                    onProgress: progressReporter.onProgress,
                  ),
                SyncBackendType.localDir => _consumeRustProgressStream(
                    backend.syncLocaldirPushProgress(
                      sessionKey,
                      syncKey,
                      localDir: _requiredTrimmed(_localDirController),
                      remoteRoot: _requiredTrimmed(_remoteRootController),
                    ),
                    onProgress: progressReporter.onProgress,
                  ),
                SyncBackendType.managedVault => throw UnimplementedError(),
              });
              stage.value = t.sync.progressDialog.finalizing;
              progressReporter.complete();
            }
          } finally {
            runCompleted = true;
          }
        },
      );
      final successMessage = recoveredOnly
          ? [
              recoveredMessage ?? t.sync.cloudManagedVault.serverUnavailable,
              pulled == 0
                  ? t.sync.noNewChanges
                  : t.sync.pulledOps(count: pulled),
            ].join(' ')
          : t.sync.pushedOps(count: pushed);
      await _writeLastSyncLog(
        direction: SyncBackgroundDirection.push,
        status: recoveredOnly
            ? SyncBackgroundResultStatus.skipped
            : SyncBackgroundResultStatus.success,
        durationMs: stopwatch.elapsedMilliseconds,
        scopeId: stateScopeId,
        userMessage: successMessage,
      );
      if (mounted && refreshedLocalState) {
        engine?.notifyExternalChange();
      }
      _showSnack(successMessage);
    } catch (e) {
      final errorMessage = managedVaultUserFacingErrorMessage(e);
      final failedMessage = t.sync.pushFailed(error: errorMessage);
      await _writeLastSyncLog(
        direction: SyncBackgroundDirection.push,
        status: SyncBackgroundResultStatus.failure,
        durationMs: stopwatch.elapsedMilliseconds,
        scopeId: stateScopeId,
        statusCode: _extractHttpStatusCode(e),
        errorMessage: errorMessage,
        userMessage: failedMessage,
      );
      _showSnack(failedMessage);
    } finally {
      if (mounted) {
        _setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _pull() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
    final stopwatch = Stopwatch()..start();
    final engine = SyncEngineScope.maybeOf(context);
    String? stateScopeId;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;
      final backendType = _effectiveBackendType;

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final syncKey = await _resolveSyncKeyForCurrentBackend(backend);
      stateScopeId = await _currentSyncStateScopeId(syncKey: syncKey);

      var pulled = 0;
      await _runSaveSyncWithProgress(
        progressKey: _SyncSettingsPageState._kManualSyncProgressKey,
        progressPercentKey:
            _SyncSettingsPageState._kManualSyncProgressPercentKey,
        run: (stage, progress) async {
          var hasTotal = false;
          var runCompleted = false;
          final progressReporter = _makeSmoothStageProgressReporter(
            progress,
            onHasTotal: () => hasTotal = true,
          );
          stage.value = t.sync.progressDialog.pulling;
          progress.value = 0.0;
          unawaited(() async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (runCompleted) return;
            if (hasTotal) return;
            if (progress.value != 0.0) return;
            progress.value = null;
          }());

          try {
            pulled = await (switch (backendType) {
              SyncBackendType.webdav => _consumeRustProgressStream(
                  backend.syncWebdavPullProgress(
                    sessionKey,
                    syncKey,
                    baseUrl: _requiredTrimmed(_baseUrlController),
                    username: _optionalTrimmed(_usernameController),
                    password: _optionalTrimmed(_passwordController),
                    remoteRoot: _requiredTrimmed(_remoteRootController),
                  ),
                  onProgress: progressReporter.onProgress,
                ),
              SyncBackendType.localDir => _consumeRustProgressStream(
                  backend.syncLocaldirPullProgress(
                    sessionKey,
                    syncKey,
                    localDir: _requiredTrimmed(_localDirController),
                    remoteRoot: _requiredTrimmed(_remoteRootController),
                  ),
                  onProgress: progressReporter.onProgress,
                ),
              SyncBackendType.managedVault => () async {
                  final cloudAuth = CloudAuthScope.of(context).controller;
                  final idToken = await readCloudAuthIdToken(
                    cloudAuth,
                    mode: CloudAuthAccessMode.interactive,
                  );
                  if (idToken == null || idToken.trim().isEmpty) {
                    throw StateError('missing_id_token');
                  }
                  final vaultId = cloudAuth.uid ?? '';
                  final baseUrl = await _store.resolveManagedVaultBaseUrl();
                  if (baseUrl == null || baseUrl.trim().isEmpty) {
                    throw StateError('missing_managed_vault_base_url');
                  }
                  return _consumeRustProgressStream(
                    backend.syncManagedVaultPullProgress(
                      sessionKey,
                      syncKey,
                      baseUrl: baseUrl,
                      vaultId: vaultId,
                      idToken: idToken,
                    ),
                    onProgress: progressReporter.onProgress,
                  );
                }(),
            });
            stage.value = t.sync.progressDialog.finalizing;
            progressReporter.complete();
          } finally {
            runCompleted = true;
          }
        },
      );
      if (mounted) engine?.notifyExternalChange();
      final successMessage =
          pulled == 0 ? t.sync.noNewChanges : t.sync.pulledOps(count: pulled);
      await _writeLastSyncLog(
        direction: SyncBackgroundDirection.pull,
        status: SyncBackgroundResultStatus.success,
        durationMs: stopwatch.elapsedMilliseconds,
        scopeId: stateScopeId,
        userMessage: successMessage,
      );
      _showSnack(successMessage);
    } catch (e) {
      if (_effectiveBackendType == SyncBackendType.managedVault) {
        final statusCode = _extractHttpStatusCode(e);
        if (statusCode == 402) {
          if (engine != null) {
            engine.writeGate.value = const SyncWriteGateState.paymentRequired();
          }
        }
      }
      final errorMessage = '$e';
      final failedMessage = t.sync.pullFailed(error: errorMessage);
      await _writeLastSyncLog(
        direction: SyncBackgroundDirection.pull,
        status: SyncBackgroundResultStatus.failure,
        durationMs: stopwatch.elapsedMilliseconds,
        scopeId: stateScopeId,
        statusCode: _extractHttpStatusCode(e),
        errorMessage: errorMessage,
        userMessage: failedMessage,
      );
      _showSnack(failedMessage);
    } finally {
      if (mounted) {
        _setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }
}
