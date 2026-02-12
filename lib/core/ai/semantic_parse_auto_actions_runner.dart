import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'ai_routing.dart';
import '../../features/actions/review/review_backoff.dart';
import '../../features/actions/settings/actions_settings_store.dart';
import '../../features/actions/todo/message_action_resolver.dart';
import '../../features/actions/todo/todo_linking.dart';
import '../../src/rust/db.dart';
import '../../src/rust/semantic_parse.dart' as rust_semantic;
import '../backend/app_backend.dart';
import 'semantic_parse.dart';

final class SemanticParseAutoActionJob {
  const SemanticParseAutoActionJob({
    required this.messageId,
    required this.status,
    required this.attempts,
    required this.nextRetryAtMs,
    required this.createdAtMs,
  });

  final String messageId;
  final String status;
  final int attempts;
  final int? nextRetryAtMs;
  final int createdAtMs;
}

final class SemanticParseTodoCandidate {
  const SemanticParseTodoCandidate({
    required this.id,
    required this.title,
    required this.status,
    this.dueLocalIso,
  });

  final String id;
  final String title;
  final String status;
  final String? dueLocalIso;
}

final class SemanticParseJobSucceededArgs {
  const SemanticParseJobSucceededArgs({
    required this.messageId,
    required this.appliedActionKind,
    this.appliedTodoId,
    this.appliedTodoTitle,
    this.appliedPrevTodoStatus,
    required this.nowMs,
  });

  final String messageId;
  final String appliedActionKind; // create | followup | none
  final String? appliedTodoId;
  final String? appliedTodoTitle;
  final String? appliedPrevTodoStatus;
  final int nowMs;
}

final class SemanticParseJobFailedArgs {
  const SemanticParseJobFailedArgs({
    required this.messageId,
    required this.attempts,
    required this.nextRetryAtMs,
    required this.error,
    required this.nowMs,
  });

  final String messageId;
  final int attempts;
  final int nextRetryAtMs;
  final String error;
  final int nowMs;
}

abstract class SemanticParseAutoActionsStore {
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  });

  Future<String?> getMessageText(String messageId);

  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
  });

  Future<void> markJobRunning({
    required String messageId,
    required int nowMs,
  });

  Future<void> markJobSucceeded(SemanticParseJobSucceededArgs args);

  Future<void> markJobFailed(SemanticParseJobFailedArgs args);

  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  });

  Future<void> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
  });

  /// Returns the previous status when available (for Undo).
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
  });
}

abstract class SemanticParseAutoActionsClient {
  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required Duration timeout,
  });
}

final class SemanticParseAutoActionsRunnerSettings {
  const SemanticParseAutoActionsRunnerSettings({
    required this.hardTimeout,
    required this.minAutoConfidence,
    this.batchLimit = 5,
  });

  final Duration hardTimeout;
  final double minAutoConfidence;
  final int batchLimit;
}

final class SemanticParseAutoActionsRunResult {
  const SemanticParseAutoActionsRunResult({
    required this.processed,
    required this.didMutateAny,
    required this.didUpdateJobs,
  });

  final int processed;
  final bool didMutateAny;
  final bool didUpdateJobs;
}

typedef SemanticParseNowMs = int Function();
typedef SemanticParseNowLocal = DateTime Function();

final class SemanticParseAutoActionsRunner {
  SemanticParseAutoActionsRunner({
    required this.store,
    required this.client,
    required this.settings,
    SemanticParseNowMs? nowMs,
    SemanticParseNowLocal? nowLocal,
  })  : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _nowLocal = nowLocal ?? (() => DateTime.now());

  final SemanticParseAutoActionsStore store;
  final SemanticParseAutoActionsClient client;
  final SemanticParseAutoActionsRunnerSettings settings;
  final SemanticParseNowMs _nowMs;
  final SemanticParseNowLocal _nowLocal;

  Future<SemanticParseAutoActionsRunResult> runOnce({
    required String localeTag,
    required int dayEndMinutes,
  }) async {
    final nowMs = _nowMs();
    final nowLocal = _nowLocal();
    final jobs = await store.listDueJobs(
      nowMs: nowMs,
      limit: settings.batchLimit,
    );

    var processed = 0;
    var didMutateAny = false;
    var didUpdateJobs = false;

    for (final job in jobs) {
      // Treat `running` as recoverable: if the app was force-killed mid-run,
      // the persisted job would remain `running` and should be retried on the
      // next launch.
      if (job.status != 'pending' &&
          job.status != 'failed' &&
          job.status != 'running') {
        continue;
      }

      final messageText = (await store.getMessageText(job.messageId))?.trim();
      if (messageText == null || messageText.isEmpty) {
        await store.markJobCanceled(messageId: job.messageId, nowMs: nowMs);
        didUpdateJobs = true;
        continue;
      }

      try {
        await store.markJobRunning(messageId: job.messageId, nowMs: nowMs);
        didUpdateJobs = true;

        final candidates = await store.listOpenTodoCandidates(
          query: messageText,
          nowLocal: nowLocal,
          limit: 8,
        );

        final json = await client
            .parseMessageActionJson(
              text: messageText,
              nowLocalIso: nowLocal.toIso8601String(),
              localeTag: localeTag,
              dayEndMinutes: dayEndMinutes,
              candidates: candidates,
              timeout: settings.hardTimeout,
            )
            .timeout(settings.hardTimeout);

        final parsed = AiSemanticParse.tryParseMessageAction(
          json,
          nowLocal: nowLocal,
          locale: _localeFromTag(localeTag),
          dayEndMinutes: dayEndMinutes,
        );

        if (parsed == null) {
          throw StateError('invalid_json');
        }

        if (parsed.confidence < settings.minAutoConfidence) {
          await store.markJobSucceeded(
            SemanticParseJobSucceededArgs(
              messageId: job.messageId,
              appliedActionKind: 'none',
              appliedTodoId: null,
              appliedTodoTitle: null,
              appliedPrevTodoStatus: null,
              nowMs: nowMs,
            ),
          );
          didUpdateJobs = true;
          continue;
        }

        switch (parsed.decision) {
          case MessageActionCreateDecision(
              :final title,
              :final status,
              :final dueAtLocal,
              :final recurrenceRule,
            ):
            await store.upsertTodoFromMessage(
              messageId: job.messageId,
              title: title,
              status: status,
              dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
              recurrenceRuleJson: recurrenceRule?.toJsonString(),
            );
            await store.markJobSucceeded(
              SemanticParseJobSucceededArgs(
                messageId: job.messageId,
                appliedActionKind: 'create',
                appliedTodoId: 'todo:${job.messageId}',
                appliedTodoTitle: title,
                appliedPrevTodoStatus: null,
                nowMs: nowMs,
              ),
            );
            didUpdateJobs = true;
            processed += 1;
            didMutateAny = true;
            break;
          case MessageActionFollowUpDecision(
              :final todoId,
              :final newStatus,
            ):
            final previousStatus = await store.setTodoStatusFromMessage(
              messageId: job.messageId,
              todoId: todoId,
              newStatus: newStatus,
            );

            final candidateTitle = candidates
                .where((c) => c.id == todoId)
                .map((c) => c.title)
                .cast<String?>()
                .firstWhere((_) => true, orElse: () => null);

            await store.markJobSucceeded(
              SemanticParseJobSucceededArgs(
                messageId: job.messageId,
                appliedActionKind: 'followup',
                appliedTodoId: todoId,
                appliedTodoTitle: candidateTitle,
                appliedPrevTodoStatus: previousStatus,
                nowMs: nowMs,
              ),
            );
            didUpdateJobs = true;
            processed += 1;
            didMutateAny = true;
            break;
          case MessageActionNoneDecision():
            await store.markJobSucceeded(
              SemanticParseJobSucceededArgs(
                messageId: job.messageId,
                appliedActionKind: 'none',
                appliedTodoId: null,
                appliedTodoTitle: null,
                appliedPrevTodoStatus: null,
                nowMs: nowMs,
              ),
            );
            didUpdateJobs = true;
            break;
        }
      } catch (e) {
        final attempts = job.attempts + 1;
        final nextRetryAtMs = nowMs + _retryBackoffMs(attempts);
        await store.markJobFailed(
          SemanticParseJobFailedArgs(
            messageId: job.messageId,
            attempts: attempts,
            nextRetryAtMs: nextRetryAtMs,
            error: e.toString(),
            nowMs: nowMs,
          ),
        );
        didUpdateJobs = true;
      }
    }

    return SemanticParseAutoActionsRunResult(
      processed: processed,
      didMutateAny: didMutateAny,
      didUpdateJobs: didUpdateJobs,
    );
  }

  static Locale _localeFromTag(String tag) {
    final normalized = tag.trim();
    if (normalized.isEmpty) return const Locale('en');
    final parts = normalized.split(RegExp(r'[-_]'));
    final language = parts.isNotEmpty ? parts[0] : 'en';
    final country = parts.length > 1 ? parts[1] : null;
    return Locale(language, country);
  }

  static int _retryBackoffMs(int attempts) {
    switch (attempts.clamp(1, 6)) {
      case 1:
        return const Duration(seconds: 30).inMilliseconds;
      case 2:
        return const Duration(minutes: 2).inMilliseconds;
      case 3:
        return const Duration(minutes: 10).inMilliseconds;
      case 4:
        return const Duration(minutes: 30).inMilliseconds;
      case 5:
        return const Duration(hours: 2).inMilliseconds;
      default:
        return const Duration(hours: 8).inMilliseconds;
    }
  }
}

final class BackendSemanticParseAutoActionsStore
    implements SemanticParseAutoActionsStore {
  BackendSemanticParseAutoActionsStore({
    required AppBackend backend,
    required Uint8List sessionKey,
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey);

  final AppBackend _backend;
  final Uint8List _sessionKey;

  @override
  Future<List<SemanticParseAutoActionJob>> listDueJobs({
    required int nowMs,
    int limit = 5,
  }) async {
    final rows = await _backend.listDueSemanticParseJobs(
      _sessionKey,
      nowMs: nowMs,
      limit: limit,
    );
    return rows
        .map(
          (r) => SemanticParseAutoActionJob(
            messageId: r.messageId,
            status: r.status,
            attempts: r.attempts.toInt(),
            nextRetryAtMs: r.nextRetryAtMs?.toInt(),
            createdAtMs: r.createdAtMs.toInt(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String?> getMessageText(String messageId) async {
    final msg = await _backend.getMessageById(_sessionKey, messageId);
    return msg?.content;
  }

  @override
  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
  }) async {
    final todos = await _backend.listTodos(_sessionKey);
    final targets = <TodoLinkTarget>[];
    for (final todo in todos) {
      if (todo.status == 'done' || todo.status == 'dismissed') continue;
      final dueMs = todo.dueAtMs;
      targets.add(
        TodoLinkTarget(
          id: todo.id,
          title: todo.title,
          status: todo.status,
          dueLocal: dueMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  dueMs,
                  isUtc: true,
                ).toLocal(),
        ),
      );
    }

    final ranked = rankTodoCandidates(
      query,
      targets,
      nowLocal: nowLocal,
      limit: limit,
    );

    final out = <SemanticParseTodoCandidate>[];
    for (final c in ranked) {
      final dueIso = c.target.dueLocal?.toIso8601String();
      out.add(
        SemanticParseTodoCandidate(
          id: c.target.id,
          title: c.target.title,
          status: c.target.status,
          dueLocalIso: dueIso,
        ),
      );
    }
    return out;
  }

  @override
  Future<void> markJobRunning({
    required String messageId,
    required int nowMs,
  }) async {
    await _backend.markSemanticParseJobRunning(
      _sessionKey,
      messageId: messageId,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> markJobSucceeded(SemanticParseJobSucceededArgs args) async {
    await _backend.markSemanticParseJobSucceeded(
      _sessionKey,
      messageId: args.messageId,
      appliedActionKind: args.appliedActionKind,
      appliedTodoId: args.appliedTodoId,
      appliedTodoTitle: args.appliedTodoTitle,
      appliedPrevTodoStatus: args.appliedPrevTodoStatus,
      nowMs: args.nowMs,
    );
  }

  @override
  Future<void> markJobFailed(SemanticParseJobFailedArgs args) async {
    await _backend.markSemanticParseJobFailed(
      _sessionKey,
      messageId: args.messageId,
      attempts: args.attempts,
      nextRetryAtMs: args.nextRetryAtMs,
      lastError: args.error,
      nowMs: args.nowMs,
    );
  }

  @override
  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  }) async {
    await _backend.markSemanticParseJobCanceled(
      _sessionKey,
      messageId: messageId,
      nowMs: nowMs,
    );
  }

  @override
  Future<void> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
  }) async {
    var normalizedStatus = status.trim();
    if (normalizedStatus.isEmpty) {
      normalizedStatus = dueAtMs == null ? 'inbox' : 'open';
    }

    // Align with capture-todo flow: scheduled todos are open; unscheduled todos
    // enter the review queue.
    if (dueAtMs != null && normalizedStatus == 'inbox') {
      normalizedStatus = 'open';
    }

    int? reviewStage;
    int? nextReviewAtMs;
    if (dueAtMs == null &&
        normalizedStatus != 'done' &&
        normalizedStatus != 'dismissed') {
      final settings = await ActionsSettingsStore.load();
      final nextLocal = ReviewBackoff.initialNextReviewAt(
        DateTime.now(),
        settings,
      );
      reviewStage = 0;
      nextReviewAtMs = nextLocal.toUtc().millisecondsSinceEpoch;
    }

    final todoId = 'todo:$messageId';
    await _backend.upsertTodo(
      _sessionKey,
      id: todoId,
      title: title,
      dueAtMs: dueAtMs,
      status: normalizedStatus,
      sourceEntryId: messageId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
    );

    final normalizedRule = recurrenceRuleJson?.trim();
    if (normalizedRule != null && normalizedRule.isNotEmpty) {
      await _backend.upsertTodoRecurrence(
        _sessionKey,
        todoId: todoId,
        seriesId: 'series:$messageId',
        ruleJson: normalizedRule,
      );
    }
  }

  @override
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
  }) async {
    final todos = await _backend.listTodos(_sessionKey);
    final existing =
        todos.where((t) => t.id == todoId).cast<Todo?>().firstWhere(
              (_) => true,
              orElse: () => null,
            );
    final prev = existing?.status;
    await _backend.setTodoStatus(
      _sessionKey,
      todoId: todoId,
      newStatus: newStatus,
      sourceMessageId: messageId,
    );
    return prev;
  }
}

final class BackendSemanticParseAutoActionsClient
    implements SemanticParseAutoActionsClient {
  BackendSemanticParseAutoActionsClient({
    required AppBackend backend,
    required Uint8List sessionKey,
    required this.route,
    required this.gatewayBaseUrl,
    required this.idToken,
    required this.modelName,
    this.forceCandidatesLimit = 8,
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey);

  final AppBackend _backend;
  final Uint8List _sessionKey;

  final AskAiRouteKind route;
  final String gatewayBaseUrl;
  final String idToken;
  final String modelName;
  final int forceCandidatesLimit;

  @override
  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required Duration timeout,
  }) async {
    final locale = SemanticParseAutoActionsRunner._localeFromTag(localeTag);
    final rustCandidates = candidates
        .take(forceCandidatesLimit)
        .map(
          (c) => rust_semantic.TodoCandidate(
            id: c.id,
            title: c.title,
            status: c.status,
            dueLocalIso: c.dueLocalIso,
          ),
        )
        .toList(growable: false);

    final future = route == AskAiRouteKind.cloudGateway
        ? _backend.semanticParseMessageActionCloudGateway(
            _sessionKey,
            text: text,
            nowLocalIso: nowLocalIso,
            locale: locale,
            dayEndMinutes: dayEndMinutes,
            candidates: rustCandidates,
            gatewayBaseUrl: gatewayBaseUrl,
            idToken: idToken,
            modelName: modelName,
          )
        : _backend.semanticParseMessageAction(
            _sessionKey,
            text: text,
            nowLocalIso: nowLocalIso,
            locale: locale,
            dayEndMinutes: dayEndMinutes,
            candidates: rustCandidates,
          );

    return future.timeout(timeout);
  }
}
