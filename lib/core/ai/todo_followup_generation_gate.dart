import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/actions/settings/actions_settings_store.dart';
import '../backend/app_backend.dart';
import '../backend/native_backend.dart';
import '../cloud/cloud_capability_auth.dart';
import '../cloud/cloud_auth_controller.dart';
import '../cloud/cloud_auth_scope.dart';
import '../session/session_scope.dart';
import '../subscription/subscription_scope.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_gate.dart';
import '../update/update_restart_activity.dart';
import '../../src/rust/db.dart';
import 'ai_routing.dart';
import 'semantic_parse_data_consent_prefs.dart';
import 'todo_followup_generation_capability.dart';
import 'todo_followup_generation_runner.dart';
import 'todo_followup_suggestions_ai.dart';

Future<String?> prepareTodoFollowupGenerationIdToken(
  CloudAuthController? controller, {
  required SubscriptionStatus subscriptionStatus,
  required String gatewayBaseUrl,
  bool forceWarm = false,
}) async {
  final normalizedGatewayBaseUrl = gatewayBaseUrl.trim();
  final shouldWarm = normalizedGatewayBaseUrl.isNotEmpty &&
      (subscriptionStatus == SubscriptionStatus.entitled || forceWarm);
  if (shouldWarm) {
    await bestEffortWarmCloudCapabilityAuth(controller);
  }

  return readCloudCapabilityIdToken(
    controller,
    mode: CloudCapabilityAuthMode.background,
  );
}

class TodoFollowupGenerationGate extends StatefulWidget {
  const TodoFollowupGenerationGate({required this.child, super.key});

  final Widget child;

  @override
  State<TodoFollowupGenerationGate> createState() =>
      _TodoFollowupGenerationGateState();
}

class _TodoFollowupGenerationGateState extends State<TodoFollowupGenerationGate>
    with WidgetsBindingObserver {
  static const _kIdleInterval = Duration(seconds: 30);
  static const _kDrainInterval = Duration(seconds: 2);
  static const _kFailureInterval = Duration(seconds: 10);
  static const _kHardTimeout = Duration(seconds: 45);
  static const _kBatchLimit = 5;

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
    if (_running || !mounted) return;

    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) return;
    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final localeTag = Localizations.localeOf(context).toLanguageTag();

    _running = true;
    _restartBlockToken = UpdateRestartActivity.blockAiAnalysis();
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
      final previewJobs = await backend.listDueTodoFollowupGenerationJobs(
        Uint8List.fromList(sessionKey),
        nowMs: DateTime.now().millisecondsSinceEpoch,
        limit: _kBatchLimit,
      );
      final hasManualRegenerateDueJob = previewJobs.any(
        (job) => job.triggerKind == 'manual_regenerate',
      );

      final idToken = await prepareTodoFollowupGenerationIdToken(
        cloudAuthScope?.controller,
        subscriptionStatus: subscriptionStatus,
        gatewayBaseUrl: gatewayConfig.baseUrl,
        forceWarm: hasManualRegenerateDueJob,
      );
      final route = await decideTodoFollowupGenerationRoute(
        backend,
        Uint8List.fromList(sessionKey),
        hasManualRegenerateDueJob: hasManualRegenerateDueJob,
        cloudIdToken: idToken,
        cloudGatewayBaseUrl: gatewayConfig.baseUrl,
        subscriptionStatus: subscriptionStatus,
      );
      if (route == AskAiRouteKind.needsSetup) {
        _schedule(_kIdleInterval);
        return;
      }

      await ActionsSettingsStore.load();

      final runner = TodoFollowupGenerationRunner(
        store: _BackendTodoFollowupGenerationStore(
          backend: backend,
          sessionKey: Uint8List.fromList(sessionKey),
        ),
        client: _BackendTodoFollowupGenerationClient(
          backend: backend,
          sessionKey: Uint8List.fromList(sessionKey),
          route: route,
          gatewayBaseUrl: gatewayConfig.baseUrl,
          idToken: idToken ?? '',
          modelName: gatewayConfig.modelName,
          source: route == AskAiRouteKind.cloudGateway ? 'cloud' : 'byok',
          supportsWebSearch: supportsTodoFollowupWebSearch(
            route: route,
            gatewayConfig: gatewayConfig,
          ),
        ),
        settings: const TodoFollowupGenerationRunnerSettings(
          hardTimeout: _kHardTimeout,
          batchLimit: _kBatchLimit,
        ),
      );

      final result = await runner.runOnce(localeTag: localeTag);
      if (result.didMutateAny) {
        syncEngine?.notifyExternalChange();
      }
      _schedule(result.didUpdateJobs ? _kDrainInterval : _kIdleInterval);
    } catch (_) {
      _schedule(_kFailureInterval);
    } finally {
      _restartBlockToken?.release();
      _restartBlockToken = null;
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _BackendTodoFollowupGenerationStore
    implements TodoFollowupGenerationStore {
  const _BackendTodoFollowupGenerationStore({
    required this.backend,
    required this.sessionKey,
  });

  final AppBackend backend;
  final Uint8List sessionKey;

  @override
  Future<Todo?> getTodo(String todoId) {
    return backend.getTodoById(sessionKey, todoId);
  }

  @override
  Future<void> dismissTodoFollowupSuggestions({
    required String todoId,
    required List<String> suggestionIds,
  }) {
    return backend.dismissTodoFollowupSuggestions(
      sessionKey,
      todoId: todoId,
      suggestionIds: suggestionIds,
    );
  }

  @override
  Future<List<TodoActivity>> listTodoActivities(String todoId) {
    return backend.listTodoActivities(sessionKey, todoId);
  }

  @override
  Future<List<TodoFollowupGenerationJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) {
    return backend.listDueTodoFollowupGenerationJobs(
      sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
  }

  @override
  Future<List<TodoFollowupSuggestion>> listTodoFollowupSuggestions(
    String todoId,
  ) {
    return backend.listTodoFollowupSuggestions(sessionKey, todoId);
  }

  @override
  Future<void> markJobCanceled({
    required String todoId,
    required int nowMs,
  }) {
    return backend.markTodoFollowupGenerationJobCanceled(
      sessionKey,
      todoId: todoId,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markJobFailed({
    required String todoId,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) {
    return backend.markTodoFollowupGenerationJobFailed(
      sessionKey,
      todoId: todoId,
      attempts: attempts,
      nextRetryAtMs: nextRetryAtMs,
      lastError: lastError,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markJobRunning({
    required String todoId,
    required int nowMs,
  }) {
    return backend.markTodoFollowupGenerationJobRunning(
      sessionKey,
      todoId: todoId,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markJobSkipped({
    required String todoId,
    required int nowMs,
  }) {
    return backend.markTodoFollowupGenerationJobSkipped(
      sessionKey,
      todoId: todoId,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markJobSucceeded({
    required String todoId,
    required int nowMs,
  }) {
    return backend.markTodoFollowupGenerationJobSucceeded(
      sessionKey,
      todoId: todoId,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> upsertGeneratedTodoFollowupSuggestions({
    required String todoId,
    required List<TodoFollowupSuggestionDraftInput> suggestions,
    required String source,
    String? generationKey,
  }) {
    return backend.upsertGeneratedTodoFollowupSuggestions(
      sessionKey,
      todoId: todoId,
      suggestions: suggestions,
      source: source,
      generationKey: generationKey,
    );
  }
}

final class _BackendTodoFollowupGenerationClient
    implements TodoFollowupGenerationClient {
  const _BackendTodoFollowupGenerationClient({
    required this.backend,
    required this.sessionKey,
    required this.route,
    required this.gatewayBaseUrl,
    required this.idToken,
    required this.modelName,
    required this.source,
    required this.supportsWebSearch,
  });

  final AppBackend backend;
  final Uint8List sessionKey;
  final AskAiRouteKind route;
  final String gatewayBaseUrl;
  final String idToken;
  final String modelName;

  @override
  final String source;

  @override
  final bool supportsWebSearch;

  @override
  Future<TodoFollowupSuggestionDraft?> generate({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    required TodoFollowupGenerationMode generationMode,
    required List<String> manualFollowups,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  }) {
    return requestTodoFollowupSuggestion(
      backend: backend,
      sessionKey: sessionKey,
      route: route,
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
      taskTitle: taskTitle,
      taskContext: taskContext,
      localeTag: localeTag,
      generationMode: generationMode,
      manualFollowups: manualFollowups,
      status: status,
      dueAtMs: dueAtMs,
      timeout: timeout,
    );
  }
}
