import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_routing.dart';
import 'embeddings_source_prefs.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_capability_auth.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import '../update/update_restart_activity.dart';

class MessageEmbeddingsIndexGate extends StatefulWidget {
  const MessageEmbeddingsIndexGate({required this.child, super.key});

  final Widget child;

  @override
  State<MessageEmbeddingsIndexGate> createState() =>
      _MessageEmbeddingsIndexGateState();
}

class _MessageEmbeddingsIndexGateState extends State<MessageEmbeddingsIndexGate>
    with WidgetsBindingObserver {
  static const _kEmbeddingsDataConsentPrefsKey = 'embeddings_data_consent_v1';
  static const _kIdleInterval = Duration(seconds: 30);
  static const _kDrainInterval = Duration(milliseconds: 600);
  static const _kFailureInterval = Duration(seconds: 10);
  static const _kBatchLimit = 256;
  static const _kLocalEmbeddingIdleReleaseMs = 180000;

  Timer? _timer;
  DateTime? _nextRunAt;
  bool _running = false;
  UpdateRestartBlockToken? _restartBlockToken;

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
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
        _nextRunAt = null;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_shouldPauseInBackground()) {
          _timer?.cancel();
          _timer = null;
          _nextRunAt = null;
        }
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

  bool _shouldPauseInBackground() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
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
    _restartBlockToken = UpdateRestartActivity.blockAiAnalysis();
    try {
      final route = await _resolveRouteForBackground(
        backend,
        sessionKey,
      );
      final keyBytes = Uint8List.fromList(sessionKey);

      int processed = 0;
      if (route == EmbeddingsSourceRouteKind.local) {
        processed = await backend.processPendingMessageEmbeddings(
          keyBytes,
          limit: _kBatchLimit,
        );
      } else {
        try {
          await backend.releaseLocalEmbeddingModelIfIdle(
            keyBytes,
            maxIdleMs: _kLocalEmbeddingIdleReleaseMs,
          );
        } catch (_) {
          // Best-effort memory cleanup in remote routes.
        }
      }

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
      _restartBlockToken?.release();
      _restartBlockToken = null;
      _running = false;
    }
  }

  Future<EmbeddingsSourceRouteKind> _resolveRouteForBackground(
    NativeAppBackend backend,
    Uint8List sessionKey,
  ) async {
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

    final cloudIdToken = await readCloudCapabilityIdToken(
      cloudAuthScope?.controller,
      mode: CloudCapabilityAuthMode.background,
    );

    final cloudAvailable = subscriptionStatus == SubscriptionStatus.entitled &&
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

    return resolveEmbeddingsSourceRoute(
      preference,
      cloudEmbeddingsSelected: cloudEmbeddingsSelected,
      cloudAvailable: cloudAvailable,
      hasByokProfile: hasByokProfile,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
