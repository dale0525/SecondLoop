import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../backend/app_backend.dart';
import '../ai/ai_routing.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../../features/media_backup/cloud_media_backup_runner.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';
import 'sync_http_error.dart';
import 'sync_result.dart';

final class SyncEngineGate extends StatefulWidget {
  const SyncEngineGate({required this.child, super.key});

  final Widget child;

  @override
  State<SyncEngineGate> createState() => _SyncEngineGateState();
}

final class _SyncEngineGateState extends State<SyncEngineGate>
    with WidgetsBindingObserver {
  final SyncConfigStore _configStore = SyncConfigStore();
  final Connectivity _connectivity = Connectivity();
  SyncEngine? _engine;
  Object? _backendIdentity;
  Object? _cloudAuthIdentity;
  Uint8List? _sessionKey;
  int _engineGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final engine = _engine;
    if (engine == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        engine.start();
        engine.triggerPushNow();
        engine.triggerPullNow();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Best-effort: try a last-minute push before we lose foreground time; on mobile the OS
        // may suspend timers anyway. Real background scheduling is handled separately.
        engine.triggerPushNow();
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final cloudAuth = CloudAuthScope.maybeOf(context)?.controller;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status;

    final shouldReuse = identical(_backendIdentity, backend) &&
        identical(_cloudAuthIdentity, cloudAuth) &&
        _bytesEqual(_sessionKey, sessionKey);
    if (shouldReuse) {
      _maybeReopenWriteGateForEntitledSubscription(
        engine: _engine,
        subscriptionStatus: subscriptionStatus,
      );
      return;
    }

    _engine?.stop();

    final runner = _AppBackendSyncRunner(
      backend: backend,
      configStore: _configStore,
      sessionKey: sessionKey,
      idTokenGetter: cloudAuth?.getIdToken,
    );
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: _configStore.loadConfiguredSyncIfAutoEnabled,
      syncRefreshV2EnabledProvider: _configStore.readSyncRefreshV2Enabled,
      autoRunGate: _autoRunGate,
      pushDebounce: const Duration(seconds: 2),
      pullInterval: const Duration(seconds: 20),
      pullJitter: const Duration(seconds: 5),
      pullOnStart: true,
    );
    _backendIdentity = backend;
    _cloudAuthIdentity = cloudAuth;
    _sessionKey = Uint8List.fromList(sessionKey);
    _engine = engine;
    final generation = ++_engineGeneration;
    unawaited(
      _initializeEngine(
        engine: engine,
        generation: generation,
        subscriptionStatus: subscriptionStatus,
      ),
    );
  }

  Future<void> _initializeEngine({
    required SyncEngine engine,
    required int generation,
    required SubscriptionStatus? subscriptionStatus,
  }) async {
    final config = await _configStore.loadConfiguredSyncIfAutoEnabled();
    if (!mounted ||
        !identical(_engine, engine) ||
        _engineGeneration != generation) {
      return;
    }

    if (config?.backendType == SyncBackendType.managedVault) {
      final scopeId = _configStore.backgroundSyncScopeId(config!);
      final repairRequired =
          await _configStore.readBackgroundSyncRepairRequired(
        backendType: SyncBackendType.managedVault,
        scopeId: scopeId,
      );
      if (!mounted ||
          !identical(_engine, engine) ||
          _engineGeneration != generation) {
        return;
      }
      if (repairRequired) {
        engine.writeGate.value = const SyncWriteGateState.localRepairRequired();
      }
    }

    _maybeReopenWriteGateForEntitledSubscription(
      engine: engine,
      subscriptionStatus: subscriptionStatus,
    );
    engine.start();
    engine.triggerPushNow();
    engine.triggerPullNow();
  }

  void _maybeReopenWriteGateForEntitledSubscription({
    required SyncEngine? engine,
    required SubscriptionStatus? subscriptionStatus,
  }) {
    if (engine == null || subscriptionStatus != SubscriptionStatus.entitled) {
      return;
    }
    final gateKind = engine.writeGate.value.kind;
    if (gateKind == SyncWriteGateKind.paymentRequired ||
        gateKind == SyncWriteGateKind.storageQuotaExceeded) {
      engine.writeGate.value = const SyncWriteGateState.open();
    }
  }

  bool _bytesEqual(Uint8List? a, Uint8List b) {
    if (a == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<bool> _autoRunGate() async {
    final wifiOnly = await _configStore.readAutoWifiOnly();
    if (!wifiOnly) return true;
    if (kIsWeb) return true;

    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return true;
      }
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.none)) {
        return false;
      }
      return true;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SyncEngineScope(
      engine: _engine,
      child: widget.child,
    );
  }
}

final class SyncEngineScope extends InheritedWidget {
  const SyncEngineScope({
    required this.engine,
    required super.child,
    super.key,
  });

  final SyncEngine? engine;

  static SyncEngine? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SyncEngineScope>()
        ?.engine;
  }

  @override
  bool updateShouldNotify(SyncEngineScope oldWidget) =>
      engine != oldWidget.engine;
}

final class _AppBackendSyncRunner implements SyncRunner, SyncPullResultRunner {
  _AppBackendSyncRunner({
    required this.backend,
    required SyncConfigStore configStore,
    required Uint8List sessionKey,
    required Future<String?> Function()? idTokenGetter,
  })  : _sessionKey = Uint8List.fromList(sessionKey),
        _configStore = configStore,
        _idTokenGetter = idTokenGetter;

  final AppBackend backend;
  final SyncConfigStore _configStore;
  final Uint8List _sessionKey;
  final Future<String?> Function()? _idTokenGetter;

  String _managedVaultMediaUploadScopeId(SyncConfig config) {
    if (config.backendType != SyncBackendType.managedVault) return '';
    return _configStore.cloudMediaBackupBackfillScopeId(config);
  }

  Future<bool> _readManagedVaultMediaUploadPending(SyncConfig config) {
    return _configStore.readManagedVaultMediaUploadPending(
      scopeId: _managedVaultMediaUploadScopeId(config),
    );
  }

  Future<void> _writeManagedVaultMediaUploadPending(
    SyncConfig config,
    bool pending,
  ) {
    return _configStore.writeManagedVaultMediaUploadPending(
      scopeId: _managedVaultMediaUploadScopeId(config),
      pending: pending,
    );
  }

  Future<CloudMediaBackupNetwork> _safeGetCloudMediaBackupNetwork({
    required bool wifiOnly,
  }) async {
    try {
      return await ConnectivityCloudMediaBackupNetworkProvider().call();
    } catch (_) {
      // Be conservative: if we can't determine connectivity, assume cellular so
      // Wi‑Fi only mode won't upload unexpectedly.
      return wifiOnly
          ? CloudMediaBackupNetwork.cellular
          : CloudMediaBackupNetwork.unknown;
    }
  }

  Future<void> _autoBackfillCloudMediaBackupIfNeeded(SyncConfig config) async {
    if (config.backendType == SyncBackendType.localDir) return;

    final scopeId = _configStore.cloudMediaBackupBackfillScopeId(config);
    if (scopeId.isEmpty) return;

    final alreadyDone = await _configStore.readCloudMediaBackupBackfillDone(
      scopeId: scopeId,
    );
    if (alreadyDone) return;

    await backend.backfillCloudMediaBackupImages(
      _sessionKey,
      desiredVariant: 'original',
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _configStore.writeCloudMediaBackupBackfillDone(
      scopeId: scopeId,
      done: true,
    );
  }

  Future<bool> _runCloudMediaBackupIfEnabled(SyncConfig config) async {
    if (config.backendType == SyncBackendType.localDir) return false;

    final enabled = await _configStore.readCloudMediaBackupEnabled();
    if (!enabled) return false;

    final wifiOnly = await _configStore.readCloudMediaBackupWifiOnly();

    try {
      await _autoBackfillCloudMediaBackupIfNeeded(config);
    } catch (_) {
      // Best-effort: failed backfill should not block sync.
    }

    final mediaStore = BackendCloudMediaBackupStore(
      backend: backend,
      sessionKey: _sessionKey,
    );

    CloudMediaBackupRunner? runner;
    switch (config.backendType) {
      case SyncBackendType.webdav:
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) return false;
        runner = CloudMediaBackupRunner(
          store: mediaStore,
          client: WebDavCloudMediaBackupClient(
            backend: backend,
            sessionKey: _sessionKey,
            syncKey: config.syncKey,
            baseUrl: baseUrl,
            username: config.username,
            password: config.password,
            remoteRoot: config.remoteRoot,
          ),
          settings: CloudMediaBackupRunnerSettings(
            enabled: true,
            wifiOnly: wifiOnly,
          ),
          getNetwork: () => _safeGetCloudMediaBackupNetwork(wifiOnly: wifiOnly),
        );
        break;
      case SyncBackendType.managedVault:
        final getter = _idTokenGetter;
        if (getter == null) return true;
        final idToken = await getter();
        if (idToken == null || idToken.trim().isEmpty) return true;
        final baseUrl = config.baseUrl;
        if (baseUrl == null || baseUrl.trim().isEmpty) return true;
        runner = CloudMediaBackupRunner(
          store: mediaStore,
          client: ManagedVaultCloudMediaBackupClient(
            backend: backend,
            sessionKey: _sessionKey,
            syncKey: config.syncKey,
            baseUrl: baseUrl,
            vaultId: config.remoteRoot,
            idToken: idToken,
          ),
          settings: CloudMediaBackupRunnerSettings(
            enabled: true,
            wifiOnly: wifiOnly,
          ),
          getNetwork: () => _safeGetCloudMediaBackupNetwork(wifiOnly: wifiOnly),
        );
        break;
      case SyncBackendType.localDir:
        return false;
    }

    try {
      await runner.runOnce(allowCellular: false);
    } catch (_) {
      // Best-effort: media uploads should not block normal sync.
      return config.backendType == SyncBackendType.managedVault;
    }
    if (config.backendType != SyncBackendType.managedVault) return false;
    try {
      final summary = await backend.cloudMediaBackupSummary(_sessionKey);
      return summary.pending.toInt() > 0 || summary.failed.toInt() > 0;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<int> push(SyncConfig config) async {
    return switch (config.backendType) {
      SyncBackendType.webdav => () async {
          final pushed = await backend.syncWebdavPushOpsOnly(
            _sessionKey,
            config.syncKey,
            baseUrl: config.baseUrl ?? '',
            username: config.username,
            password: config.password,
            remoteRoot: config.remoteRoot,
          );
          await _runCloudMediaBackupIfEnabled(config);
          return pushed;
        }(),
      SyncBackendType.localDir => backend.syncLocaldirPush(
          _sessionKey,
          config.syncKey,
          localDir: config.localDir ?? '',
          remoteRoot: config.remoteRoot,
        ),
      SyncBackendType.managedVault => () async {
          final getter = _idTokenGetter;
          if (getter == null) return 0;
          final idToken = await getter();
          if (idToken == null || idToken.trim().isEmpty) return 0;
          final scopeId = _configStore.backgroundSyncScopeId(config);
          try {
            final pushed = await backend.syncManagedVaultPush(
              _sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              vaultId: config.remoteRoot,
              idToken: idToken,
            );
            await _configStore.writeBackgroundSyncRepairRequired(
              false,
              backendType: SyncBackendType.managedVault,
              scopeId: scopeId,
            );
            await _configStore.writeBackgroundSyncBackoffState(
              null,
              backendType: SyncBackendType.managedVault,
              scopeId: scopeId,
            );
            await _writeManagedVaultMediaUploadPending(config, true);
            return pushed;
          } catch (error) {
            await _configStore.writeBackgroundSyncRepairRequired(
              extractSyncHttpStatusCode(error) == 400 &&
                  extractSyncErrorCode(error) == 'invalid_batch',
              backendType: SyncBackendType.managedVault,
              scopeId: scopeId,
            );
            rethrow;
          }
        }(),
    };
  }

  @override
  Future<int> pull(SyncConfig config) async {
    final applied = await switch (config.backendType) {
      SyncBackendType.webdav => backend.syncWebdavPull(
          _sessionKey,
          config.syncKey,
          baseUrl: config.baseUrl ?? '',
          username: config.username,
          password: config.password,
          remoteRoot: config.remoteRoot,
        ),
      SyncBackendType.localDir => backend.syncLocaldirPull(
          _sessionKey,
          config.syncKey,
          localDir: config.localDir ?? '',
          remoteRoot: config.remoteRoot,
        ),
      SyncBackendType.managedVault => () async {
          final getter = _idTokenGetter;
          if (getter == null) return 0;
          final idToken = await getter();
          if (idToken == null || idToken.trim().isEmpty) return 0;
          return backend.syncManagedVaultPull(
            _sessionKey,
            config.syncKey,
            baseUrl: config.baseUrl ?? '',
            vaultId: config.remoteRoot,
            idToken: idToken,
          );
        }(),
    };
    switch (config.backendType) {
      case SyncBackendType.webdav:
        await _runCloudMediaBackupIfEnabled(config);
        break;
      case SyncBackendType.managedVault:
        if (await _readManagedVaultMediaUploadPending(config)) {
          final hasPendingUploads = await _runCloudMediaBackupIfEnabled(config);
          await _writeManagedVaultMediaUploadPending(config, hasPendingUploads);
        }
        break;
      case SyncBackendType.localDir:
        break;
    }
    return applied;
  }

  @override
  Future<SyncPullResult> pullWithResult(SyncConfig config) async {
    final applied = await pull(config);
    return SyncPullResult(
      applied: applied,
      shouldRefreshUi: true,
    );
  }
}
