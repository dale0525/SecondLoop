import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_routing.dart';
import '../ai/embeddings_data_consent_prefs.dart';
import '../backend/app_backend.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
import 'cloud_sync_switch_prefs.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';
import 'sync_engine_gate.dart';
import 'background_sync.dart';

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
  bool _embeddingsPromptScheduled = false;

  static const _kSyncProgressTick = Duration(milliseconds: 120);
  static const _kSyncProgressIndicatorKey =
      ValueKey('cloud_sync_switch_progress');
  static const _kSyncProgressPercentKey =
      ValueKey('cloud_sync_switch_progress_percent');

  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();

  static const _kCloudEmbeddingsUpgradePromptedUidPrefsKey =
      'cloud_embeddings_upgrade_prompted_uid_v1';

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

  void _scheduleEmbeddingsPrompt() {
    if (!mounted) return;
    if (_embeddingsPromptScheduled) return;

    _embeddingsPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddingsPromptScheduled = false;
      unawaited(_maybePromptEnableCloudEmbeddings());
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
      _promptedForUid = true;
      await _maybePromptEnableCloudEmbeddings();
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

    await _maybePromptEnableCloudEmbeddings();
  }

  Future<void> _maybePromptEnableCloudEmbeddings() async {
    if (!mounted) return;
    if (_dialogShowing) {
      _scheduleEmbeddingsPrompt();
      return;
    }

    final uid = _lastUid?.trim();
    if (uid == null || uid.isEmpty) return;

    final subscriptionStatus =
        _subscriptionController?.status ?? SubscriptionStatus.unknown;
    if (subscriptionStatus != SubscriptionStatus.entitled) return;

    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool(cloudSyncSwitchInProgressPrefsKey) ?? false) == true) {
      _scheduleEmbeddingsPrompt();
      return;
    }
    final alreadyPromptedUid =
        (prefs.getString(_kCloudEmbeddingsUpgradePromptedUidPrefsKey) ?? '')
            .trim();
    if (alreadyPromptedUid == uid) return;
    if ((prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey) ?? false) == true) {
      await prefs.setString(_kCloudEmbeddingsUpgradePromptedUidPrefsKey, uid);
      return;
    }
    if (!mounted) return;

    final dialogContext = widget.navigatorKey?.currentContext;
    if (widget.navigatorKey != null && dialogContext == null) {
      _scheduleEmbeddingsPrompt();
      return;
    }
    final effectiveContext = dialogContext ?? context;
    if (!effectiveContext.mounted) {
      _scheduleEmbeddingsPrompt();
      return;
    }

    final t = effectiveContext.t;
    _dialogShowing = true;
    final enable = await showDialog<bool>(
      context: effectiveContext,
      builder: (context) {
        return AlertDialog(
          title: Text(t.chat.embeddingsConsent.title),
          content: Text(t.chat.embeddingsConsent.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.chat.embeddingsConsent.actions.useLocal),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.chat.embeddingsConsent.actions.enableCloud),
            ),
          ],
        );
      },
    );
    _dialogShowing = false;

    await EmbeddingsDataConsentPrefs.setEnabled(prefs, enable == true);
    await prefs.setString(_kCloudEmbeddingsUpgradePromptedUidPrefsKey, uid);
  }

  Future<void> _runManagedVaultSyncWithProgress({
    required BuildContext dialogContext,
    required AppBackend backend,
    required Uint8List sessionKey,
    required Uint8List syncKey,
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    final t = dialogContext.t;
    final stage = ValueNotifier<String>(t.sync.progressDialog.preparing);
    final progress = ValueNotifier<double>(0.0);

    double stageMax = 0.1;
    Timer? progressTimer;
    progressTimer = Timer.periodic(_kSyncProgressTick, (_) {
      final next = (progress.value + 0.01).clamp(0.0, stageMax);
      progress.value = next;
    });

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
                // Prepare
                await Future<void>.delayed(const Duration(milliseconds: 150));

                // Pull
                stage.value = t.sync.progressDialog.pulling;
                stageMax = 0.6;
                if (progress.value < 0.1) progress.value = 0.1;
                await backend.syncManagedVaultPull(
                  sessionKey,
                  syncKey,
                  baseUrl: baseUrl,
                  vaultId: vaultId,
                  idToken: idToken,
                );
                if (progress.value < 0.6) progress.value = 0.6;

                // Push
                stage.value = t.sync.progressDialog.pushing;
                stageMax = 0.95;
                await backend.syncManagedVaultPushOpsOnly(
                  sessionKey,
                  syncKey,
                  baseUrl: baseUrl,
                  vaultId: vaultId,
                  idToken: idToken,
                );
                if (progress.value < 0.95) progress.value = 0.95;

                // Finalize
                stage.value = t.sync.progressDialog.finalizing;
                stageMax = 1.0;
                progress.value = 1.0;
              } catch (_) {
                // Best-effort: avoid blocking the user on transient sync errors.
              } finally {
                progressTimer?.cancel();
                progressTimer = null;
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
                              '$percent%',
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
    } finally {
      _dialogShowing = false;
      progressTimer?.cancel();
      stage.dispose();
      progress.dispose();
    }
  }

  Future<void> _switchToCloud(String uid) async {
    final backendScope =
        context.getInheritedWidgetOfExactType<AppBackendScope>();
    if (backendScope == null) return;
    final backend = backendScope.backend;

    final existing = await _store.readSyncKey();
    if (!mounted) return;

    if (existing == null || existing.length != 32) {
      final passphrase = await _promptForPassphrase();
      if (!mounted) return;
      if (passphrase == null || passphrase.trim().isEmpty) return;

      final derived = await backend.deriveSyncKey(passphrase.trim());
      if (!mounted) return;
      await _store.writeSyncKey(derived);
    }

    await _store.writeBackendType(SyncBackendType.managedVault);
    await _store.writeRemoteRoot(uid);
    if (!mounted) return;

    unawaited(BackgroundSync.refreshSchedule(
      backend: backend,
      configStore: _store,
    ));

    final sessionKey =
        context.getInheritedWidgetOfExactType<SessionScope>()?.sessionKey;
    final syncKey = await _store.readSyncKey();
    final baseUrl = await _store.resolveManagedVaultBaseUrl();
    String? idToken;
    try {
      idToken = await _cloudAuthController?.getIdToken();
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
    if (sessionKey != null &&
        syncKey != null &&
        syncKey.length == 32 &&
        baseUrl != null &&
        baseUrl.trim().isNotEmpty &&
        idToken != null &&
        idToken.trim().isNotEmpty &&
        effectiveContext.mounted &&
        canShowDialog) {
      await _runManagedVaultSyncWithProgress(
        dialogContext: effectiveContext,
        backend: backend,
        sessionKey: sessionKey,
        syncKey: syncKey,
        baseUrl: baseUrl.trim(),
        vaultId: uid,
        idToken: idToken.trim(),
      );
      didSync = true;
    }

    if (!mounted) return;
    final engine = SyncEngineScope.maybeOf(context);
    engine?.notifyExternalChange();
    if (!didSync) {
      engine?.triggerPullNow();
      engine?.triggerPushNow();
    }
  }

  Future<String?> _promptForPassphrase() async {
    final dialogContext = widget.navigatorKey?.currentContext;
    final effectiveContext = dialogContext ?? context;

    final t = effectiveContext.t;
    final controller = TextEditingController();
    final passphrase = await showDialog<String?>(
      context: effectiveContext,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = controller.text.trim().isNotEmpty;
            return AlertDialog(
              title: Text(t.sync.cloudManagedVault.setPassphraseDialog.title),
              content: TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.sync.fields.passphrase.label,
                  helperText: t.sync.fields.passphrase.helper,
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(t.common.actions.cancel),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () => Navigator.of(context).pop(controller.text.trim())
                      : null,
                  child: Text(
                      t.sync.cloudManagedVault.setPassphraseDialog.confirm),
                ),
              ],
            );
          },
        );
      },
    );
    return passphrase;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
