part of 'sync_settings_page.dart';

extension _SyncSettingsPageSyncActions on _SyncSettingsPageState {
  Future<int> _consumeRustProgressStream(
    Stream<String> stream, {
    required void Function(int done, int total) onProgress,
  }) async {
    var count = 0;
    await for (final msg in stream) {
      Map<String, dynamic>? ev;
      try {
        final decoded = jsonDecode(msg);
        ev = decoded is Map ? decoded.cast<String, dynamic>() : null;
      } catch (_) {
        ev = null;
      }
      if (ev == null) continue;

      final type = ev['type'];
      if (type == 'progress') {
        final done = (ev['done'] as num?)?.toInt();
        final total = (ev['total'] as num?)?.toInt();
        if (done != null && total != null) {
          onProgress(done, total);
        }
      } else if (type == 'result') {
        final v = (ev['count'] as num?)?.toInt();
        if (v != null) count = v;
      }
    }
    return count;
  }

  Future<bool> _persistBackendConfig() async {
    final t = context.t;
    final cloudUid = CloudAuthScope.maybeOf(context)?.controller.uid?.trim();
    final resolvedRemoteRoot = switch (_backendType) {
      SyncBackendType.managedVault =>
        cloudUid == null || cloudUid.isEmpty ? '' : cloudUid,
      _ => _requiredTrimmed(_remoteRootController),
    };
    if (resolvedRemoteRoot.isEmpty) {
      _showSnack(
        _backendType == SyncBackendType.managedVault
            ? t.sync.cloudManagedVault.signInRequired
            : t.sync.remoteRootRequired,
      );
      return false;
    }

    await _store.writeBackendType(_backendType);
    await _store.writeAutoEnabled(_autoEnabled);
    await _store.writeRemoteRoot(resolvedRemoteRoot);

    switch (_backendType) {
      case SyncBackendType.webdav:
        final baseUrl = _requiredTrimmed(_baseUrlController);
        if (baseUrl.isEmpty) {
          _showSnack(t.sync.baseUrlRequired);
          return false;
        }
        await _store.writeWebdavBaseUrl(baseUrl);
        await _store.writeWebdavUsername(_optionalTrimmed(_usernameController));
        await _store.writeWebdavPassword(_optionalTrimmed(_passwordController));
        break;
      case SyncBackendType.localDir:
        final localDir = _requiredTrimmed(_localDirController);
        if (localDir.isEmpty) {
          _showSnack(t.sync.localDirRequired);
          return false;
        }
        await _store.writeLocalDir(localDir);
        break;
      case SyncBackendType.managedVault:
        if (kDebugMode && _showManagedVaultEndpointOverride) {
          await _store.writeManagedVaultBaseUrl(
              _requiredTrimmed(_managedVaultBaseUrlController));
        }
        final resolved = await _store.resolveManagedVaultBaseUrl();
        if (resolved == null || resolved.trim().isEmpty) {
          _showSnack(t.sync.baseUrlRequired);
          return false;
        }
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

  Future<void> _runConnectionTest() async {
    final backend = AppBackendScope.of(context);
    final remoteRoot = _requiredTrimmed(_remoteRootController);

    switch (_backendType) {
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
  }) async {
    final dialogContext = context;
    final t = dialogContext.t;

    final stage = ValueNotifier<String>(t.sync.progressDialog.preparing);
    final progress = ValueNotifier<double?>(0.0);

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
              } catch (_) {
                // Best-effort: sync errors should not block the user.
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
                      final percent =
                          ((value ?? 0) * 100).floor().clamp(0, 100).toString();
                      final percentLabel = '$percent%';
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                key: _SyncSettingsPageState
                                    ._kSaveSyncProgressKey,
                                value: value,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 48,
                            child: Text(
                              percentLabel,
                              key: _SyncSettingsPageState
                                  ._kSaveSyncProgressPercentKey,
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
    } finally {
      stage.dispose();
      progress.dispose();
    }
  }

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
      // Specifically requested: switching from WebDAV/local-dir to Cloud should
      // trigger an immediate sync.
      return oldBackendType != SyncBackendType.managedVault;
    }
    return false;
  }

  Future<void> _save() async {
    if (_busy) return;
    _setState(() => _busy = true);

    final t = context.t;
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
      final oldRemoteRoot = (before[SyncConfigStore.kRemoteRoot] ?? '').trim();
      final oldLocalDir = (before[SyncConfigStore.kLocalDir] ?? '').trim();

      final backend = AppBackendScope.of(context);

      final requiresSyncKey = _backendType == SyncBackendType.webdav ||
          _backendType == SyncBackendType.managedVault ||
          _backendType == SyncBackendType.localDir;
      final passphrase = _optionalTrimmed(_syncPassphraseController);
      final hasNewPassphrase = passphrase != null && !_passphraseIsPlaceholder;
      if (requiresSyncKey && !hasNewPassphrase) {
        final existing = await _loadSyncKey();
        if (existing == null || existing.length != 32) {
          _showSnack(t.sync.missingSyncKey);
          return;
        }
      }

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      if (hasNewPassphrase) {
        final passphrase = _optionalTrimmed(_syncPassphraseController);
        if (passphrase == null) {
          _showSnack(t.sync.missingSyncKey);
          return;
        }
        final derived = await backend.deriveSyncKey(passphrase);
        await _store.writeSyncKey(derived);
        _syncPassphraseController.text =
            _SyncSettingsPageState._kPassphrasePlaceholder;
        _passphraseIsPlaceholder = true;
      }

      unawaited(BackgroundSync.refreshSchedule(
          backend: backend, configStore: _store));

      try {
        await _runConnectionTest();
        if (!mounted) return;
        _showSnack(t.sync.connectionOk);

        final newBackendType = _backendType;
        final newWebdavBaseUrl = _requiredTrimmed(_baseUrlController).trim();
        final newRemoteRoot = _requiredTrimmed(_remoteRootController).trim();
        final newLocalDir = _requiredTrimmed(_localDirController).trim();

        final shouldSync = _shouldRunSaveSyncForConfigChange(
          oldBackendType: oldBackendType,
          oldWebdavBaseUrl: oldWebdavBaseUrl,
          oldRemoteRoot: oldRemoteRoot,
          oldLocalDir: oldLocalDir,
          newBackendType: newBackendType,
          newWebdavBaseUrl: newWebdavBaseUrl,
          newRemoteRoot: newRemoteRoot,
          newLocalDir: newLocalDir,
        );

        var didSync = false;
        if (shouldSync) {
          final sessionScope =
              context.getInheritedWidgetOfExactType<SessionScope>();
          final sessionKey = sessionScope?.sessionKey;
          final syncKey = await _loadSyncKey();
          if (sessionKey != null &&
              syncKey != null &&
              syncKey.length == 32 &&
              mounted) {
            switch (newBackendType) {
              case SyncBackendType.webdav:
                await _runSaveSyncWithProgress(
                  run: (stage, progress) async {
                    stage.value = t.sync.progressDialog.pulling;
                    progress.value = 0.0;
                    await _consumeRustProgressStream(
                      backend.syncWebdavPullProgress(
                        sessionKey,
                        syncKey,
                        baseUrl: newWebdavBaseUrl,
                        username: _optionalTrimmed(_usernameController),
                        password: _optionalTrimmed(_passwordController),
                        remoteRoot: newRemoteRoot,
                      ),
                      onProgress: (done, total) {
                        progress.value =
                            total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                      },
                    );

                    stage.value = t.sync.progressDialog.pushing;
                    progress.value = 0.0;
                    await _consumeRustProgressStream(
                      backend.syncWebdavPushOpsOnlyProgress(
                        sessionKey,
                        syncKey,
                        baseUrl: newWebdavBaseUrl,
                        username: _optionalTrimmed(_usernameController),
                        password: _optionalTrimmed(_passwordController),
                        remoteRoot: newRemoteRoot,
                      ),
                      onProgress: (done, total) {
                        progress.value =
                            total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                      },
                    );

                    if (_cloudMediaBackupEnabled) {
                      stage.value = t.sync.progressDialog.uploadingMedia;
                      progress.value = null;

                      final runner = CloudMediaBackupRunner(
                        store: BackendCloudMediaBackupStore(
                          backend: backend,
                          sessionKey: sessionKey,
                        ),
                        client: WebDavCloudMediaBackupClient(
                          backend: backend,
                          sessionKey: sessionKey,
                          syncKey: syncKey,
                          baseUrl: newWebdavBaseUrl,
                          username: _optionalTrimmed(_usernameController),
                          password: _optionalTrimmed(_passwordController),
                          remoteRoot: newRemoteRoot,
                        ),
                        settings: CloudMediaBackupRunnerSettings(
                          enabled: true,
                          wifiOnly: _cloudMediaBackupWifiOnly,
                        ),
                        getNetwork:
                            ConnectivityCloudMediaBackupNetworkProvider().call,
                      );
                      final result = await runner.runOnce(
                        allowCellular: false,
                        onBytesProgress: (doneBytes, totalBytes) {
                          progress.value = totalBytes <= 0
                              ? 1.0
                              : (doneBytes / totalBytes).clamp(0.0, 1.0);
                        },
                      );
                      if (result.needsCellularConfirmation) {
                        progress.value = 1.0;
                      }
                    }

                    stage.value = t.sync.progressDialog.finalizing;
                    progress.value = 1.0;
                  },
                );
                didSync = true;
                break;
              case SyncBackendType.localDir:
                await _runSaveSyncWithProgress(
                  run: (stage, progress) async {
                    stage.value = t.sync.progressDialog.pulling;
                    progress.value = 0.0;
                    await _consumeRustProgressStream(
                      backend.syncLocaldirPullProgress(
                        sessionKey,
                        syncKey,
                        localDir: newLocalDir,
                        remoteRoot: newRemoteRoot,
                      ),
                      onProgress: (done, total) {
                        progress.value =
                            total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                      },
                    );

                    stage.value = t.sync.progressDialog.pushing;
                    progress.value = 0.0;
                    await _consumeRustProgressStream(
                      backend.syncLocaldirPushProgress(
                        sessionKey,
                        syncKey,
                        localDir: newLocalDir,
                        remoteRoot: newRemoteRoot,
                      ),
                      onProgress: (done, total) {
                        progress.value =
                            total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                      },
                    );

                    stage.value = t.sync.progressDialog.finalizing;
                    progress.value = 1.0;
                  },
                );
                didSync = true;
                break;
              case SyncBackendType.managedVault:
                final cloudAuth = CloudAuthScope.maybeOf(context)?.controller;
                String? idToken;
                try {
                  idToken = await cloudAuth?.getIdToken();
                } catch (_) {
                  idToken = null;
                }
                final vaultId = cloudAuth?.uid?.trim();
                final baseUrl = await _store.resolveManagedVaultBaseUrl();

                if (!mounted) break;
                if (idToken == null ||
                    idToken.trim().isEmpty ||
                    vaultId == null ||
                    vaultId.isEmpty ||
                    baseUrl == null ||
                    baseUrl.trim().isEmpty) {
                  // If we can't get auth details, fall back to engine scheduling.
                  break;
                }

                final baseUrlTrimmed = baseUrl.trim();
                final idTokenTrimmed = idToken.trim();

                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, true);
                try {
                  await _runSaveSyncWithProgress(
                    run: (stage, progress) async {
                      stage.value = t.sync.progressDialog.pulling;
                      progress.value = 0.0;
                      await _consumeRustProgressStream(
                        backend.syncManagedVaultPullProgress(
                          sessionKey,
                          syncKey,
                          baseUrl: baseUrlTrimmed,
                          vaultId: vaultId,
                          idToken: idTokenTrimmed,
                        ),
                        onProgress: (done, total) {
                          progress.value =
                              total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                        },
                      );

                      stage.value = t.sync.progressDialog.pushing;
                      progress.value = 0.0;
                      await _consumeRustProgressStream(
                        backend.syncManagedVaultPushOpsOnlyProgress(
                          sessionKey,
                          syncKey,
                          baseUrl: baseUrlTrimmed,
                          vaultId: vaultId,
                          idToken: idTokenTrimmed,
                        ),
                        onProgress: (done, total) {
                          progress.value =
                              total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
                        },
                      );

                      if (_cloudMediaBackupEnabled) {
                        stage.value = t.sync.progressDialog.uploadingMedia;
                        progress.value = null;

                        final runner = CloudMediaBackupRunner(
                          store: BackendCloudMediaBackupStore(
                            backend: backend,
                            sessionKey: sessionKey,
                          ),
                          client: ManagedVaultCloudMediaBackupClient(
                            backend: backend,
                            sessionKey: sessionKey,
                            syncKey: syncKey,
                            baseUrl: baseUrlTrimmed,
                            vaultId: vaultId,
                            idToken: idTokenTrimmed,
                          ),
                          settings: CloudMediaBackupRunnerSettings(
                            enabled: true,
                            wifiOnly: _cloudMediaBackupWifiOnly,
                          ),
                          getNetwork:
                              ConnectivityCloudMediaBackupNetworkProvider()
                                  .call,
                        );
                        final result = await runner.runOnce(
                          allowCellular: false,
                          onBytesProgress: (doneBytes, totalBytes) {
                            progress.value = totalBytes <= 0
                                ? 1.0
                                : (doneBytes / totalBytes).clamp(0.0, 1.0);
                          },
                        );
                        if (result.needsCellularConfirmation) {
                          progress.value = 1.0;
                        }
                      }

                      stage.value = t.sync.progressDialog.finalizing;
                      progress.value = 1.0;
                    },
                  );
                  didSync = true;
                } finally {
                  await prefs.setBool(cloudSyncSwitchInProgressPrefsKey, false);
                }
                break;
            }
          }
        }

        if (!mounted) return;
        final engine = SyncEngineScope.maybeOf(context);
        engine?.start();
        engine?.notifyExternalChange();
        if (!didSync) {
          engine?.triggerPullNow();
          engine?.triggerPushNow();
        }
      } catch (e) {
        if (!mounted) return;
        _showSnack(t.sync.connectionFailed(error: '$e'));
      }
    } catch (e) {
      _showSnack(t.sync.saveFailed(error: '$e'));
    } finally {
      if (mounted) _setState(() => _busy = false);
    }
  }

  void _scheduleManualSyncIndeterminateFallback() {
    final startedAction = _manualSyncAction;
    if (startedAction == null) return;

    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (_manualSyncAction != startedAction) return;
      if (_manualSyncHasTotal) return;
      if (_manualSyncProgress != 0.0) return;
      _setState(() => _manualSyncProgress = null);
    }());
  }

  Future<void> _push() async {
    if (_busy) return;
    _setState(() {
      _busy = true;
      _manualSyncAction = _ManualSyncAction.push;
      _manualSyncHasTotal = false;
      _manualSyncProgress = 0.0;
    });
    _scheduleManualSyncIndeterminateFallback();

    final t = context.t;
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final syncKey = await _loadSyncKey();
      if (syncKey == null || syncKey.length != 32) {
        _showSnack(t.sync.missingSyncKey);
        return;
      }

      final pushed = await (switch (_backendType) {
        SyncBackendType.webdav => _consumeRustProgressStream(
            backend.syncWebdavPushOpsOnlyProgress(
              sessionKey,
              syncKey,
              baseUrl: _requiredTrimmed(_baseUrlController),
              username: _optionalTrimmed(_usernameController),
              password: _optionalTrimmed(_passwordController),
              remoteRoot: _requiredTrimmed(_remoteRootController),
            ),
            onProgress: (done, total) {
              if (!mounted) return;
              if (total <= 0) return;
              _setState(() {
                _manualSyncHasTotal = true;
                _manualSyncProgress = (done / total).clamp(0.0, 1.0);
              });
            },
          ),
        SyncBackendType.localDir => _consumeRustProgressStream(
            backend.syncLocaldirPushProgress(
              sessionKey,
              syncKey,
              localDir: _requiredTrimmed(_localDirController),
              remoteRoot: _requiredTrimmed(_remoteRootController),
            ),
            onProgress: (done, total) {
              if (!mounted) return;
              if (total <= 0) return;
              _setState(() {
                _manualSyncHasTotal = true;
                _manualSyncProgress = (done / total).clamp(0.0, 1.0);
              });
            },
          ),
        SyncBackendType.managedVault => () async {
            final cloudAuth = CloudAuthScope.of(context).controller;
            final idToken = await cloudAuth.getIdToken();
            if (idToken == null || idToken.trim().isEmpty) {
              throw StateError('missing_id_token');
            }
            final vaultId = cloudAuth.uid ?? '';
            final baseUrl = await _store.resolveManagedVaultBaseUrl();
            if (baseUrl == null || baseUrl.trim().isEmpty) {
              throw StateError('missing_managed_vault_base_url');
            }
            return _consumeRustProgressStream(
              backend.syncManagedVaultPushOpsOnlyProgress(
                sessionKey,
                syncKey,
                baseUrl: baseUrl,
                vaultId: vaultId,
                idToken: idToken,
              ),
              onProgress: (done, total) {
                if (!mounted) return;
                if (total <= 0) return;
                _setState(() {
                  _manualSyncHasTotal = true;
                  _manualSyncProgress = (done / total).clamp(0.0, 1.0);
                });
              },
            );
          }(),
      });
      _showSnack(t.sync.pushedOps(count: pushed));
    } catch (e) {
      _showSnack(t.sync.pushFailed(error: '$e'));
    } finally {
      if (mounted) {
        _setState(() {
          _busy = false;
          _manualSyncAction = null;
          _manualSyncHasTotal = false;
          _manualSyncProgress = null;
        });
      } else {
        _busy = false;
        _manualSyncAction = null;
        _manualSyncHasTotal = false;
        _manualSyncProgress = null;
      }
    }
  }

  Future<void> _pull() async {
    if (_busy) return;
    _setState(() {
      _busy = true;
      _manualSyncAction = _ManualSyncAction.pull;
      _manualSyncHasTotal = false;
      _manualSyncProgress = 0.0;
    });
    _scheduleManualSyncIndeterminateFallback();

    final t = context.t;
    final engine = SyncEngineScope.maybeOf(context);
    try {
      final backend = AppBackendScope.of(context);
      final sessionKey = SessionScope.of(context).sessionKey;

      final persisted = await _persistBackendConfig();
      if (!persisted) return;

      final syncKey = await _loadSyncKey();
      if (syncKey == null || syncKey.length != 32) {
        _showSnack(t.sync.missingSyncKey);
        return;
      }

      final pulled = await (switch (_backendType) {
        SyncBackendType.webdav => _consumeRustProgressStream(
            backend.syncWebdavPullProgress(
              sessionKey,
              syncKey,
              baseUrl: _requiredTrimmed(_baseUrlController),
              username: _optionalTrimmed(_usernameController),
              password: _optionalTrimmed(_passwordController),
              remoteRoot: _requiredTrimmed(_remoteRootController),
            ),
            onProgress: (done, total) {
              if (!mounted) return;
              if (total <= 0) return;
              _setState(() {
                _manualSyncHasTotal = true;
                _manualSyncProgress = (done / total).clamp(0.0, 1.0);
              });
            },
          ),
        SyncBackendType.localDir => _consumeRustProgressStream(
            backend.syncLocaldirPullProgress(
              sessionKey,
              syncKey,
              localDir: _requiredTrimmed(_localDirController),
              remoteRoot: _requiredTrimmed(_remoteRootController),
            ),
            onProgress: (done, total) {
              if (!mounted) return;
              if (total <= 0) return;
              _setState(() {
                _manualSyncHasTotal = true;
                _manualSyncProgress = (done / total).clamp(0.0, 1.0);
              });
            },
          ),
        SyncBackendType.managedVault => () async {
            final cloudAuth = CloudAuthScope.of(context).controller;
            final idToken = await cloudAuth.getIdToken();
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
              onProgress: (done, total) {
                if (!mounted) return;
                if (total <= 0) return;
                _setState(() {
                  _manualSyncHasTotal = true;
                  _manualSyncProgress = (done / total).clamp(0.0, 1.0);
                });
              },
            );
          }(),
      });
      if (mounted) engine?.notifyExternalChange();
      _showSnack(
        pulled == 0 ? t.sync.noNewChanges : t.sync.pulledOps(count: pulled),
      );
    } catch (e) {
      if (_backendType == SyncBackendType.managedVault) {
        final message = e.toString();
        final status =
            RegExp(r'\\bHTTP\\s+(\\d{3})\\b').firstMatch(message)?.group(1);
        if (status == '402') {
          if (engine != null) {
            engine.writeGate.value = const SyncWriteGateState.paymentRequired();
          }
        }
      }
      _showSnack(t.sync.pullFailed(error: '$e'));
    } finally {
      if (mounted) {
        _setState(() {
          _busy = false;
          _manualSyncAction = null;
          _manualSyncHasTotal = false;
          _manualSyncProgress = null;
        });
      } else {
        _busy = false;
        _manualSyncAction = null;
        _manualSyncHasTotal = false;
        _manualSyncProgress = null;
      }
    }
  }
}
