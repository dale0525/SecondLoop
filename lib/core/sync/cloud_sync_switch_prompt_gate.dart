import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_routing.dart';
import '../backend/app_backend.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../subscription/subscription_scope.dart';
import '../../i18n/strings.g.dart';
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

  late final SyncConfigStore _store = widget.configStore ?? SyncConfigStore();

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

  Future<void> _maybePromptSwitchToCloud() async {
    if (!mounted) return;
    if (_dialogShowing) return;

    final uid = _lastUid?.trim();
    if (uid == null || uid.isEmpty) return;
    if (_promptedForUid) return;

    final backendType = await _store.readBackendType();
    if (!mounted) return;
    if (backendType == SyncBackendType.managedVault) return;

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
    if (shouldSwitch != true) return;

    await _switchToCloud(uid);
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

    final engine = SyncEngineScope.maybeOf(context);
    engine?.notifyExternalChange();
    engine?.triggerPullNow();
    engine?.triggerPushNow();
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
