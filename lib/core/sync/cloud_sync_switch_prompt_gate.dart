import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../cloud/cloud_auth_access.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../platform/app_platform_capability_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../features/media_backup/cloud_media_backup_runner.dart';
import '../../features/settings/ai_settings_page.dart';
import 'cloud_sync_switch_prefs.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';
import 'sync_engine_gate.dart';
import 'background_sync.dart';
import 'sync_key_manager.dart';
import 'sync_http_error.dart';
import 'managed_vault_sync_helpers.dart';
import 'sync_switch_direction.dart';
import 'sync_switch_direction_dialog.dart';
import 'vault_replace_local_guard.dart';

part 'cloud_sync_switch_prompt_gate_key.dart';
part 'cloud_sync_switch_prompt_gate_messages.dart';
part 'cloud_sync_switch_prompt_gate_prompts.dart';
part 'cloud_sync_switch_prompt_gate_restore.dart';

final class CloudSyncSwitchPromptGate extends StatefulWidget {
  const CloudSyncSwitchPromptGate({
    required this.child,
    super.key,
    this.configStore,
    this.navigatorKey,
  });

  final Widget child;
  final SyncConfigStore? configStore;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<CloudSyncSwitchPromptGate> createState() =>
      _CloudSyncSwitchPromptGateState();
}

final class _CloudSyncSwitchPromptGateState
    extends State<CloudSyncSwitchPromptGate> {
  SubscriptionStatusController? _subscriptionController;
  SubscriptionStatus _lastStatus = SubscriptionStatus.unknown;
  CloudAuthController? _cloudAuthController;
  Listenable? _cloudAuthListenable;
  String? _lastUid;
  bool _promptedForUid = false;
  bool _dialogShowing = false;
  bool _promptScheduled = false;
  bool _aiGuidePromptScheduled = false;

  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();
  static const _kCloudAiFeatureGuidePromptedUidPrefsKey =
      'cloud_ai_feature_guide_prompted_uid_v1';

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  ManagedVaultPushFailureDetails _applyManagedVaultPushFailure(
    Object error, {
    required SyncEngine? engine,
  }) {
    final details = inspectManagedVaultPushFailure(error);
    final gate = details.writeGateState;
    if (gate != null) {
      engine?.writeGate.value = gate;
    }
    return details;
  }

  Future<void> _runManagedVaultPullStageWithProgress({
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required ValueNotifier<String> stage,
    required ValueNotifier<double> progress,
  }) async {
    final t = context.t;
    final stageProgress = makeManagedVaultStageProgressReporter(progress);
    stage.value = t.sync.progressDialog.pulling;
    progress.value = 0.0;
    await consumeRustProgressStream(
      backend.syncManagedVaultPullProgress(
        sessionKey,
        syncKey,
        baseUrl: baseUrl,
        vaultId: vaultId,
        idToken: idToken,
      ),
      onProgress: stageProgress.onProgress,
    );
    stageProgress.complete();
  }

  Future<void> _clearManagedVaultBackgroundSyncBlockers({
    required String baseUrl,
    required String vaultId,
    required Uint8List syncKey,
  }) async {
    final scopeId = _store.syncStateScopeIdForFields(
      backendType: SyncBackendType.managedVault,
      baseUrl: baseUrl,
      remoteRoot: vaultId,
      syncKey: syncKey,
    );
    await _store.writeBackgroundSyncRepairRequired(
      false,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
    await _store.writeBackgroundSyncBackoffState(
      null,
      backendType: SyncBackendType.managedVault,
      scopeId: scopeId,
    );
  }

  Future<void> _persistManagedVaultBackgroundRepairBlock(
    Object error, {
    required String baseUrl,
    required String vaultId,
    required Uint8List syncKey,
  }) async {
    if (!shouldPersistManagedVaultBackgroundRepairBlock(error)) {
      return;
    }
    await _store.writeBackgroundSyncRepairRequired(
      true,
      backendType: SyncBackendType.managedVault,
      scopeId: _store.syncStateScopeIdForFields(
        backendType: SyncBackendType.managedVault,
        baseUrl: baseUrl,
        remoteRoot: vaultId,
        syncKey: syncKey,
      ),
    );
  }

  Future<
      ({
        ManagedVaultPushFailureRecoveryAction recoveryAction,
        String? failureMessage,
      })> _runManagedVaultPushStageWithProgress({
    required SyncEngine? engine,
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required ValueNotifier<String> stage,
    required ValueNotifier<double> progress,
    required bool allowRecovery,
  }) async {
    final t = context.t;
    final materialLocalizations = MaterialLocalizations.of(context);
    final stageProgress = makeManagedVaultStageProgressReporter(progress);
    stage.value = t.sync.progressDialog.pushing;
    progress.value = 0.0;
    try {
      await consumeRustProgressStream(
        backend.syncManagedVaultPushProgress(
          sessionKey,
          syncKey,
          baseUrl: baseUrl,
          vaultId: vaultId,
          idToken: idToken,
        ),
        onProgress: stageProgress.onProgress,
      );
      stageProgress.complete();
      await _clearManagedVaultBackgroundSyncBlockers(
        baseUrl: baseUrl,
        vaultId: vaultId,
        syncKey: syncKey,
      );
      reopenManagedVaultWriteGateOnSuccess(engine);
      return (
        recoveryAction: ManagedVaultPushFailureRecoveryAction.none,
        failureMessage: null,
      );
    } catch (error) {
      final details = _applyManagedVaultPushFailure(error, engine: engine);
      await _persistManagedVaultBackgroundRepairBlock(
        error,
        baseUrl: baseUrl,
        vaultId: vaultId,
        syncKey: syncKey,
      );
      if (!allowRecovery ||
          details.recoveryAction ==
              ManagedVaultPushFailureRecoveryAction.none) {
        rethrow;
      }
      return (
        recoveryAction: details.recoveryAction,
        failureMessage: details.writeGateState == null
            ? null
            : _managedVaultRecoveredMessageForGate(
                t,
                materialLocalizations,
                details.writeGateState!,
              ),
      );
    }
  }

  @override
  void dispose() {
    _subscriptionController?.removeListener(_onSubscriptionChanged);
    _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final controller = SubscriptionScope.maybeOf(context);
    if (!identical(controller, _subscriptionController)) {
      _subscriptionController?.removeListener(_onSubscriptionChanged);
      _subscriptionController = controller;
      _lastStatus = controller?.status ?? SubscriptionStatus.unknown;
      _subscriptionController?.addListener(_onSubscriptionChanged);
    }

    final cloudAuthController = CloudAuthScope.maybeOf(context)?.controller;
    if (!identical(cloudAuthController, _cloudAuthController)) {
      _cloudAuthListenable?.removeListener(_onCloudAuthChanged);
      _cloudAuthController = cloudAuthController;

      final listenable = cloudAuthController is Listenable
          ? cloudAuthController as Listenable
          : null;
      _cloudAuthListenable = listenable;
      listenable?.addListener(_onCloudAuthChanged);

      _lastUid = cloudAuthController?.uid;
      _promptedForUid = false;
    }

    // Handle cases where the subscription is already entitled by the time this
    // gate becomes active (e.g. app unlock, cold start, login race).
    if ((_subscriptionController?.status ?? SubscriptionStatus.unknown) ==
        SubscriptionStatus.entitled) {
      _schedulePrompt();
    }
  }

  void _onSubscriptionChanged() {
    final controller = _subscriptionController;
    if (controller == null) return;

    final next = controller.status;
    final prev = _lastStatus;
    _lastStatus = next;

    if (next != SubscriptionStatus.entitled) {
      _promptedForUid = false;
      return;
    }
    if (prev == SubscriptionStatus.entitled) return;

    _schedulePrompt();
  }

  void _onCloudAuthChanged() {
    final controller = _cloudAuthController;
    if (controller == null) return;

    final uid = controller.uid;
    if (_lastUid == uid) return;

    _lastUid = uid;
    _promptedForUid = false;

    if ((_subscriptionController?.status ?? SubscriptionStatus.unknown) ==
        SubscriptionStatus.entitled) {
      _schedulePrompt();
    }
  }

  void _schedulePrompt() {
    if (!mounted) return;
    if (_promptScheduled) return;

    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      unawaited(_maybePromptSwitchToCloud());
    });
  }

  void _scheduleAiFeatureGuidePrompt() {
    if (!mounted) return;
    if (_aiGuidePromptScheduled) return;

    _aiGuidePromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aiGuidePromptScheduled = false;
      unawaited(_maybePromptReviewAiFeatureGuide());
    });
  }

  Future<void> _maybePromptSwitchToCloud() async {
    if (!mounted) return;
    if (_dialogShowing) return;

    final uid = _lastUid?.trim();
    if (uid == null || uid.isEmpty) return;
    if (_promptedForUid) return;

    final backendType = await _store.readBackendType();
    if (!mounted) return;
    if (backendType == SyncBackendType.managedVault) {
      final savedRemoteRoot = (await _store.readRemoteRoot())?.trim();
      if (savedRemoteRoot != null &&
          savedRemoteRoot.isNotEmpty &&
          savedRemoteRoot != uid) {
        final syncDirection = await _promptSyncSwitchDirection();
        if (!mounted) return;
        if (syncDirection == null) {
          _promptedForUid = true;
          return;
        }
        final switchHandled =
            await _switchToCloud(uid, direction: syncDirection);
        if (!mounted || !switchHandled) return;
      } else {
        await _ensureManagedVaultSyncKey(uid);
      }
      _promptedForUid = true;
      await _maybePromptReviewAiFeatureGuide();
      return;
    }
    final shouldSwitch = await _promptSwitchToCloud();

    if (!mounted) return;
    if (shouldSwitch == true) {
      final syncDirection = await _promptSyncSwitchDirection();
      if (!mounted) return;
      if (syncDirection == null) {
        _promptedForUid = true;
        return;
      }
      final switchHandled = await _switchToCloud(uid, direction: syncDirection);
      if (!mounted || !switchHandled) return;
    }
    _promptedForUid = true;

    await _maybePromptReviewAiFeatureGuide();
  }

  Future<void> _maybePromptReviewAiFeatureGuide() async {
    if (!mounted) return;
    if (_dialogShowing) {
      _scheduleAiFeatureGuidePrompt();
      return;
    }

    final uid = _lastUid?.trim();
    if (uid == null || uid.isEmpty) return;

    final subscriptionStatus =
        _subscriptionController?.status ?? SubscriptionStatus.unknown;
    if (subscriptionStatus != SubscriptionStatus.entitled) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if ((prefs.getBool(cloudSyncSwitchInProgressPrefsKey) ?? false) == true) {
      _scheduleAiFeatureGuidePrompt();
      return;
    }

    final alreadyPromptedUid =
        (prefs.getString(_kCloudAiFeatureGuidePromptedUidPrefsKey) ?? '')
            .trim();
    if (alreadyPromptedUid == uid) return;

    final dialogContext = widget.navigatorKey?.currentContext;
    if (widget.navigatorKey != null && dialogContext == null) {
      _scheduleAiFeatureGuidePrompt();
      return;
    }
    final effectiveContext = dialogContext ?? context;
    if (!effectiveContext.mounted) {
      _scheduleAiFeatureGuidePrompt();
      return;
    }

    final t = effectiveContext.t;
    _dialogShowing = true;
    final review = await showDialog<bool>(
      context: effectiveContext,
      builder: (context) {
        return AlertDialog(
          title: Text(t.sync.cloudManagedVault.aiFeatureGuideDialog.title),
          content: Text(t.sync.cloudManagedVault.aiFeatureGuideDialog.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.sync.cloudManagedVault.aiFeatureGuideDialog.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child:
                  Text(t.sync.cloudManagedVault.aiFeatureGuideDialog.confirm),
            ),
          ],
        );
      },
    );
    _dialogShowing = false;

    await prefs.setString(_kCloudAiFeatureGuidePromptedUidPrefsKey, uid);

    if (review == true && effectiveContext.mounted) {
      await Navigator.of(effectiveContext, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const AiSettingsPage(
            focusSection: AiSettingsSection.smartOrganization,
            highlightFocus: true,
          ),
        ),
      );
    }
  }

  Future<
      ({
        bool completed,
        String? failureMessage,
        bool pauseSync,
        bool rollbackConfig,
      })> _runManagedVaultSyncWithProgress({
    required BuildContext dialogContext,
    required SyncEngine? engine,
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required SyncSwitchDirection direction,
    VoidCallback? onSafeToRestartEngine,
  }) async {
    final t = dialogContext.t;
    final materialLocalizations = MaterialLocalizations.of(dialogContext);
    final stage = ValueNotifier<String>(t.sync.progressDialog.preparing);
    // Keep progress determinate: an indeterminate LinearProgressIndicator
    // (value: null) animates continuously and can make widget tests using
    // pumpAndSettle time out.
    final progress = ValueNotifier<double>(0.0);

    var completed = true;
    var pauseSync = false;
    var rollbackConfig = false;
    Object? runFailureMessage = kNoManagedVaultSyncFailureMessage;
    bool started = false;
    _dialogShowing = true;
    try {
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) {
          if (!started) {
            started = true;
            unawaited(() async {
              try {
                var allowMediaUploads =
                    direction != SyncSwitchDirection.remoteReplacesLocal;
                switch (direction) {
                  case SyncSwitchDirection.localReplacesRemote:
                    stage.value = t.sync.progressDialog.pushing;
                    progress.value = 0.0;
                    var remoteCleared = false;
                    try {
                      await backend.syncManagedVaultClearVault(
                        baseUrl: baseUrl,
                        vaultId: vaultId,
                        idToken: idToken,
                      );
                      remoteCleared = true;
                      await _runManagedVaultPushStageWithProgress(
                        engine: engine,
                        backend: backend,
                        sessionKey: sessionKey,
                        syncKey: syncKey,
                        baseUrl: baseUrl,
                        vaultId: vaultId,
                        idToken: idToken,
                        stage: stage,
                        progress: progress,
                        allowRecovery: false,
                      );
                    } catch (error) {
                      if (remoteCleared) {
                        throw SyncRemoteReplaceCommittedException(error);
                      }
                      rethrow;
                    }
                    break;
                  case SyncSwitchDirection.remoteReplacesLocal:
                    stage.value = t.sync.progressDialog.pulling;
                    progress.value = 0.0;
                    await runDestructiveReplaceLocalWithRollback<void>(
                      backend: backend,
                      sessionKey: sessionKey,
                      run: () => _runManagedVaultPullStageWithProgress(
                        backend: backend,
                        sessionKey: sessionKey,
                        syncKey: syncKey,
                        baseUrl: baseUrl,
                        vaultId: vaultId,
                        idToken: idToken,
                        stage: stage,
                        progress: progress,
                      ),
                    );
                    break;
                  case SyncSwitchDirection.merge:
                    var retryPushAfterPull = false;
                    final pushStage =
                        await _runManagedVaultPushStageWithProgress(
                      engine: engine,
                      backend: backend,
                      sessionKey: sessionKey,
                      syncKey: syncKey,
                      baseUrl: baseUrl,
                      vaultId: vaultId,
                      idToken: idToken,
                      stage: stage,
                      progress: progress,
                      allowRecovery: true,
                    );
                    allowMediaUploads = pushStage.recoveryAction ==
                        ManagedVaultPushFailureRecoveryAction.none;
                    retryPushAfterPull = pushStage.recoveryAction ==
                        ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;

                    if (pushStage.recoveryAction ==
                        ManagedVaultPushFailureRecoveryAction.pullOnly) {
                      completed = false;
                      rollbackConfig = true;
                      runFailureMessage = pushStage.failureMessage;
                      break;
                    }

                    await _runManagedVaultPullStageWithProgress(
                      backend: backend,
                      sessionKey: sessionKey,
                      syncKey: syncKey,
                      baseUrl: baseUrl,
                      vaultId: vaultId,
                      idToken: idToken,
                      stage: stage,
                      progress: progress,
                    );
                    if (retryPushAfterPull) {
                      await _runManagedVaultPushStageWithProgress(
                        engine: engine,
                        backend: backend,
                        sessionKey: sessionKey,
                        syncKey: syncKey,
                        baseUrl: baseUrl,
                        vaultId: vaultId,
                        idToken: idToken,
                        stage: stage,
                        progress: progress,
                        allowRecovery: false,
                      );
                      allowMediaUploads = true;
                      retryPushAfterPull = false;
                      await _runManagedVaultPullStageWithProgress(
                        backend: backend,
                        sessionKey: sessionKey,
                        syncKey: syncKey,
                        baseUrl: baseUrl,
                        vaultId: vaultId,
                        idToken: idToken,
                        stage: stage,
                        progress: progress,
                      );
                    }
                    break;
                }
                if (!rollbackConfig && !pauseSync) {
                  onSafeToRestartEngine?.call();
                }

                // Media uploads (optional)
                final mediaEnabled = allowMediaUploads &&
                    await _store.readCloudMediaBackupEnabled();
                if (mediaEnabled) {
                  final wifiOnly = await _store.readCloudMediaBackupWifiOnly();
                  stage.value = t.sync.progressDialog.uploadingMedia;
                  progress.value = 0.0;

                  final runner = CloudMediaBackupRunner(
                    store: BackendCloudMediaBackupStore(
                      backend: backend,
                      sessionKey: sessionKey,
                      scopeId: _store.syncStateScopeIdForFields(
                        backendType: SyncBackendType.managedVault,
                        baseUrl: baseUrl,
                        remoteRoot: vaultId,
                        syncKey: syncKey,
                      ),
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
                      wifiOnly: wifiOnly,
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
              } catch (error) {
                final remoteReplaceCommitted =
                    error is SyncRemoteReplaceCommittedException;
                final displayError =
                    remoteReplaceCommitted ? error.cause : error;
                pauseSync = remoteReplaceCommitted ||
                    (direction == SyncSwitchDirection.remoteReplacesLocal &&
                        error.toString().contains('rollback failed'));
                rollbackConfig = !remoteReplaceCommitted &&
                    (direction == SyncSwitchDirection.remoteReplacesLocal ||
                        shouldRollbackManagedVaultBootstrapAfterFailure(
                            displayError));
                runFailureMessage = _managedVaultSyncFailureMessage(
                  t,
                  materialLocalizations,
                  displayError,
                );
                // Best-effort: avoid blocking the user on transient sync errors.
                completed = false;
              } finally {
                if (!rollbackConfig && !pauseSync) {
                  onSafeToRestartEngine?.call();
                }
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
                  ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (context, value, _) {
                      final percent =
                          (value * 100).floor().clamp(0, 100).toString();
                      final percentLabel =
                          t.common.labels.percent(value: percent);
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                key: kCloudSyncProgressKey,
                                value: value,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 48,
                            child: Text(
                              percentLabel,
                              key: kCloudSyncPercentKey,
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
      _dialogShowing = false;
      stage.dispose();
      progress.dispose();
    }
    return (
      completed: completed,
      failureMessage: switch (runFailureMessage) {
        String message => message,
        _ => null,
      },
      pauseSync: pauseSync,
      rollbackConfig: rollbackConfig,
    );
  }

  Future<bool> _switchToCloud(
    String uid, {
    required SyncSwitchDirection direction,
  }) async {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    if (backendScope == null) return false;
    final backend = backendScope.backend;

    final previousBackendType = await _store.readBackendType();
    final previousAll = await _store.readAll();
    final previousWebdavBaseUrl = previousAll[SyncConfigStore.kWebdavBaseUrl];
    final previousWebdavUsername = previousAll[SyncConfigStore.kWebdavUsername];
    final previousWebdavPassword = await _store.readWebdavPassword();
    final previousLocalDir = previousAll[SyncConfigStore.kLocalDir];
    final previousManagedVaultBaseUrl =
        previousAll[SyncConfigStore.kManagedVaultBaseUrl];
    final previousRemoteRoot = previousAll[SyncConfigStore.kRemoteRoot];
    final previousAutoEnabled =
        previousAll[SyncConfigStore.kAutoEnabled] == null ||
            previousAll[SyncConfigStore.kAutoEnabled] == '1';
    final previousSyncKey = await _store.readSyncKey();
    if (!mounted) return false;

    final sessionKey =
        context.getInheritedWidgetOfExactType<SessionScope>()?.sessionKey;
    final baseUrl = await _store.resolveManagedVaultBaseUrl();
    String? idToken;
    try {
      idToken = await readCloudAuthIdToken(
        _cloudAuthController,
        mode: CloudAuthAccessMode.interactive,
      );
    } catch (_) {
      idToken = null;
    }
    if (!mounted) return false;

    final dialogContext = widget.navigatorKey?.currentContext;
    final effectiveContext = (dialogContext != null && dialogContext.mounted)
        ? dialogContext
        : context;
    if (!effectiveContext.mounted) return false;

    final canShowDialog =
        Navigator.maybeOf(effectiveContext, rootNavigator: true) != null;

    if (sessionKey == null ||
        baseUrl == null ||
        baseUrl.trim().isEmpty ||
        idToken == null ||
        idToken.trim().isEmpty ||
        !effectiveContext.mounted ||
        !canShowDialog) {
      if (mounted) {
        _showSnack(
          switch ((sessionKey, baseUrl, idToken, canShowDialog)) {
            (null, _, _, _) =>
              context.t.sync.cloudManagedVault.serverUnavailable,
            (_, null, _, _) => context.t.sync.baseUrlRequired,
            (_, final String value, _, _) when value.trim().isEmpty =>
              context.t.sync.baseUrlRequired,
            (_, _, null, _) => context.t.sync.cloudManagedVault.signInRequired,
            (_, _, final String value, _) when value.trim().isEmpty =>
              context.t.sync.cloudManagedVault.signInRequired,
            _ => context.t.sync.cloudManagedVault.serverUnavailable,
          },
        );
      }
      return false;
    }

    var didSync = false;
    final engine = SyncEngineScope.maybeOf(context);
    var shouldRestartEngine = engine?.isRunning ?? false;
    var restartedEngineBeforeDialogDismiss = false;
    final switchPrefs = await SharedPreferences.getInstance();
    var switchInProgressMarked = false;
    var shouldRefreshBackgroundSchedule = false;
    void restartEngineBeforeDialogDismiss() {
      if (!shouldRestartEngine || restartedEngineBeforeDialogDismiss) return;
      engine?.start();
      restartedEngineBeforeDialogDismiss = true;
    }

    try {
      await switchPrefs.setBool(cloudSyncSwitchInProgressPrefsKey, true);
      switchInProgressMarked = true;
      await engine?.stopImmediatelyAndWait(
        timeout: kDestructiveSyncStopTimeout,
      );
      if (!effectiveContext.mounted) return false;
      final syncKey = await _resolveManagedVaultSyncKey(
        uid: uid,
        backend: backend,
      );
      await _store.writePrimarySyncSettings(
        backendType: SyncBackendType.managedVault,
        remoteRoot: uid,
      );
      shouldRefreshBackgroundSchedule = true;
      if (!mounted) return false;
      if (!effectiveContext.mounted) return false;

      final result = await _runManagedVaultSyncWithProgress(
        dialogContext: effectiveContext,
        engine: engine,
        backend: backend,
        sessionKey: sessionKey,
        syncKey: syncKey,
        baseUrl: baseUrl.trim(),
        vaultId: uid,
        idToken: idToken.trim(),
        direction: direction,
        onSafeToRestartEngine: restartEngineBeforeDialogDismiss,
      );
      if (!result.completed && result.rollbackConfig) {
        await _restoreCloudSyncPreviousSyncConfig(
          this,
          backend: backend,
          previousBackendType: previousBackendType,
          previousWebdavBaseUrl: previousWebdavBaseUrl,
          previousWebdavUsername: previousWebdavUsername,
          previousWebdavPassword: previousWebdavPassword,
          previousLocalDir: previousLocalDir,
          previousManagedVaultBaseUrl: previousManagedVaultBaseUrl,
          previousRemoteRoot: previousRemoteRoot,
          previousAutoEnabled: previousAutoEnabled,
          previousSyncKey: previousSyncKey,
          engine: engine,
          refreshSchedule: false,
        );
        shouldRefreshBackgroundSchedule = true;
        if (result.pauseSync) {
          shouldRestartEngine = false;
          await _store.writeAutoEnabled(false);
        }
        if (mounted && result.failureMessage != null) {
          _showSnack(result.failureMessage!);
        }
        return true;
      }
      didSync = result.completed;
      if (result.pauseSync) {
        shouldRestartEngine = false;
        await _store.writeAutoEnabled(false);
        shouldRefreshBackgroundSchedule = true;
      }
      if (mounted && result.failureMessage != null) {
        _showSnack(result.failureMessage!);
      }
    } catch (error) {
      if (error is TimeoutException &&
          (error.message?.contains(
                'sync engine did not stop before destructive operation',
              ) ??
              false)) {
        shouldRestartEngine = false;
      }
      await _restoreCloudSyncPreviousSyncConfig(
        this,
        backend: backend,
        previousBackendType: previousBackendType,
        previousWebdavBaseUrl: previousWebdavBaseUrl,
        previousWebdavUsername: previousWebdavUsername,
        previousWebdavPassword: previousWebdavPassword,
        previousLocalDir: previousLocalDir,
        previousManagedVaultBaseUrl: previousManagedVaultBaseUrl,
        previousRemoteRoot: previousRemoteRoot,
        previousAutoEnabled: previousAutoEnabled,
        previousSyncKey: previousSyncKey,
        engine: engine,
        refreshSchedule: false,
      );
      shouldRefreshBackgroundSchedule = true;
      if (mounted) {
        _showSnack(
          _managedVaultUserFacingErrorMessage(
            context.t,
            MaterialLocalizations.of(context),
            error,
          ),
        );
      }
      return true;
    } finally {
      if (switchInProgressMarked) {
        try {
          await switchPrefs.setBool(cloudSyncSwitchInProgressPrefsKey, false);
        } catch (e) {
          debugPrint(
            'cloud sync switch: failed to clear in-progress marker: $e',
          );
        }
      }
      if (shouldRefreshBackgroundSchedule) {
        unawaited(_refreshCloudSyncSwitchBackgroundScheduleBestEffort(
          backend: backend,
          store: _store,
        ));
      }
      if (shouldRestartEngine && !restartedEngineBeforeDialogDismiss) {
        engine?.start();
      }
    }

    if (!mounted) return true;
    engine?.notifyExternalChange();
    if (!didSync && shouldRestartEngine) {
      engine?.triggerPushNow();
      engine?.triggerPullNow();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
