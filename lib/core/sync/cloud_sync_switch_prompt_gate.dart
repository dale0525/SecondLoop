import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../cloud/cloud_auth_access.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import '../../features/media_backup/cloud_media_backup_runner.dart';
import '../../features/settings/ai_settings_page.dart';
import 'cloud_sync_switch_prefs.dart';
import 'stage_progress_smoother.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';
import 'sync_engine_gate.dart';
import 'background_sync.dart';
import 'sync_key_manager.dart';
import 'sync_http_error.dart';

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

  static const _kSyncProgressIndicatorKey =
      ValueKey('cloud_sync_switch_progress');
  static const _kSyncProgressPercentKey =
      ValueKey('cloud_sync_switch_progress_percent');
  static const _kNoManagedVaultSyncFailureMessage = Object();

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
      ),
    );
  }

  SyncStageProgressReporter _makeSmoothStageProgressReporter(
    ValueNotifier<double> progress,
  ) {
    return SyncStageProgressReporter((value) => progress.value = value);
  }

  String _managedVaultRecoveredMessageForGate(SyncWriteGateState gate) {
    final t = context.t;
    if (gate.kind == SyncWriteGateKind.localRepairRequired) {
      return t.sync.cloudManagedVault.localSyncDataRepairRequired;
    }
    if (gate.kind == SyncWriteGateKind.paymentRequired) {
      return t.sync.cloudManagedVault.paymentRequired;
    }
    if (gate.kind == SyncWriteGateKind.graceReadOnly) {
      final untilMs = gate.graceUntilMs;
      if (untilMs != null && DateTime.now().millisecondsSinceEpoch < untilMs) {
        final dt = DateTime.fromMillisecondsSinceEpoch(untilMs).toLocal();
        final until = MaterialLocalizations.of(context).formatShortDate(dt);
        return t.sync.cloudManagedVault.graceReadonlyUntil(until: until);
      }
      return t.sync.cloudManagedVault.serverUnavailable;
    }
    if (gate.kind == SyncWriteGateKind.storageQuotaExceeded) {
      return t.sync.cloudManagedVault.storageQuotaExceeded;
    }
    return t.sync.cloudManagedVault.serverUnavailable;
  }

  String _managedVaultUserFacingErrorMessage(Object error) {
    final status = extractSyncHttpStatusCode(error);
    final code = extractSyncErrorCode(error);
    if (status == 400 && code == 'invalid_batch') {
      return context.t.sync.cloudManagedVault.localSyncDataRepairRequired;
    }
    final recoveryBlockedReason =
        extractManagedVaultRecoveryBlockedReason(error);
    if (recoveryBlockedReason == 'local_unpushed_changes') {
      return context.t.sync.cloudManagedVault.localChangesUploadRequired;
    }
    if (recoveryBlockedReason == 'local_media_backfill_pending') {
      return context.t.sync.cloudManagedVault.localMediaBackfillRequired;
    }
    final gate = inspectManagedVaultPushFailure(error).writeGateState;
    if (gate != null) {
      return _managedVaultRecoveredMessageForGate(gate);
    }
    return '$error';
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

  String? _managedVaultSyncFailureMessage(Object error) {
    return _managedVaultUserFacingErrorMessage(error);
  }

  Future<void> _clearManagedVaultBackgroundRepairBlock() {
    return _store.writeBackgroundSyncRepairRequired(
      false,
      backendType: SyncBackendType.managedVault,
    );
  }

  Future<ManagedVaultPushFailureRecoveryAction>
      _runManagedVaultPushStageWithProgress({
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
    final stageProgress = _makeSmoothStageProgressReporter(progress);
    stage.value = context.t.sync.progressDialog.pushing;
    progress.value = 0.0;
    try {
      await _consumeRustProgressStream(
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
      await _clearManagedVaultBackgroundRepairBlock();
      reopenManagedVaultWriteGateOnSuccess(engine);
      return ManagedVaultPushFailureRecoveryAction.none;
    } catch (error) {
      final details = _applyManagedVaultPushFailure(error, engine: engine);
      if (!allowRecovery ||
          details.recoveryAction ==
              ManagedVaultPushFailureRecoveryAction.none) {
        rethrow;
      }
      return details.recoveryAction;
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

  Future<void> _maybePromptSwitchToCloud() async {
    if (!mounted) return;
    if (_dialogShowing) return;

    final uid = _lastUid?.trim();
    if (uid == null || uid.isEmpty) return;
    if (_promptedForUid) return;

    final backendType = await _store.readBackendType();
    if (!mounted) return;
    if (backendType == SyncBackendType.managedVault) {
      await _ensureManagedVaultSyncKey(uid);
      _promptedForUid = true;
      await _maybePromptReviewAiFeatureGuide();
      return;
    }

    final dialogContext = widget.navigatorKey?.currentContext;
    if (widget.navigatorKey != null && dialogContext == null) {
      _schedulePrompt();
      return;
    }
    final effectiveContext = dialogContext ?? context;
    if (!effectiveContext.mounted) {
      _schedulePrompt();
      return;
    }

    final t = effectiveContext.t;
    _dialogShowing = true;
    final shouldSwitch = await showDialog<bool>(
      context: effectiveContext,
      builder: (context) {
        return AlertDialog(
          title: Text(t.sync.cloudManagedVault.switchDialog.title),
          content: Text(t.sync.cloudManagedVault.switchDialog.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.sync.cloudManagedVault.switchDialog.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.sync.cloudManagedVault.switchDialog.confirm),
            ),
          ],
        );
      },
    );
    _dialogShowing = false;
    _promptedForUid = true;

    if (!mounted) return;
    if (shouldSwitch == true) {
      await _switchToCloud(uid);
    }

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

  Future<({bool completed, String? failureMessage})>
      _runManagedVaultSyncWithProgress({
    required BuildContext dialogContext,
    required SyncEngine? engine,
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final t = dialogContext.t;
    final stage = ValueNotifier<String>(t.sync.progressDialog.preparing);
    // Keep progress determinate: an indeterminate LinearProgressIndicator
    // (value: null) animates continuously and can make widget tests using
    // pumpAndSettle time out.
    final progress = ValueNotifier<double>(0.0);

    var completed = true;
    Object? runError;
    StackTrace? runErrorStackTrace;
    Object? runFailureMessage = _kNoManagedVaultSyncFailureMessage;
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
                var allowMediaUploads = true;
                var retryPushAfterPull = false;

                // Push local changes first so the next pull converges to the
                // authoritative remote head for this vault generation.
                final recoveryAction =
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
                allowMediaUploads = recoveryAction ==
                    ManagedVaultPushFailureRecoveryAction.none;
                retryPushAfterPull = recoveryAction ==
                    ManagedVaultPushFailureRecoveryAction.pullThenRetryPush;

                // Pull after push to converge to the latest remote log head.
                final stageProgress =
                    _makeSmoothStageProgressReporter(progress);
                stage.value = t.sync.progressDialog.pulling;
                progress.value = 0.0;
                await _consumeRustProgressStream(
                  backend.syncManagedVaultPullProgress(
                    sessionKey,
                    syncKey,
                    baseUrl: baseUrl,
                    vaultId: vaultId,
                    idToken: idToken,
                  ),
                  onProgress: stageProgress.onProgress,
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

                // Finalize
                stage.value = t.sync.progressDialog.finalizing;
                stageProgress.complete();
              } catch (error, stackTrace) {
                if (shouldRollbackManagedVaultBootstrapOnError(error)) {
                  runError = error;
                  runErrorStackTrace = stackTrace;
                } else {
                  runFailureMessage = _managedVaultSyncFailureMessage(error);
                }
                // Best-effort: avoid blocking the user on transient sync errors.
                completed = false;
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
                                key: _kSyncProgressIndicatorKey,
                                value: value,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 48,
                            child: Text(
                              percentLabel,
                              key: _kSyncProgressPercentKey,
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
    );
  }

  Future<void> _switchToCloud(String uid) async {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    if (backendScope == null) return;
    final backend = backendScope.backend;

    final previousBackendType = await _store.readBackendType();
    final previousRemoteRoot = await _store.readRemoteRoot();
    final previousSyncKey = await _store.readSyncKey();

    final syncKey = await SyncKeyManager.deriveManagedVaultSyncKey(
      vaultId: uid,
      deriveSyncKey: backend.deriveSyncKey,
    );
    await SyncKeyManager.save(
      write: _store.writeSyncKey,
      key: syncKey,
    );

    await _store.writeBackendType(SyncBackendType.managedVault);
    await _store.writeRemoteRoot(uid);
    if (!mounted) return;

    unawaited(BackgroundSync.refreshSchedule(
      backend: backend,
      configStore: _store,
    ));

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
    if (!mounted) return;

    final dialogContext = widget.navigatorKey?.currentContext;
    final effectiveContext = (dialogContext != null && dialogContext.mounted)
        ? dialogContext
        : context;
    if (!effectiveContext.mounted) return;

    final canShowDialog =
        Navigator.maybeOf(effectiveContext, rootNavigator: true) != null;

    var didSync = false;
    final engine = SyncEngineScope.maybeOf(context);
    if (sessionKey != null &&
        baseUrl != null &&
        baseUrl.trim().isNotEmpty &&
        idToken != null &&
        idToken.trim().isNotEmpty &&
        effectiveContext.mounted &&
        canShowDialog) {
      try {
        final result = await _runManagedVaultSyncWithProgress(
          dialogContext: effectiveContext,
          engine: engine,
          backend: backend,
          sessionKey: sessionKey,
          syncKey: syncKey,
          baseUrl: baseUrl.trim(),
          vaultId: uid,
          idToken: idToken.trim(),
        );
        didSync = result.completed;
        if (mounted && result.failureMessage != null) {
          _showSnack(result.failureMessage!);
        }
      } catch (error) {
        await _store.writeBackendType(previousBackendType);
        await _store.writeRemoteRoot(previousRemoteRoot ?? '');
        if (previousSyncKey != null) {
          await SyncKeyManager.save(
            write: _store.writeSyncKey,
            key: previousSyncKey,
          );
        } else {
          await _store.clearSyncKey();
        }
        unawaited(BackgroundSync.refreshSchedule(
          backend: backend,
          configStore: _store,
        ));
        if (mounted) {
          _showSnack(_managedVaultUserFacingErrorMessage(error));
        }
        return;
      }
    }

    if (!mounted) return;
    engine?.notifyExternalChange();
    if (!didSync) {
      engine?.triggerPushNow();
      engine?.triggerPullNow();
    }
  }

  Future<void> _ensureManagedVaultSyncKey(String uid) async {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    if (backendScope == null) return;
    final backend = backendScope.backend;
    try {
      final syncKey = await SyncKeyManager.deriveManagedVaultSyncKey(
        vaultId: uid,
        deriveSyncKey: backend.deriveSyncKey,
      );
      await SyncKeyManager.save(
        write: _store.writeSyncKey,
        key: syncKey,
      );
    } catch (_) {
      // Best-effort self-heal for managed-vault key policy.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
