import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/actions/settings/actions_settings_store.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import 'ai_routing.dart';
import 'semantic_parse_auto_actions_runner.dart';
import 'semantic_parse_data_consent_prefs.dart';

class SemanticParseAutoActionsGate extends StatefulWidget {
  const SemanticParseAutoActionsGate({required this.child, super.key});

  final Widget child;

  @override
  State<SemanticParseAutoActionsGate> createState() =>
      _SemanticParseAutoActionsGateState();
}

class _SemanticParseAutoActionsGateState
    extends State<SemanticParseAutoActionsGate> with WidgetsBindingObserver {
  static const _kIdleInterval = Duration(seconds: 30);
  static const _kDrainInterval = Duration(seconds: 2);
  static const _kFailureInterval = Duration(seconds: 10);

  static const _kHardTimeout = Duration(seconds: 60);
  static const _kMinAutoConfidence = 0.86;
  static const _kBatchLimit = 5;

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
        _schedule(const Duration(milliseconds: 800));
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

    void onChange() => _schedule(const Duration(milliseconds: 800));
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

    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);

    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled =
          prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;
      if (!enabled || !mounted) {
        _schedule(_kIdleInterval);
        return;
      }

      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

      String? idToken;
      try {
        idToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        idToken = null;
      }

      AskAiRouteKind route;
      try {
        route = await decideAiAutomationRoute(
          backend,
          Uint8List.fromList(sessionKey),
          cloudIdToken: idToken,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          subscriptionStatus: subscriptionStatus,
        );
      } catch (_) {
        route = AskAiRouteKind.needsSetup;
      }

      if (!mounted) return;
      if (route == AskAiRouteKind.needsSetup) {
        _schedule(_kIdleInterval);
        return;
      }

      final settings = await ActionsSettingsStore.load();
      if (!mounted) return;

      final runner = SemanticParseAutoActionsRunner(
        store: BackendSemanticParseAutoActionsStore(
          backend: backend,
          sessionKey: Uint8List.fromList(sessionKey),
        ),
        client: BackendSemanticParseAutoActionsClient(
          backend: backend,
          sessionKey: Uint8List.fromList(sessionKey),
          route: route,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          idToken: (idToken ?? '').trim(),
          modelName: gatewayConfig.modelName,
        ),
        settings: const SemanticParseAutoActionsRunnerSettings(
          hardTimeout: _kHardTimeout,
          minAutoConfidence: _kMinAutoConfidence,
          batchLimit: _kBatchLimit,
        ),
      );

      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final result = await runner.runOnce(
        localeTag: localeTag,
        dayEndMinutes: settings.dayEndMinutes,
      );
      if (!mounted) return;

      if (result.didMutateAny) {
        syncEngine?.notifyLocalMutation();
      } else if (result.didUpdateJobs) {
        syncEngine?.notifyExternalChange();
      }

      if (!result.didUpdateJobs) {
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
