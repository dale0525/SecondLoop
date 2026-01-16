import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../backend/app_backend.dart';
import '../session/session_scope.dart';
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
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Best-effort: keep the engine running in background; on mobile the OS may suspend
        // timers anyway. Real background scheduling is handled separately.
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    final shouldReuse = identical(_backendIdentity, backend) &&
        _bytesEqual(_sessionKey, sessionKey);
    if (shouldReuse) return;

    _engine?.stop();

    final runner = _AppBackendSyncRunner(backend: backend, sessionKey: sessionKey);
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async {
        final enabled = await _configStore.readAutoEnabled();
        if (!enabled) return null;
        return _configStore.loadConfiguredSync();
      },
      pushDebounce: const Duration(seconds: 2),
      pullInterval: const Duration(seconds: 20),
      pullJitter: const Duration(seconds: 5),
      pullOnStart: true,
    );
    engine.start();

    _backendIdentity = backend;
    _sessionKey = Uint8List.fromList(sessionKey);
    _engine = engine;
  }

  bool _bytesEqual(Uint8List? a, Uint8List b) {
    if (a == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
    return context.dependOnInheritedWidgetOfExactType<SyncEngineScope>()?.engine;
  }

  @override
  bool updateShouldNotify(SyncEngineScope oldWidget) => engine != oldWidget.engine;
}

final class _AppBackendSyncRunner implements SyncRunner {
  _AppBackendSyncRunner({required this.backend, required Uint8List sessionKey})
      : _sessionKey = Uint8List.fromList(sessionKey);

  final AppBackend backend;
  final Uint8List _sessionKey;

  @override
  Future<int> push(SyncConfig config) async {
    return switch (config.backendType) {
      SyncBackendType.webdav => backend.syncWebdavPush(
          _sessionKey,
          config.syncKey,
          baseUrl: config.baseUrl ?? '',
          username: config.username,
          password: config.password,
          remoteRoot: config.remoteRoot,
        ),
      SyncBackendType.localDir => backend.syncLocaldirPush(
          _sessionKey,
          config.syncKey,
          localDir: config.localDir ?? '',
          remoteRoot: config.remoteRoot,
        ),
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
    };
  }
}
