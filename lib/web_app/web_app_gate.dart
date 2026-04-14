import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/router.dart';
import '../core/ai/ai_routing.dart';
import '../core/backend/app_backend.dart';
import '../core/backend/cloud_web_backend.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/cloud_auth_scope.dart';
import '../core/cloud/cloud_usage_client.dart';
import '../core/cloud/vault_attachments_client.dart';
import '../core/cloud/vault_usage_client.dart';
import '../core/platform/app_platform_capabilities.dart';
import '../core/platform/app_platform_capability_scope.dart';
import '../core/session/session_scope.dart';
import '../core/sync/sync_config_store.dart';
import '../core/sync/sync_engine.dart';
import 'web_entry_intent.dart';
import 'web_public_entry_scaffold.dart';
import 'web_app_service.dart';
import '../features/settings/cloud_account_panel.dart';
import 'web_formal_settings_adapters.dart';
import 'web_formal_settings_scope.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/subscription_scope.dart';

export 'web_app_service.dart';

class WebAppGate extends StatefulWidget {
  const WebAppGate({
    required this.authController,
    required this.service,
    this.chatBackend,
    this.entryIntent = WebEntryIntent.open,
    this.managedVaultBaseUrl = '',
    super.key,
  });

  final ObservableCloudAuthController authController;
  final WebAppService service;
  final CloudWebBackend? chatBackend;
  final WebEntryIntent entryIntent;
  final String managedVaultBaseUrl;

  @override
  State<WebAppGate> createState() => _WebAppGateState();
}

class _WebAppGateState extends State<WebAppGate> {
  late CloudWebBackend _chatBackend;
  late CloudSubscriptionController _subscriptionController;
  late WebAppBillingClient _billingClient;
  late CloudUsageClient _cloudUsageClient;
  late VaultUsageClient _vaultUsageClient;
  late VaultAttachmentsClient _vaultAttachmentsClient;
  late SyncConfigStore _vaultConfigStore;

  bool _canAccessMainShell = false;
  String? _activeUid;
  String? _mainShellUid;

  String? _normalizedUid() {
    final uid = widget.authController.uid?.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  void _resetSessionScopedState() {
    _chatBackend.clearWebSessionState();
    _subscriptionController.reset();
    _canAccessMainShell = false;
    _mainShellUid = null;
  }

  void _createInjectedDependencies() {
    _chatBackend = widget.chatBackend ??
        CloudWebBackend(chatClient: const UnsupportedCloudWebChatClient());
    _subscriptionController = createWebFormalSubscriptionController(
      service: widget.service,
      authController: widget.authController,
    );
    _subscriptionController.addListener(_onSubscriptionChanged);
    _billingClient = WebAppBillingClient(
      service: widget.service,
      authController: widget.authController,
    );
    _cloudUsageClient = createWebFormalCloudUsageClient(
      service: widget.service,
      authController: widget.authController,
    );
    _vaultUsageClient = createWebFormalVaultUsageClient(
      service: widget.service,
      authController: widget.authController,
    );
    _vaultAttachmentsClient = createWebFormalVaultAttachmentsClient(
      service: widget.service,
      authController: widget.authController,
    );
    _vaultConfigStore = SyncConfigStore(
      managedVaultDefaultBaseUrl: widget.managedVaultBaseUrl.trim(),
    );
    unawaited(_primeWebFormalSyncDefaults());
  }

  Future<void> _primeWebFormalSyncDefaults() async {
    final storedBaseUrl =
        (await _vaultConfigStore.readManagedVaultBaseUrl())?.trim() ?? '';
    if (storedBaseUrl == kWebFormalSettingsBaseUrl) {
      await _vaultConfigStore.writeManagedVaultBaseUrl('');
    }
    await _vaultConfigStore.writeBackendType(SyncBackendType.managedVault);
  }

  void _disposeInjectedDependencies() {
    _subscriptionController.removeListener(_onSubscriptionChanged);
    _subscriptionController.dispose();
    _cloudUsageClient.dispose();
    _vaultUsageClient.dispose();
    _vaultAttachmentsClient.dispose();
  }

  @override
  void initState() {
    super.initState();
    _createInjectedDependencies();
    _activeUid = _normalizedUid();
    widget.authController.addListener(_onAuthChanged);
    unawaited(_refreshGateState());
  }

  @override
  void didUpdateWidget(covariant WebAppGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final authChanged = oldWidget.authController != widget.authController;
    final serviceChanged = oldWidget.service != widget.service;
    final chatBackendChanged = oldWidget.chatBackend != widget.chatBackend;
    if (!authChanged && !serviceChanged && !chatBackendChanged) {
      return;
    }

    oldWidget.authController.removeListener(_onAuthChanged);
    _disposeInjectedDependencies();
    _createInjectedDependencies();
    widget.authController.addListener(_onAuthChanged);

    _activeUid = _normalizedUid();
    if (authChanged || chatBackendChanged) {
      _resetSessionScopedState();
    } else {
      _syncMainShellAccess();
    }

    unawaited(_refreshGateState(expectedUid: _activeUid));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    _disposeInjectedDependencies();
    super.dispose();
  }

  void _onAuthChanged() {
    final nextUid = _normalizedUid();
    if (nextUid != _activeUid) {
      _activeUid = nextUid;
      _resetSessionScopedState();
    }
    _syncMainShellAccess();
    if (mounted) {
      setState(() {});
    }
    unawaited(_refreshGateState(expectedUid: nextUid));
  }

  void _onSubscriptionChanged() {
    _syncMainShellAccess();
    if (!mounted) return;
    setState(() {});
  }

  void _syncMainShellAccess() {
    final uid = widget.authController.uid?.trim() ?? '';
    if (uid.isEmpty) {
      _canAccessMainShell = false;
      _mainShellUid = null;
      return;
    }

    switch (_subscriptionController.status) {
      case SubscriptionStatus.entitled:
        _canAccessMainShell = true;
        _mainShellUid = uid;
        return;
      case SubscriptionStatus.notEntitled:
        _canAccessMainShell = false;
        _mainShellUid = null;
        return;
      case SubscriptionStatus.unknown:
        if (_mainShellUid != uid) {
          _canAccessMainShell = false;
        }
        return;
    }
  }

  Future<void> _refreshGateState({String? expectedUid}) async {
    final refreshUid = expectedUid ?? _normalizedUid();
    await _subscriptionController.refresh();
    if (refreshUid != _normalizedUid()) return;
    _syncMainShellAccess();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.authController.uid;
    final webFormalSettings = WebFormalSettingsDependencies(
      billingClient: _billingClient,
      cloudUsageClient: _cloudUsageClient,
      vaultUsageClient: _vaultUsageClient,
      vaultAttachmentsClient: _vaultAttachmentsClient,
      vaultConfigStore: _vaultConfigStore,
      cloudAuthController: widget.authController,
      cloudGatewayConfig: const CloudGatewayConfig(
        baseUrl: kWebFormalSettingsBaseUrl,
        modelName: 'cloud',
      ),
      subscriptionController: _subscriptionController,
      isWebOverride: true,
    );
    late final Widget child;
    if (uid == null || uid.trim().isEmpty) {
      child = WebPublicEntryScaffold(
        entryIntent: widget.entryIntent,
        signedIn: false,
        child: CloudAccountPanel(
          billingClient: _billingClient,
          cloudUsageClient: _cloudUsageClient,
          vaultUsageClient: _vaultUsageClient,
          vaultAttachmentsClient: _vaultAttachmentsClient,
          vaultConfigStore: _vaultConfigStore,
          isWebOverride: true,
        ),
      );
    } else if (!_canAccessMainShell || _mainShellUid != uid.trim()) {
      child = WebPublicEntryScaffold(
        entryIntent: widget.entryIntent,
        signedIn: true,
        child: CloudAccountPanel(
          billingClient: _billingClient,
          cloudUsageClient: _cloudUsageClient,
          vaultUsageClient: _vaultUsageClient,
          vaultAttachmentsClient: _vaultAttachmentsClient,
          vaultConfigStore: _vaultConfigStore,
          isWebOverride: true,
        ),
      );
    } else {
      child = AppShell(
        key: ValueKey<String>('web-main-shell-$uid'),
        initialTab: widget.entryIntent == WebEntryIntent.manage
            ? AppTab.settings
            : AppTab.chat,
      );
    }

    return AppPlatformCapabilityScope(
      capabilities: AppPlatformCapabilities.webCloud(),
      child: AppBackendScope(
        backend: _chatBackend,
        child: CloudAuthScope(
          controller: widget.authController,
          gatewayConfig: const CloudGatewayConfig(
            baseUrl: kWebFormalSettingsBaseUrl,
            modelName: 'cloud',
          ),
          child: SubscriptionScope(
            controller: _subscriptionController,
            child: SessionScope(
              sessionKey: Uint8List(0),
              lock: () {},
              child: WebFormalSettingsScope(
                dependencies: webFormalSettings,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
