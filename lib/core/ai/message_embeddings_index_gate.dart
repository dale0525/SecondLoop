import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../session/session_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';

class MessageEmbeddingsIndexGate extends StatefulWidget {
  const MessageEmbeddingsIndexGate({required this.child, super.key});

  final Widget child;

  @override
  State<MessageEmbeddingsIndexGate> createState() =>
      _MessageEmbeddingsIndexGateState();
}

class _MessageEmbeddingsIndexGateState extends State<MessageEmbeddingsIndexGate>
    with WidgetsBindingObserver {
  static const _kIdleInterval = Duration(seconds: 30);
  static const _kDrainInterval = Duration(milliseconds: 600);
  static const _kFailureInterval = Duration(seconds: 10);
  static const _kBatchLimit = 256;

  Timer? _timer;
  DateTime? _nextRunAt;
  bool _running = false;

  SyncEngine? _syncEngine;
  VoidCallback? _syncListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachSyncEngine();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _schedule(_kDrainInterval);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
        _nextRunAt = null;
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final backend = AppBackendScope.of(context);
    if (backend is! NativeAppBackend) {
      _detachSyncEngine();
      _timer?.cancel();
      _timer = null;
      _nextRunAt = null;
      return;
    }

    _attachSyncEngine(SyncEngineScope.maybeOf(context));
    _schedule(const Duration(seconds: 2));
  }

  void _attachSyncEngine(SyncEngine? engine) {
    if (identical(engine, _syncEngine)) return;
    _detachSyncEngine();

    _syncEngine = engine;
    if (engine == null) return;

    void onChange() {
      _schedule(const Duration(milliseconds: 800));
    }

    _syncListener = onChange;
    engine.changes.addListener(onChange);
  }

  void _detachSyncEngine() {
    final engine = _syncEngine;
    final listener = _syncListener;
    if (engine != null && listener != null) {
      engine.changes.removeListener(listener);
    }
    _syncEngine = null;
    _syncListener = null;
  }

  void _schedule(Duration delay) {
    if (!mounted) return;

    final now = DateTime.now();
    final desired = now.add(delay);
    final nextRunAt = _nextRunAt;
    if (nextRunAt != null && nextRunAt.isBefore(desired)) {
      return;
    }

    _timer?.cancel();
    _nextRunAt = desired;
    _timer = Timer(delay, () {
      _nextRunAt = null;
      unawaited(_runOnce());
    });
  }

  Future<void> _runOnce() async {
    if (_running) return;
    if (!mounted) return;

    final backend = AppBackendScope.of(context);
    if (backend is! NativeAppBackend) return;
    final sessionKey = SessionScope.of(context).sessionKey;

    _running = true;
    try {
      final processed = await backend.processPendingMessageEmbeddings(
        Uint8List.fromList(sessionKey),
        limit: _kBatchLimit,
      );

      if (!mounted) return;
      if (processed <= 0) {
        _schedule(_kIdleInterval);
        return;
      }
      _schedule(_kDrainInterval);
    } catch (_) {
      if (!mounted) return;
      _schedule(_kFailureInterval);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
