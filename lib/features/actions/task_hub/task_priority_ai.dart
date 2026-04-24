import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../../core/ai/ai_routing.dart';
import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';
import '../../../src/rust/platform_int.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_models.dart';

abstract class TaskPriorityAiService {
  const TaskPriorityAiService();

  String get cacheScopeKey;

  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request);

  Future<Map<String, TaskPriorityAiCachedAssessment>> readSharedAssessments({
    required DateTime nowLocal,
    Duration cacheTtl = defaultTaskPriorityAiCacheTtl,
  }) async =>
      const <String, TaskPriorityAiCachedAssessment>{};

  Future<void> writeSharedAssessments({
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) async {}
}

const Duration defaultTaskPriorityAiCacheTtl = Duration(minutes: 15);

class TaskPriorityAiCachedAssessment {
  const TaskPriorityAiCachedAssessment({
    required this.entry,
    required this.requestSignature,
    required this.computedAtLocal,
  });

  final TaskPriorityAiEntry entry;
  final String requestSignature;
  final DateTime computedAtLocal;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entry': entry.toJson(),
      'request_signature': requestSignature,
      'computed_at_ms': computedAtLocal.millisecondsSinceEpoch,
    };
  }

  static TaskPriorityAiCachedAssessment? fromJson(Map<String, Object?> json) {
    final entryJson = json['entry'];
    if (entryJson is! Map) return null;
    final computedAtMs = json['computed_at_ms'];
    if (computedAtMs is! num) return null;
    return TaskPriorityAiCachedAssessment(
      entry: TaskPriorityAiEntry.fromJson(
        entryJson.map((key, value) => MapEntry(key.toString(), value)),
      ),
      requestSignature: (json['request_signature'] ?? '').toString(),
      computedAtLocal:
          DateTime.fromMillisecondsSinceEpoch(computedAtMs.toInt()),
    );
  }
}

class BackendTaskPriorityAiSharedAssessmentsClient {
  BackendTaskPriorityAiSharedAssessmentsClient({
    required AppBackend backend,
    required Uint8List sessionKey,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
    required String localeTag,
    required String cacheScopeKey,
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey),
        _gatewayBaseUrl = gatewayBaseUrl,
        _idToken = idToken,
        _modelName = modelName,
        _localeTag = localeTag.trim(),
        _cacheScopeKey = cacheScopeKey.trim();

  final AppBackend _backend;
  final Uint8List _sessionKey;
  final String _gatewayBaseUrl;
  final String _idToken;
  final String _modelName;
  final String _localeTag;
  final String _cacheScopeKey;

  String get cacheScopeKey => _cacheScopeKey;

  bool get _canUseSharedCache =>
      _idToken.trim().isNotEmpty && _cacheScopeKey.isNotEmpty;

  Future<Map<String, TaskPriorityAiCachedAssessment>> read({
    required DateTime nowLocal,
    Duration cacheTtl = defaultTaskPriorityAiCacheTtl,
  }) async {
    if (!_canUseSharedCache) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    try {
      final raw = await _backend.fetchTaskPriorityAiAssessmentsCloudGateway(
        _sessionKey,
        gatewayBaseUrl: _gatewayBaseUrl,
        idToken: _idToken,
        cacheScopeKey: _cacheScopeKey,
      );
      if (raw.trim().isEmpty) {
        return const <String, TaskPriorityAiCachedAssessment>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String, TaskPriorityAiCachedAssessment>{};
      }
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      final rawEntries = data['entries'];
      if (rawEntries is! List) {
        return const <String, TaskPriorityAiCachedAssessment>{};
      }
      final entries = <String, TaskPriorityAiCachedAssessment>{};
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map) continue;
        final entryJson =
            rawEntry.map((key, value) => MapEntry(key.toString(), value));
        final todoId = (entryJson['todo_id'] ?? '').toString().trim();
        if (todoId.isEmpty) continue;
        final computedAtMs = entryJson['computed_at_ms'];
        final parsedComputedAtMs = computedAtMs is num
            ? computedAtMs.toInt()
            : int.tryParse('${computedAtMs ?? ''}');
        if (parsedComputedAtMs == null) continue;
        final computedAtLocal =
            DateTime.fromMillisecondsSinceEpoch(parsedComputedAtMs);
        if (nowLocal.difference(computedAtLocal).abs() > cacheTtl) {
          continue;
        }
        entries[todoId] = TaskPriorityAiCachedAssessment(
          entry: TaskPriorityAiEntry.fromJson(entryJson),
          requestSignature: (entryJson['request_signature'] ?? '').toString(),
          computedAtLocal: computedAtLocal,
        );
      }
      return entries;
    } catch (_) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
  }

  Future<void> write({
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) async {
    if (!_canUseSharedCache) return;
    final activeIds = activeTodoIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final isFullSnapshot = entries.keys.toSet().containsAll(activeIds);
    final payloadEntries = <Object?>[];
    int? updatedAtMs;
    for (final entry in entries.entries) {
      if (!activeIds.contains(entry.key)) continue;
      final computedAtMs = entry.value.computedAtLocal.millisecondsSinceEpoch;
      if (updatedAtMs == null || computedAtMs > updatedAtMs) {
        updatedAtMs = computedAtMs;
      }
      payloadEntries.add(<String, Object?>{
        ...entry.value.entry.toJson(),
        'request_signature': entry.value.requestSignature,
        'computed_at_ms': computedAtMs,
      });
    }
    final resolvedUpdatedAtMs =
        updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    try {
      await _backend.upsertTaskPriorityAiAssessmentsCloudGateway(
        _sessionKey,
        gatewayBaseUrl: _gatewayBaseUrl,
        idToken: _idToken,
        cacheScopeKey: _cacheScopeKey,
        payloadJson: jsonEncode(<String, Object?>{
          'scope': _cacheScopeKey,
          'route': AskAiRouteKind.cloudGateway.name,
          'model_name': _modelName,
          'locale_tag': _localeTag,
          'replace_missing_entries': isFullSnapshot,
          'updated_at_ms': resolvedUpdatedAtMs,
          'entries': payloadEntries,
        }),
      );
    } catch (_) {
      // Ignore shared cache write failures.
    }
  }
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

bool _isUninitializedRustBridgeStateError(StateError error) {
  return error.message.toString().contains(
        'flutter_rust_bridge has not been initialized',
      );
}

String _buildTaskPriorityAiFallbackScopeKey({
  required AskAiRouteKind route,
  required String gatewayBaseUrl,
  required String modelName,
  required String localeTag,
}) {
  return buildTaskPriorityAiCacheScopeKey(
    route: route,
    gatewayBaseUrl: gatewayBaseUrl,
    modelName: modelName,
    localeTag: localeTag,
  );
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
      try {
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
      } on StateError catch (error) {
        if (!_isUninitializedRustBridgeStateError(error)) rethrow;
        return _buildTaskPriorityAiFallbackScopeKey(
          route: route,
          gatewayBaseUrl: gatewayBaseUrl,
          modelName: modelName,
          localeTag: localeTag,
        );
      } catch (_) {
        return _buildTaskPriorityAiFallbackScopeKey(
          route: route,
          gatewayBaseUrl: gatewayBaseUrl,
          modelName: modelName,
          localeTag: localeTag,
        );
      }
    case AskAiRouteKind.needsSetup:
      return null;
  }
}

Future<String> buildTaskPriorityRefreshDependencyKey(
  AppBackend backend,
  Uint8List sessionKey, {
  required SubscriptionStatus subscriptionStatus,
  required String gatewayBaseUrl,
  required String modelName,
  required String localeTag,
  String? cloudUid,
}) async {
  final cloudRouteScope = subscriptionStatus == SubscriptionStatus.entitled
      ? await resolveTaskPriorityAiCacheScopeKey(
          backend,
          sessionKey,
          route: AskAiRouteKind.cloudGateway,
          gatewayBaseUrl: gatewayBaseUrl,
          modelName: modelName,
          localeTag: localeTag,
          cloudUid: cloudUid,
        )
      : null;
  final byokScope = await resolveTaskPriorityAiCacheScopeKey(
    backend,
    sessionKey,
    route: AskAiRouteKind.byok,
    gatewayBaseUrl: gatewayBaseUrl,
    modelName: modelName,
    localeTag: localeTag,
    cloudUid: cloudUid,
  );
  return jsonEncode(<String, Object?>{
    'subscription_status': subscriptionStatus.name,
    'cloud_uid': (cloudUid ?? '').trim(),
    'gateway_base_url': gatewayBaseUrl.trim(),
    'model_name': modelName.trim(),
    'locale_tag': localeTag.trim(),
    'cloud_scope': cloudRouteScope,
    'byok_scope': byokScope,
  });
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

  String get _sharedAssessmentScopeKey {
    final override = _cacheScopeKeyOverride;
    if (override != null) {
      return override;
    }
    if (_route == AskAiRouteKind.cloudGateway) {
      return '';
    }
    return buildTaskPriorityAiCacheScopeKey(
      route: _route,
      gatewayBaseUrl: _gatewayBaseUrl,
      modelName: _modelName,
      localeTag: _localeTag,
    );
  }

  String get _rerankCacheScopeKey {
    final override = _cacheScopeKeyOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    if (_route == AskAiRouteKind.cloudGateway) {
      final normalizedIdToken = _idToken.trim();
      if (normalizedIdToken.isNotEmpty) {
        return jsonEncode(<String>[
          'cloud_ephemeral',
          _gatewayBaseUrl.trim(),
          _modelName.trim(),
          _localeTag,
          normalizedIdToken,
        ]);
      }
    }
    return buildTaskPriorityAiCacheScopeKey(
      route: _route,
      gatewayBaseUrl: _gatewayBaseUrl,
      modelName: _modelName,
      localeTag: _localeTag,
    );
  }

  BackendTaskPriorityAiSharedAssessmentsClient get _sharedAssessmentsClient =>
      BackendTaskPriorityAiSharedAssessmentsClient(
        backend: _backend,
        sessionKey: _sessionKey,
        gatewayBaseUrl: _gatewayBaseUrl,
        idToken: _idToken,
        modelName: _modelName,
        localeTag: _localeTag,
        cacheScopeKey: cacheScopeKey,
      );

  @override
  Future<Map<String, TaskPriorityAiCachedAssessment>> readSharedAssessments({
    required DateTime nowLocal,
    Duration cacheTtl = defaultTaskPriorityAiCacheTtl,
  }) async {
    if (_route != AskAiRouteKind.cloudGateway) {
      return const <String, TaskPriorityAiCachedAssessment>{};
    }
    return _sharedAssessmentsClient.read(
      nowLocal: nowLocal,
      cacheTtl: cacheTtl,
    );
  }

  @override
  Future<void> writeSharedAssessments({
    required Map<String, TaskPriorityAiCachedAssessment> entries,
    required Iterable<String> activeTodoIds,
  }) async {
    if (_route != AskAiRouteKind.cloudGateway) return;
    await _sharedAssessmentsClient.write(
      entries: entries,
      activeTodoIds: activeTodoIds,
    );
  }

  @override
  String get cacheScopeKey => _sharedAssessmentScopeKey;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
    TaskPriorityAiRequest request,
  ) async {
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
      'scope': _rerankCacheScopeKey,
      'time_bucket': buildTaskPriorityAiTimeBucket(request.nowLocal),
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
      'You are evaluating personal task candidates for a task manager.',
      'Return JSON only with shape {"entries":[{"todo_id":"...","semantic_adjustment":number,"reason":"...","confidence":"low|medium|high","is_important":true|false|null,"is_urgent":true|false|null},...]} and no prose.',
      'Evaluate each candidate independently and do not compare candidates against each other.',
      'Only emit per-candidate signals; do not emit list-level ranking instructions.',
      'Prefer stable judgments from the task itself, not transient phrasing.',
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
  int candidateLimit = 32,
}) {
  final candidates = <TaskPriorityAiCandidate>[];
  for (final entry in snapshot.activeEntries) {
    if (candidates.length >= candidateLimit) break;
    final reviewStage = platformIntToNullableInt(entry.todo.reviewStage) ?? 0;
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
        updatedAtMs: platformIntToInt(entry.todo.updatedAtMs),
        recentInteractionSummary: _recentInteractionSummary(entry, nowLocal),
        sourceSummary: entry.todo.sourceEntryId == null
            ? 'standalone task'
            : 'linked to a captured message',
        isRepeatedlyDeferred: reviewStage >= 2,
        isPotentialBlocker:
            entry.isInProgress || entry.isOverdue || entry.isDueToday,
        isQuickWin:
            entry.todo.title.trim().runes.length <= 24 && !entry.isInProgress,
        ruleIsImportant: entry.isImportant,
        ruleIsUrgent: entry.isUrgent,
      ),
    );
  }
  return TaskPriorityAiRequest(
    nowLocal: nowLocal,
    candidates: candidates,
  );
}

String _recentInteractionSummary(TaskPriorityEntry entry, DateTime nowLocal) {
  final updatedAt = DateTime.fromMillisecondsSinceEpoch(
    platformIntToInt(entry.todo.updatedAtMs),
    isUtc: true,
  ).toLocal();
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
