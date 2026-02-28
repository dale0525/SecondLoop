import 'dart:async';

import 'package:flutter/widgets.dart';

import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../sync/sync_engine_gate.dart';
import 'detached_ask_recovery_service.dart';

class DetachedAskRecoveryGate extends StatefulWidget {
  const DetachedAskRecoveryGate({required this.child, super.key});

  final Widget child;

  @override
  State<DetachedAskRecoveryGate> createState() =>
      _DetachedAskRecoveryGateState();
}

class _DetachedAskRecoveryGateState extends State<DetachedAskRecoveryGate>
    with WidgetsBindingObserver {
  static const _kIdleInterval = Duration(seconds: 30);
  static const _kFailureInterval = Duration(seconds: 10);

  Timer? _timer;
  DateTime? _nextRunAt;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _schedule(const Duration(milliseconds: 300));
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
      _timer?.cancel();
      _timer = null;
      _nextRunAt = null;
      return;
    }

    _schedule(const Duration(seconds: 1));
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

    final cloudAuthScope = CloudAuthScope.maybeOf(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final gatewayBaseUrl = (cloudAuthScope?.gatewayConfig.baseUrl ?? '').trim();

    _running = true;
    try {
      final idToken = await readCloudIdTokenForBackground(
        cloudAuthScope?.controller,
      );

      final result = await DetachedAskRecoveryService.recoverIfNeeded(
        backend: backend,
        sessionKey: sessionKey,
        idToken: idToken,
        defaultGatewayBaseUrl: gatewayBaseUrl,
      );

      if (!mounted) return;
      switch (result.kind) {
        case DetachedAskRecoverOutcomeKind.none:
        case DetachedAskRecoverOutcomeKind.cleared:
          _schedule(_kIdleInterval);
          break;
        case DetachedAskRecoverOutcomeKind.waitingForAuth:
          _schedule(_kFailureInterval);
          break;
        case DetachedAskRecoverOutcomeKind.running:
          _schedule(result.pollDelay ?? const Duration(seconds: 3));
          break;
        case DetachedAskRecoverOutcomeKind.temporaryFailure:
          _schedule(_kFailureInterval);
          break;
        case DetachedAskRecoverOutcomeKind.recovered:
          syncEngine?.notifyLocalMutation();
          _schedule(const Duration(milliseconds: 500));
          break;
      }
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
