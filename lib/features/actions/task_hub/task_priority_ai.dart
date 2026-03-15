import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../core/ai/ai_routing.dart';
import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_models.dart';

abstract interface class TaskPriorityAiService {
  String get cacheScopeKey;

  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request);
}

String buildTaskPriorityAiCacheScopeKey({
  required AskAiRouteKind route,
  required String gatewayBaseUrl,
  required String modelName,
  required String localeTag,
  String? partitionKey,
}) {
  final trimmedPartitionKey = partitionKey?.trim();
  return jsonEncode(<String>[
    route.name,
    gatewayBaseUrl.trim(),
    modelName.trim(),
    localeTag.trim(),
    if (trimmedPartitionKey != null && trimmedPartitionKey.isNotEmpty)
      trimmedPartitionKey,
  ]);
}

Future<String?> resolveTaskPriorityAiCacheScopeKey(
  AppBackend backend,
  Uint8List sessionKey, {
  required AskAiRouteKind route,
  required String gatewayBaseUrl,
  required String modelName,
  required String localeTag,
  String? cloudUid,
}) async {
  switch (route) {
    case AskAiRouteKind.cloudGateway:
      final uid = (cloudUid ?? '').trim();
      if (uid.isEmpty) return null;
      return buildTaskPriorityAiCacheScopeKey(
        route: route,
        gatewayBaseUrl: gatewayBaseUrl,
        modelName: modelName,
        localeTag: localeTag,
        partitionKey: 'cloud:$uid',
      );
    case AskAiRouteKind.byok:
      final profiles = await backend.listLlmProfiles(sessionKey);
      LlmProfile? activeProfile;
      for (final profile in profiles) {
        if (profile.isActive) {
          activeProfile = profile;
          break;
        }
      }
      if (activeProfile == null) return null;
      return buildTaskPriorityAiCacheScopeKey(
        route: route,
        gatewayBaseUrl: activeProfile.baseUrl ?? '',
        modelName: activeProfile.modelName,
        localeTag: localeTag,
        partitionKey: jsonEncode(<String>[
          activeProfile.id,
          activeProfile.providerType,
        ]),
      );
    case AskAiRouteKind.needsSetup:
      return null;
  }
}

Future<AskAiRouteKind> resolveTaskPriorityAiRoute(
  AppBackend backend,
  Uint8List sessionKey, {
  required String? cloudIdToken,
  required String cloudGatewayBaseUrl,
  required SubscriptionStatus subscriptionStatus,
}) {
  return decideAiAutomationRoute(
    backend,
    sessionKey,
    cloudIdToken: cloudIdToken,
    cloudGatewayBaseUrl: cloudGatewayBaseUrl,
    subscriptionStatus: subscriptionStatus,
  );
}

class BackendTaskPriorityAiService implements TaskPriorityAiService {
  static final Map<String, _TaskPriorityAiCacheEntry> _sharedCache =
      <String, _TaskPriorityAiCacheEntry>{};
  static final Map<String, Future<String>> _sharedInflight =
      <String, Future<String>>{};
  // Keep this cache short-lived: the prompt still includes `now_local_iso`, but
  // the shared cache key intentionally ignores it so near-duplicate reranks from
  // multiple pages can collapse into one upstream call.
  static const Duration _sharedCacheTtl = Duration(minutes: 1);

  @visibleForTesting
  static void clearSharedCacheForTest() {
    _sharedCache.clear();
    _sharedInflight.clear();
  }

  BackendTaskPriorityAiService({
    required AppBackend backend,
    required Uint8List sessionKey,
    required AskAiRouteKind route,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String localeTag,
    String? cacheScopeKeyOverride,
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey),
        _route = route,
        _gatewayBaseUrl = gatewayBaseUrl,
        _idToken = idToken,
        _modelName = modelName,
        _localeTag = localeTag.trim(),
        _cacheScopeKeyOverride = cacheScopeKeyOverride?.trim();

  factory BackendTaskPriorityAiService.forTesting({
    required AppBackend backend,
    required Uint8List sessionKey,
    required AskAiRouteKind route,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    String localeTag = 'en-US',
    String? cacheScopeKeyOverride,
  }) {
    return BackendTaskPriorityAiService(
      backend: backend,
      sessionKey: sessionKey,
      route: route,
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
      localeTag: localeTag,
      cacheScopeKeyOverride: cacheScopeKeyOverride,
    );
  }

  final AppBackend _backend;
  final Uint8List _sessionKey;
  final AskAiRouteKind _route;
  final String _gatewayBaseUrl;
  final String _idToken;
  final String _modelName;
  final String _localeTag;
  final String? _cacheScopeKeyOverride;

  @override
  String get cacheScopeKey =>
      _cacheScopeKeyOverride ??
      buildTaskPriorityAiCacheScopeKey(
        route: _route,
        gatewayBaseUrl: _gatewayBaseUrl,
        modelName: _modelName,
        localeTag: _localeTag,
      );

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    final cacheKey = _buildCacheKey(request);
    final response = await _resolveSharedCachedOrFreshResponse(
      cacheKey,
      () {
        final prompt = _buildPrompt(request);
        return _route == AskAiRouteKind.cloudGateway
            ? _backend.taskPriorityRerankAiCloudGateway(
                _sessionKey,
                prompt: prompt,
                gatewayBaseUrl: _gatewayBaseUrl,
                idToken: _idToken,
                modelName: _modelName,
              )
            : _backend.taskPriorityRerankAi(
                _sessionKey,
                prompt: prompt,
              );
      },
    );
    final output = response.trim();
    if (output.isEmpty) {
      throw const FormatException('task_priority_ai_empty_response');
    }
    return parseTaskPriorityAiBatchResult(output);
  }

  String _buildCacheKey(TaskPriorityAiRequest request) {
    return jsonEncode(<String, Object?>{
      'scope': cacheScopeKey,
      'candidates': request.candidates
          .map((entry) => entry.toJson())
          .toList(growable: false),
    });
  }

  Future<String> _resolveSharedCachedOrFreshResponse(
    String cacheKey,
    Future<String> Function() loader,
  ) {
    final now = DateTime.now();
    _sharedCache.removeWhere(
      (_, entry) => now.difference(entry.cachedAt) > _sharedCacheTtl,
    );

    final cached = _sharedCache[cacheKey];
    if (cached != null) {
      return Future<String>.value(cached.response);
    }

    final inflight = _sharedInflight[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = loader().then((response) {
      _sharedCache[cacheKey] = _TaskPriorityAiCacheEntry(
        response: response,
        cachedAt: DateTime.now(),
      );
      return response;
    }).whenComplete(() {
      _sharedInflight.remove(cacheKey);
    });
    _sharedInflight[cacheKey] = future;
    return future;
  }

  String _buildPrompt(TaskPriorityAiRequest request) {
    final payload = jsonEncode(request.toJson());
    return [
      'You are reranking personal task candidates for a task manager.',
      'Return JSON only with shape {"entries":[...]} and no prose.',
      'Allowed priority_band: focus | next | later.',
      'Allowed suggested_action: do_now | schedule | defer | clarify.',
      'Do not invent facts. Keep reasons short and verifiable.',
      _localeTag.isEmpty
          ? "Write the reason field in the user's current app language."
          : "Write the reason field in the user's current app language ($_localeTag).",
      'Payload:',
      payload,
    ].join('\n');
  }
}

TaskPriorityAiRequest buildTaskPriorityAiRequest(
  TaskPrioritySnapshot snapshot, {
  required DateTime nowLocal,
  int candidateLimit = 8,
}) {
  final candidates = <TaskPriorityAiCandidate>[];
  for (final entry in snapshot.activeEntries) {
    if (candidates.length >= candidateLimit) break;
    candidates.add(
      TaskPriorityAiCandidate(
        todoId: entry.todo.id,
        title: entry.todo.title,
        status: entry.todo.status,
        band: entry.band,
        dueState: entry.isOverdue
            ? 'overdue'
            : entry.isDueToday
                ? 'today'
                : entry.isFutureScheduled
                    ? 'scheduled'
                    : entry.isReviewDue
                        ? 'review_due'
                        : entry.isSnoozed
                            ? 'snoozed'
                            : 'unscheduled',
        ruleScore: entry.ruleScore,
        updatedAtMs: entry.todo.updatedAtMs,
        recentInteractionSummary: _recentInteractionSummary(entry, nowLocal),
        sourceSummary: entry.todo.sourceEntryId == null
            ? 'standalone task'
            : 'linked to a captured message',
        isRepeatedlyDeferred:
            entry.isSnoozed || ((entry.todo.reviewStage ?? 0) >= 2),
        isPotentialBlocker:
            entry.isInProgress || entry.isOverdue || entry.isDueToday,
        isQuickWin:
            entry.todo.title.trim().runes.length <= 24 && !entry.isInProgress,
      ),
    );
  }
  return TaskPriorityAiRequest(
    nowLocal: nowLocal,
    candidates: candidates,
  );
}

String _recentInteractionSummary(TaskPriorityEntry entry, DateTime nowLocal) {
  final updatedAt =
      DateTime.fromMillisecondsSinceEpoch(entry.todo.updatedAtMs, isUtc: true)
          .toLocal();
  final age = nowLocal.difference(updatedAt);
  if (age.inHours < 24) {
    return 'updated within the last day';
  }
  if (age.inDays < 7) {
    return 'updated within the last week';
  }
  return 'stale for more than a week';
}

final class _TaskPriorityAiCacheEntry {
  const _TaskPriorityAiCacheEntry({
    required this.response,
    required this.cachedAt,
  });

  final String response;
  final DateTime cachedAt;
}
