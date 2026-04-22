import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/router.dart';
import '../core/app_bootstrap.dart';
import '../core/ai/ai_routing.dart';
import '../core/backend/app_backend.dart';
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
import '../features/lock/lock_gate.dart';
import 'web_entry_intent.dart';
import 'web_public_entry_scaffold.dart';
import 'web_app_service.dart';
import '../features/settings/cloud_account_panel.dart';
import 'web_formal_settings_adapters.dart';
import 'web_formal_settings_scope.dart';
import 'web_initial_sync_gate.dart';
import 'web_native_app_backend.dart';
import 'web_persistent_app_dir.dart';
import '../core/subscription/cloud_subscription_controller.dart';
import '../core/subscription/subscription_scope.dart';

export 'web_app_service.dart';

class WebAppGate extends StatefulWidget {
  const WebAppGate({
    required this.authController,
    required this.service,
    this.backend,
    this.defaultBackendBuilder,
    this.entryIntent = WebEntryIntent.open,
    this.managedVaultBaseUrl = '',
    this.syncDefaultsPrimer,
    this.syncDefaultsPrimingTimeout = const Duration(seconds: 2),
    super.key,
  });

  final ObservableCloudAuthController authController;
  final WebAppService service;
  final AppBackend? backend;
  final AppBackend Function()? defaultBackendBuilder;
  final WebEntryIntent entryIntent;
  final String managedVaultBaseUrl;
  final Future<void> Function(SyncConfigStore store)? syncDefaultsPrimer;
  final Duration syncDefaultsPrimingTimeout;

  @override
  State<WebAppGate> createState() => _WebAppGateState();
}

class _WebAppGateState extends State<WebAppGate> {
  final WebPersistentAppDirResolver _appDirResolver =
      OpfsWebPersistentAppDirResolver();
  late AppBackend _appBackend;
  late CloudSubscriptionController _subscriptionController;
  late WebAppBillingClient _billingClient;
  late CloudUsageClient _cloudUsageClient;
  late VaultUsageClient _vaultUsageClient;
  late VaultAttachmentsClient _vaultAttachmentsClient;
  late SyncConfigStore _vaultConfigStore;
  Future<void>? _syncDefaultsPriming;
  bool _syncDefaultsPrimed = false;

  bool _canAccessMainShell = false;
  String? _activeUid;
  String? _mainShellUid;
  late bool _usesManagedWebNativeBackend;

  String? _normalizedUid() {
    final uid = widget.authController.uid?.trim() ?? '';
    return uid.isEmpty ? null : uid;
  }

  void _resetSessionScopedState() {
    _subscriptionController.reset();
    _canAccessMainShell = false;
    _mainShellUid = null;
  }

  void _createInjectedDependencies() {
    final uid = _normalizedUid();
    _usesManagedWebNativeBackend =
        widget.backend == null && widget.defaultBackendBuilder == null;
    _appBackend = widget.backend ??
        widget.defaultBackendBuilder?.call() ??
        WebNativeAppBackend.withDefaults(
          appDirProvider: () async {
            final resolvedUid = _normalizedUid();
            if (resolvedUid == null) {
              throw StateError('missing_web_uid');
            }
            return _appDirResolver.resolve(uid: resolvedUid);
          },
          storageScope: _storageScopeForUid(uid),
          webAppService: widget.service,
        );
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
      scopeKey: _storageScopeForUid(uid),
      managedVaultDefaultBaseUrl: widget.managedVaultBaseUrl.trim(),
    );
    _syncDefaultsPrimed = false;
    final primingFuture = (widget.syncDefaultsPrimer?.call(_vaultConfigStore) ??
            _primeWebFormalSyncDefaults())
        .timeout(widget.syncDefaultsPrimingTimeout, onTimeout: () {});
    _syncDefaultsPriming = primingFuture;
    primingFuture.whenComplete(() {
      if (!mounted || !identical(_syncDefaultsPriming, primingFuture)) return;
      setState(() {
        _syncDefaultsPrimed = true;
      });
    });
  }

  String? _storageScopeForUid(String? uid) {
    final normalizedUid = uid?.trim();
    if (normalizedUid == null || normalizedUid.isEmpty) return null;
    return 'web-native:$normalizedUid';
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
    final backendChanged = oldWidget.backend != widget.backend;
    final defaultBackendBuilderChanged =
        oldWidget.defaultBackendBuilder != widget.defaultBackendBuilder;
    final managedVaultBaseUrlChanged = oldWidget.managedVaultBaseUrl.trim() !=
        widget.managedVaultBaseUrl.trim();
    if (!authChanged &&
        !serviceChanged &&
        !backendChanged &&
        !defaultBackendBuilderChanged &&
        !managedVaultBaseUrlChanged) {
      return;
    }

    oldWidget.authController.removeListener(_onAuthChanged);
    _disposeInjectedDependencies();
    _createInjectedDependencies();
    widget.authController.addListener(_onAuthChanged);

    _activeUid = _normalizedUid();
    if (authChanged ||
        backendChanged ||
        defaultBackendBuilderChanged ||
        managedVaultBaseUrlChanged) {
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
      final shouldRecreateInjectedDependencies = _usesManagedWebNativeBackend;
      _activeUid = nextUid;
      _resetSessionScopedState();
      if (shouldRecreateInjectedDependencies) {
        _disposeInjectedDependencies();
        _createInjectedDependencies();
      }
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
    await _syncDefaultsPriming;
    final refreshUid = expectedUid ?? _normalizedUid();
    await _subscriptionController.refresh();
    if (refreshUid != _normalizedUid()) return;
    _syncMainShellAccess();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_syncDefaultsPrimed) {
      return const SizedBox.shrink();
    }
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
      child = AppBootstrap(
        child: LockGate(
          child: WebInitialSyncGate(
            key: ValueKey<String>(
              'web-initial-sync-$uid-${widget.managedVaultBaseUrl.trim()}',
            ),
            authController: widget.authController,
            managedVaultBaseUrl: widget.managedVaultBaseUrl,
            syncConfigStore: _vaultConfigStore,
            child: AppShell(
              key: ValueKey<String>('web-main-shell-$uid'),
              initialTab: widget.entryIntent == WebEntryIntent.manage
                  ? AppTab.settings
                  : AppTab.chat,
            ),
          ),
        ),
      );
    }

    return AppPlatformCapabilityScope(
      capabilities: _appBackend is WebNativeAppBackend
          ? AppPlatformCapabilities.webNative()
          : AppPlatformCapabilities.webCloud(),
      child: AppBackendScope(
        backend: _appBackend,
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
