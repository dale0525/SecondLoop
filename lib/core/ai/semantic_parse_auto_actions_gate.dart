import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/actions/settings/actions_settings_store.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_capability_auth.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import '../../src/rust/db.dart';
import '../update/update_restart_activity.dart';
import 'ai_routing.dart';
import 'embeddings_data_consent_prefs.dart';
import 'embeddings_source_prefs.dart';
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
  static const _kCloudEmbeddingsModelName = 'baai/bge-m3';
  static const _kMinAutoConfidence = 0.86;
  static const _kMinAutoTagConfidence = 0.8;
  static const _kBatchLimit = 5;

  Timer? _timer;
  DateTime? _nextRunAt;
  bool _running = false;
  UpdateRestartBlockToken? _restartBlockToken;
  bool _didRecoverRunningJobs = false;
  NativeAppBackend? _recoveryBackend;
  Uint8List? _recoverySessionKey;

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
        _timer?.cancel();
        _timer = null;
        _nextRunAt = null;
        _schedule(const Duration(milliseconds: 800));
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
      _recoveryBackend = null;
      _recoverySessionKey = null;
      _didRecoverRunningJobs = false;
      _detachSyncEngine();
      _timer?.cancel();
      _timer = null;
      _nextRunAt = null;
      return;
    }

    final sessionKey = SessionScope.of(context).sessionKey;
    final didRecoveryContextChange = !identical(backend, _recoveryBackend) ||
        !_sameSessionKey(sessionKey, _recoverySessionKey);
    if (didRecoveryContextChange) {
      _recoveryBackend = backend;
      _recoverySessionKey = Uint8List.fromList(sessionKey);
      _didRecoverRunningJobs = false;
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
    final hasActiveTimer = _timer?.isActive ?? false;
    if (nextRunAt != null && hasActiveTimer && nextRunAt.isBefore(desired)) {
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
    _restartBlockToken = UpdateRestartActivity.blockAiAnalysis();
    try {
      final prefs = await SharedPreferences.getInstance();
      final didRecoverRunningJobs = await _recoverRunningSemanticParseJobs(
        backend,
        sessionKey: sessionKey,
      );
      final enabled =
          prefs.getBool(SemanticParseDataConsentPrefs.prefsKey) ?? false;
      if (!enabled || !mounted) {
        final canceled = await _cancelDueSemanticParseJobs(
          backend,
          sessionKey: sessionKey,
        );
        final didUpdateJobs = didRecoverRunningJobs || canceled;
        if (didUpdateJobs) {
          syncEngine?.notifyExternalChange();
        }
        _schedule(didUpdateJobs ? _kDrainInterval : _kIdleInterval);
        return;
      }

      final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
          SubscriptionStatus.unknown;
      final cloudAuthScope = CloudAuthScope.maybeOf(context);
      final gatewayConfig =
          cloudAuthScope?.gatewayConfig ?? CloudGatewayConfig.defaultConfig;

      final idToken = await readCloudCapabilityIdToken(
        cloudAuthScope?.controller,
        mode: CloudCapabilityAuthMode.background,
      );

      AskAiRouteKind askAiRoute;
      try {
        askAiRoute = await decideAiAutomationRoute(
          backend,
          Uint8List.fromList(sessionKey),
          cloudIdToken: idToken,
          cloudGatewayBaseUrl: gatewayConfig.baseUrl,
          subscriptionStatus: subscriptionStatus,
        );
      } catch (_) {
        askAiRoute = AskAiRouteKind.needsSetup;
      }

      if (!mounted) return;
      if (askAiRoute == AskAiRouteKind.needsSetup) {
        final canceled = await _cancelDueSemanticParseJobs(
          backend,
          sessionKey: sessionKey,
        );
        final didUpdateJobs = didRecoverRunningJobs || canceled;
        if (didUpdateJobs) {
          syncEngine?.notifyExternalChange();
        }
        _schedule(didUpdateJobs ? _kDrainInterval : _kIdleInterval);
        return;
      }

      final cloudAvailable =
          subscriptionStatus == SubscriptionStatus.entitled &&
              idToken != null &&
              idToken.trim().isNotEmpty &&
              gatewayConfig.baseUrl.trim().isNotEmpty;

      final embeddingsPreference = switch (
          (prefs.getString(EmbeddingsSourcePrefs.prefsKey) ?? '').trim()) {
        'cloud' => EmbeddingsSourcePreference.cloud,
        'byok' => EmbeddingsSourcePreference.byok,
        'local' => EmbeddingsSourcePreference.local,
        _ => EmbeddingsSourcePreference.auto,
      };
      final cloudEmbeddingsSelected =
          prefs.getBool(EmbeddingsDataConsentPrefs.prefsKey) ?? false;

      var hasByokEmbeddingsProfile = false;
      try {
        final profiles = await backend.listEmbeddingProfiles(sessionKey);
        hasByokEmbeddingsProfile = profiles.any((profile) => profile.isActive);
      } catch (_) {
        hasByokEmbeddingsProfile = false;
      }

      final embeddingsRoute = resolveEmbeddingsSourceRoute(
        embeddingsPreference,
        cloudEmbeddingsSelected: cloudEmbeddingsSelected,
        cloudAvailable: cloudAvailable,
        hasByokProfile: hasByokEmbeddingsProfile,
      );

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
          askAiRoute: askAiRoute,
          embeddingsRoute: embeddingsRoute,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          idToken: (idToken ?? '').trim(),
          modelName: gatewayConfig.modelName,
          embeddingsModelName: _kCloudEmbeddingsModelName,
        ),
        settings: const SemanticParseAutoActionsRunnerSettings(
          hardTimeout: _kHardTimeout,
          minAutoConfidence: _kMinAutoConfidence,
          minAutoTagConfidence: _kMinAutoTagConfidence,
          batchLimit: _kBatchLimit,
        ),
      );

      final localeTag = Localizations.localeOf(context).toLanguageTag();
      final firstDayOfWeekIndex =
          MaterialLocalizations.of(context).firstDayOfWeekIndex;
      final result = await runner.runOnce(
        localeTag: localeTag,
        dayEndMinutes: settings.dayEndMinutes,
        morningMinutes: settings.morningMinutes,
        firstDayOfWeekIndex: firstDayOfWeekIndex,
      );
      if (!mounted) return;

      final didUpdateJobs = didRecoverRunningJobs || result.didUpdateJobs;
      if (result.didMutateAny) {
        syncEngine?.notifyLocalMutation();
      } else if (didUpdateJobs) {
        syncEngine?.notifyExternalChange();
      }

      if (!didUpdateJobs) {
        _schedule(_kIdleInterval);
        return;
      }
      _schedule(_kDrainInterval);
    } catch (_) {
      if (!mounted) return;
      _schedule(_kFailureInterval);
    } finally {
      try {
        await backend.releaseLocalEmbeddingModelIfIdle(
          Uint8List.fromList(sessionKey),
          maxIdleMs: 180000,
        );
      } catch (_) {
        // Best-effort local model cleanup.
      }
      _restartBlockToken?.release();
      _restartBlockToken = null;
      _running = false;
    }
  }

  static bool _sameSessionKey(Uint8List current, Uint8List? previous) {
    if (previous == null || current.length != previous.length) return false;
    for (var i = 0; i < current.length; i += 1) {
      if (current[i] != previous[i]) return false;
    }
    return true;
  }

  Future<bool> _recoverRunningSemanticParseJobs(
    NativeAppBackend backend, {
    required Uint8List sessionKey,
  }) async {
    if (_didRecoverRunningJobs) return false;
    try {
      final recovered = await backend.requeueRunningSemanticParseJobs(
        Uint8List.fromList(sessionKey),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      _didRecoverRunningJobs = true;
      return recovered > 0;
    } catch (error, stackTrace) {
      debugPrint(
        'requeueRunningSemanticParseJobs failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  bool _shouldPauseInBackground() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<bool> _cancelDueSemanticParseJobs(
    NativeAppBackend backend, {
    required Uint8List sessionKey,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    List<SemanticParseJob> dueJobs;
    try {
      dueJobs = await backend.listDueSemanticParseJobs(
        Uint8List.fromList(sessionKey),
        nowMs: nowMs,
        limit: _kBatchLimit,
      );
    } catch (_) {
      return false;
    }

    var didCancelAny = false;
    for (final job in dueJobs) {
      final status = job.status.trim().toLowerCase();
      if (status == 'succeeded' || status == 'failed' || status == 'canceled') {
        continue;
      }
      final messageId = job.messageId.trim();
      if (messageId.isEmpty) continue;
      try {
        await backend.markSemanticParseJobCanceled(
          Uint8List.fromList(sessionKey),
          messageId: messageId,
          nowMs: nowMs,
        );
        didCancelAny = true;
      } catch (_) {
        continue;
      }
    }
    return didCancelAny;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
