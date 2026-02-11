import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_routing.dart';
import 'embeddings_source_prefs.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';

class EmbeddingsIndexGate extends StatefulWidget {
  const EmbeddingsIndexGate({required this.child, super.key});

  final Widget child;

  @override
  State<EmbeddingsIndexGate> createState() => _EmbeddingsIndexGateState();
}

class _EmbeddingsIndexGateState extends State<EmbeddingsIndexGate>
    with WidgetsBindingObserver {
  static const _kEmbeddingsDataConsentPrefsKey = 'embeddings_data_consent_v1';
  static const _kCloudEmbeddingsModelName = 'baai/bge-m3';

  static const _kTodoBatchLimitLocal = 16;
  static const _kActivityBatchLimitLocal = 32;
  static const _kTodoBatchLimitRemote = 8;
  static const _kActivityBatchLimitRemote = 16;

  static const _kIdleInterval = Duration(seconds: 30);
  static const _kDrainIntervalLocal = Duration(milliseconds: 600);
  static const _kDrainIntervalRemote = Duration(seconds: 2);
  static const _kFailureInterval = Duration(seconds: 10);

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
        _schedule(const Duration(milliseconds: 600));
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
      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final cloudGatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

      final prefs = await SharedPreferences.getInstance();
      final cloudEmbeddingsSelected =
          prefs.getBool(_kEmbeddingsDataConsentPrefsKey) ?? false;

      final preference = switch (
          (prefs.getString(EmbeddingsSourcePrefs.prefsKey) ?? '').trim()) {
        'cloud' => EmbeddingsSourcePreference.cloud,
        'byok' => EmbeddingsSourcePreference.byok,
        'local' => EmbeddingsSourcePreference.local,
        _ => EmbeddingsSourcePreference.auto,
      };

      String? cloudIdToken;
      try {
        cloudIdToken = await cloudAuthScope?.controller.getIdToken();
      } catch (_) {
        cloudIdToken = null;
      }

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              cloudIdToken != null &&
              cloudIdToken.trim().isNotEmpty &&
              cloudGatewayConfig.baseUrl.trim().isNotEmpty;

      var hasByokProfile = false;
      try {
        final profiles = await backend.listEmbeddingProfiles(sessionKey);
        hasByokProfile = profiles.any((p) => p.isActive);
      } catch (_) {
        hasByokProfile = false;
      }

      final route = resolveEmbeddingsSourceRoute(
        preference,
        cloudEmbeddingsSelected: cloudEmbeddingsSelected,
        cloudAvailable: cloudAvailable,
        hasByokProfile: hasByokProfile,
      );

      final result = await _processBatch(
        backend,
        sessionKey,
        route: route,
        hasByokProfile: hasByokProfile,
        cloudAvailable: cloudAvailable,
        cloudIdToken: cloudIdToken,
        cloudGatewayBaseUrl: cloudGatewayConfig.baseUrl,
      );

      if (!mounted) return;
      if (result.processed <= 0) {
        _schedule(_kIdleInterval);
        return;
      }
      _schedule(result.isRemote ? _kDrainIntervalRemote : _kDrainIntervalLocal);
    } catch (_) {
      if (!mounted) return;
      _schedule(_kFailureInterval);
    } finally {
      _running = false;
    }
  }

  Future<_IndexBatchResult> _processBatch(
    AppBackend backend,
    Uint8List sessionKey, {
    required EmbeddingsSourceRouteKind route,
    required bool hasByokProfile,
    required bool cloudAvailable,
    required String? cloudIdToken,
    required String cloudGatewayBaseUrl,
  }) async {
    Future<_IndexBatchResult> processCloud() async {
      final processed =
          await backend.processPendingTodoThreadEmbeddingsCloudGateway(
        sessionKey,
        todoLimit: _kTodoBatchLimitRemote,
        activityLimit: _kActivityBatchLimitRemote,
        gatewayBaseUrl: cloudGatewayBaseUrl,
        idToken: cloudIdToken ?? '',
        modelName: _kCloudEmbeddingsModelName,
      );
      return _IndexBatchResult(processed: processed, isRemote: true);
    }

    Future<_IndexBatchResult> processLocal() async {
      final processed = await backend.processPendingTodoThreadEmbeddings(
        sessionKey,
        todoLimit: _kTodoBatchLimitLocal,
        activityLimit: _kActivityBatchLimitLocal,
      );
      return _IndexBatchResult(processed: processed, isRemote: false);
    }

    Future<_IndexBatchResult> processByokWithFallback() async {
      try {
        final processed = await backend.processPendingTodoThreadEmbeddingsBrok(
          sessionKey,
          todoLimit: _kTodoBatchLimitRemote,
          activityLimit: _kActivityBatchLimitRemote,
        );
        return _IndexBatchResult(processed: processed, isRemote: true);
      } catch (_) {
        return processLocal();
      }
    }

    switch (route) {
      case EmbeddingsSourceRouteKind.cloudGateway:
        if (cloudAvailable) {
          try {
            return await processCloud();
          } catch (_) {
            if (hasByokProfile) {
              return processByokWithFallback();
            }
            return processLocal();
          }
        }
        if (hasByokProfile) {
          return processByokWithFallback();
        }
        return processLocal();
      case EmbeddingsSourceRouteKind.byok:
        if (hasByokProfile) {
          return processByokWithFallback();
        }
        return processLocal();
      case EmbeddingsSourceRouteKind.local:
        return processLocal();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _IndexBatchResult {
  const _IndexBatchResult({required this.processed, required this.isRemote});

  final int processed;
  final bool isRemote;
}
