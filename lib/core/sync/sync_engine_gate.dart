import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../backend/app_backend.dart';
import '../ai/ai_routing.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import 'sync_config_store.dart';
import 'sync_engine.dart';

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
  Uint8List? _sessionKey;

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
        engine.triggerPullNow();
        engine.triggerPushNow();
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
        _bytesEqual(_sessionKey, sessionKey);
    if (shouldReuse) {
      if (subscriptionStatus == SubscriptionStatus.entitled) {
        _engine?.writeGate.value = const SyncWriteGateState.open();
      }
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
      autoRunGate: _autoRunGate,
      pushDebounce: const Duration(seconds: 2),
      pullInterval: const Duration(seconds: 20),
      pullJitter: const Duration(seconds: 5),
      pullOnStart: true,
    );
    engine.start();
    engine.triggerPullNow();
    engine.triggerPushNow();

    _backendIdentity = backend;
    _sessionKey = Uint8List.fromList(sessionKey);
    _engine = engine;

    if (subscriptionStatus == SubscriptionStatus.entitled) {
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

final class _AppBackendSyncRunner implements SyncRunner {
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

  @override
  Future<int> push(SyncConfig config) async {
    return switch (config.backendType) {
      SyncBackendType.webdav => () async {
          final useMediaQueue =
              await _configStore.readCloudMediaBackupEnabled();
          if (useMediaQueue) {
            return backend.syncWebdavPushOpsOnly(
              _sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              username: config.username,
              password: config.password,
              remoteRoot: config.remoteRoot,
            );
          }
          return backend.syncWebdavPush(
            _sessionKey,
            config.syncKey,
            baseUrl: config.baseUrl ?? '',
            username: config.username,
            password: config.password,
            remoteRoot: config.remoteRoot,
          );
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
          final useMediaQueue =
              await _configStore.readCloudMediaBackupEnabled();
          if (useMediaQueue) {
            return backend.syncManagedVaultPushOpsOnly(
              _sessionKey,
              config.syncKey,
              baseUrl: config.baseUrl ?? '',
              vaultId: config.remoteRoot,
              idToken: idToken,
            );
          }
          return backend.syncManagedVaultPush(
            _sessionKey,
            config.syncKey,
            baseUrl: config.baseUrl ?? '',
            vaultId: config.remoteRoot,
            idToken: idToken,
          );
        }(),
    };
  }

  @override
  Future<int> pull(SyncConfig config) async {
    return switch (config.backendType) {
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
  }
}
