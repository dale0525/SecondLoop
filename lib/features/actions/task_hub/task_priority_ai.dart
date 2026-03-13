import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/ai/ai_routing.dart';
import '../../../core/backend/app_backend.dart';
import 'task_priority_ai_models.dart';
import 'task_priority_models.dart';

abstract interface class TaskPriorityAiService {
  Future<TaskPriorityAiBatchResult> rerank(TaskPriorityAiRequest request);
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
  BackendTaskPriorityAiService({
    required AppBackend backend,
    required Uint8List sessionKey,
    required AskAiRouteKind route,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey),
        _route = route,
        _gatewayBaseUrl = gatewayBaseUrl,
        _idToken = idToken,
        _modelName = modelName;

  factory BackendTaskPriorityAiService.forTesting({
    required AppBackend backend,
    required Uint8List sessionKey,
    required AskAiRouteKind route,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) {
    return BackendTaskPriorityAiService(
      backend: backend,
      sessionKey: sessionKey,
      route: route,
      gatewayBaseUrl: gatewayBaseUrl,
      idToken: idToken,
      modelName: modelName,
    );
  }

  final AppBackend _backend;
  final Uint8List _sessionKey;
  final AskAiRouteKind _route;
  final String _gatewayBaseUrl;
  final String _idToken;
  final String _modelName;

  @override
  Future<TaskPriorityAiBatchResult> rerank(
      TaskPriorityAiRequest request) async {
    final prompt = _buildPrompt(request);
    final response = await _collectResponse(
      _route == AskAiRouteKind.cloudGateway
          ? _backend.askAiStreamCloudGateway(
              _sessionKey,
              'loop_home',
              question: prompt,
              topK: 1,
              thisThreadOnly: true,
              gatewayBaseUrl: _gatewayBaseUrl,
              idToken: _idToken,
              modelName: _modelName,
            )
          : _backend.askAiStream(
              _sessionKey,
              'loop_home',
              question: prompt,
              topK: 1,
              thisThreadOnly: true,
            ),
    );
    return parseTaskPriorityAiBatchResult(response);
  }

  Future<String> _collectResponse(Stream<String> stream) async {
    final buffer = StringBuffer();
    await for (final chunk in stream) {
      buffer.write(chunk);
    }
    final output = buffer.toString().trim();
    if (output.isEmpty) {
      throw const FormatException('task_priority_ai_empty_response');
    }
    return output;
  }

  String _buildPrompt(TaskPriorityAiRequest request) {
    final payload = jsonEncode(request.toJson());
    return [
      'You are reranking personal task candidates for a task manager.',
      'Return JSON only with shape {"entries":[...]} and no prose.',
      'Allowed priority_band: focus | next | later.',
      'Allowed suggested_action: do_now | schedule | defer | clarify.',
      'Do not invent facts. Keep reasons short and verifiable.',
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
