import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'ai_routing.dart';
import 'embeddings_source_prefs.dart';
import 'semantic_parse_edit_policy.dart';
import 'local_semantic_parse_result.dart';
import 'local_semantic_parser.dart';
import 'todo_followup_task_classifier.dart';
import 'todo_checklist_suggestions_ai.dart';
import '../../features/actions/review/review_backoff.dart';
import '../../features/actions/settings/actions_settings_store.dart';
import '../../features/actions/todo/message_action_resolver.dart';
import '../../features/actions/todo/todo_thread_match.dart';
import '../../features/actions/todo/todo_linking.dart';
import '../../features/tags/tag_repository.dart';
import '../../src/rust/db.dart';
import '../../src/rust/semantic_parse.dart' as rust_semantic;
import '../backend/app_backend.dart';
import '../backend/attachments_backend.dart';
import '../backend/native_backend.dart';
import '../backend/semantic_parse_attempt_aware_backend.dart';
import '../backend/semantic_parse_enhancement_backend.dart';
import '../secretary/internal_tool_registry.dart';
import 'semantic_parse.dart';

part 'semantic_parse_auto_actions_runner_store.dart';
part 'semantic_parse_auto_actions_runner_client.dart';
part 'semantic_parse_auto_actions_runner_parse_policy.dart';

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

final class SemanticParseMessageInput {
  const SemanticParseMessageInput({
    required this.sourceText,
    required this.analysisText,
    required this.allowCreate,
  });

  final String sourceText;
  final String analysisText;
  final bool allowCreate;
}

final class SemanticParseJobSucceededArgs {
  const SemanticParseJobSucceededArgs({
    required this.messageId,
    required this.appliedActionKind,
    this.appliedTodoId,
    this.appliedTodoTitle,
    this.appliedPrevTodoStatus,
    this.suggestedTags,
    this.suggestedTagConfidence,
    this.tagSuggestionState,
    this.appliedTagIds,
    required this.nowMs,
  });

  final String messageId;
  final String appliedActionKind; // create | followup | none
  final String? appliedTodoId;
  final String? appliedTodoTitle;
  final String? appliedPrevTodoStatus;
  final List<String>? suggestedTags;
  final double? suggestedTagConfidence;
  final String? tagSuggestionState; // pending | applied | dismissed | none
  final List<String>? appliedTagIds;
  final int nowMs;
}

final class SemanticParseTagApplyResult {
  const SemanticParseTagApplyResult({
    required this.appliedCount,
    required this.appliedTagIds,
  });

  final int appliedCount;
  final List<String> appliedTagIds;
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

  Future<SemanticParseJob?> getJob(String messageId);

  Future<SemanticParseMessageInput?> getMessageInput(String messageId);

  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
    List<String> preferredTodoIds = const <String>[],
  });

  Future<int?> claimJobRunning({
    required String messageId,
    required int nowMs,
  });

  Future<bool> markJobSucceededIfCurrentAttempt(
    SemanticParseJobSucceededArgs args, {
    required int expectedAttemptId,
  });

  Future<bool> markJobFailedIfCurrentAttempt(
    SemanticParseJobFailedArgs args, {
    required int expectedAttemptId,
  });

  Future<void> markJobCanceled({
    required String messageId,
    required int nowMs,
  });

  Future<bool> markJobCanceledIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required int nowMs,
  });

  Future<List<String>?> completeNoActionIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  });

  Future<bool> completeCreateTodoIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
    String? followupTaskTypeHint,
    required List<String> checklistSuggestions,
    required String checklistSource,
    String? checklistGenerationKey,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  });

  Future<bool> completeFollowupIfCurrentAttempt({
    required String messageId,
    required int expectedAttemptId,
    required String todoId,
    String? todoTitle,
    String? newStatus,
    int? dueAtMs,
    List<String>? pendingSuggestedTags,
    List<String>? autoApplySuggestedTags,
    double? suggestedTagConfidence,
    required int nowMs,
  });

  Future<SemanticParseTagApplyResult> applySemanticTags({
    required String messageId,
    required List<String> suggestedTags,
    int? expectedAttemptId,
  });

  Future<String?> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
    String? followupTaskTypeHint,
    int? expectedAttemptId,
  });

  Future<void> upsertGeneratedChecklistSuggestions({
    required String messageId,
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
    int? expectedAttemptId,
  });

  /// Returns the previous status when available (for Undo).
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
    int? expectedAttemptId,
  });
}

abstract class SemanticParseAutoActionsClient {
  Future<List<String>> retrieveTodoCandidateIds({
    required String query,
    required int topK,
  });

  Future<List<TodoThreadMatch>> retrieveTodoCandidateMatches({
    required String query,
    required int topK,
  }) async {
    final ids = await retrieveTodoCandidateIds(query: query, topK: topK);
    final out = <TodoThreadMatch>[];
    final seen = <String>{};
    for (final rawId in ids) {
      final todoId = rawId.trim();
      if (todoId.isEmpty || !seen.add(todoId)) continue;
      out.add(TodoThreadMatch(todoId: todoId, distance: 1.0));
      if (out.length >= topK) break;
    }
    return out;
  }

  Future<String> parseMessageActionJson({
    required String text,
    required String nowLocalIso,
    required String localeTag,
    required int dayEndMinutes,
    required List<SemanticParseTodoCandidate> candidates,
    required String localResultJson,
    required List<String> unresolvedFields,
    required Duration timeout,
  });

  Future<List<String>> generateChecklistSuggestions({
    required String taskTitle,
    required String taskContext,
    required String localeTag,
    String? status,
    int? dueAtMs,
    required Duration timeout,
  });
}

final class SemanticParseAutoActionsRunnerSettings {
  const SemanticParseAutoActionsRunnerSettings({
    required this.hardTimeout,
    required this.minAutoConfidence,
    this.minAutoTagConfidence = 0.8,
    this.minPendingTagConfidence = 0.6,
    this.batchLimit = 5,
  });

  final Duration hardTimeout;
  final double minAutoConfidence;
  final double minAutoTagConfidence;
  final double minPendingTagConfidence;
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

const int kMaxSemanticTagsPerMessage = 3;

String? normalizeSemanticTagName(String raw) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  if (normalized.isEmpty) return null;
  return normalized;
}

List<String> normalizeSemanticTagNames(
  List<String> rawTags, {
  int maxCount = kMaxSemanticTagsPerMessage,
}) {
  final out = <String>[];
  final seen = <String>{};

  for (final rawTag in rawTags) {
    final normalized = normalizeSemanticTagName(rawTag);
    if (normalized == null || !seen.add(normalized)) continue;
    out.add(normalized);
    if (out.length >= maxCount) break;
  }

  return out;
}

final class SemanticParseAutoActionsRunner {
  SemanticParseAutoActionsRunner({
    required this.store,
    required this.client,
    required this.settings,
    SecretaryAuditRecorder? secretaryAuditRecorder,
    SemanticParseNowMs? nowMs,
    SemanticParseNowLocal? nowLocal,
  })  : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _nowLocal = nowLocal ?? (() => DateTime.now()),
        _secretaryAuditRecorder = secretaryAuditRecorder;

  final SemanticParseAutoActionsStore store;
  final SemanticParseAutoActionsClient client;
  final SemanticParseAutoActionsRunnerSettings settings;
  final SemanticParseNowMs _nowMs;
  final SemanticParseNowLocal _nowLocal;
  final SecretaryAuditRecorder? _secretaryAuditRecorder;

  Future<SemanticParseAutoActionsRunResult> runOnce({
    required String localeTag,
    required int dayEndMinutes,
    int? morningMinutes,
    int firstDayOfWeekIndex = 1,
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

      final messageInput = await store.getMessageInput(job.messageId);
      final analysisText = messageInput?.analysisText.trim() ?? '';
      if (analysisText.isEmpty) {
        await store.markJobCanceled(messageId: job.messageId, nowMs: nowMs);
        didUpdateJobs = true;
        continue;
      }

      int? attemptId;
      try {
        attemptId = await store.claimJobRunning(
          messageId: job.messageId,
          nowMs: nowMs,
        );
        if (attemptId == null) {
          // The due-jobs snapshot is stale; another actor already claimed,
          // canceled, or removed this job. Treat that as external progress so
          // the gate keeps draining instead of idling.
          didUpdateJobs = true;
          continue;
        }
        didUpdateJobs = true;

        var candidates = await store.listOpenTodoCandidates(
          query: analysisText,
          nowLocal: nowLocal,
          limit: 8,
        );

        final locale = _localeFromTag(localeTag);
        final resolvedMorningMinutes = morningMinutes ?? 8 * 60;
        var localParsedResult = _parseLocally(
          text: analysisText,
          nowLocal: nowLocal,
          locale: locale,
          candidates: candidates,
          dayEndMinutes: dayEndMinutes,
          morningMinutes: resolvedMorningMinutes,
          firstDayOfWeekIndex: firstDayOfWeekIndex,
        );

        var preferredMatches = const <TodoThreadMatch>[];
        var preferredTodoIds = const <String>[];
        if (_shouldRetrieveSemanticCandidates(localParsedResult)) {
          try {
            preferredMatches = await client
                .retrieveTodoCandidateMatches(
                  query: analysisText,
                  topK: 8,
                )
                .timeout(settings.hardTimeout);
            preferredTodoIds =
                _preferredTodoIdsFromSemanticMatches(preferredMatches);
          } catch (_) {
            preferredMatches = const <TodoThreadMatch>[];
            preferredTodoIds = const <String>[];
          }

          if (preferredTodoIds.isNotEmpty) {
            candidates = await store.listOpenTodoCandidates(
              query: analysisText,
              nowLocal: nowLocal,
              limit: 8,
              preferredTodoIds: preferredTodoIds,
            );
            localParsedResult = _parseLocally(
              text: analysisText,
              nowLocal: nowLocal,
              locale: locale,
              candidates: candidates,
              dayEndMinutes: dayEndMinutes,
              morningMinutes: resolvedMorningMinutes,
              firstDayOfWeekIndex: firstDayOfWeekIndex,
              semanticMatches: preferredMatches,
            );
          }
        }
        final unresolvedFields = _unresolvedFields(localParsedResult);
        var parsed = AiSemanticParse.fromLocalResult(localParsedResult);
        try {
          if (_shouldRequestEnhancement(
            localParsedResult,
            minAutoConfidence: settings.minAutoConfidence,
          )) {
            final json = await client
                .parseMessageActionJson(
                  text: analysisText,
                  nowLocalIso: nowLocal.toIso8601String(),
                  localeTag: localeTag,
                  dayEndMinutes: dayEndMinutes,
                  candidates: candidates,
                  localResultJson: _localResultJson(localParsedResult),
                  unresolvedFields: unresolvedFields,
                  timeout: settings.hardTimeout,
                )
                .timeout(settings.hardTimeout);

            final remoteParsed = AiSemanticParse.tryParseMessageAction(
              json,
              nowLocal: nowLocal,
              locale: locale,
              dayEndMinutes: dayEndMinutes,
              morningMinutes: resolvedMorningMinutes,
              firstDayOfWeekIndex: firstDayOfWeekIndex,
            );
            if (remoteParsed == null) {
              throw StateError('invalid_json');
            }
            parsed = _mergeEnhancedDecision(
              localResult: localParsedResult,
              remoteParsed: remoteParsed,
              unresolvedFields: unresolvedFields,
            );
          }
        } catch (error) {
          if (_shouldRetryRemoteParseError(error)) {
            rethrow;
          }
        }

        final refreshedMessageInput =
            await store.getMessageInput(job.messageId);
        final refreshedAnalysisText =
            refreshedMessageInput?.analysisText.trim() ?? '';
        final allowCreate = refreshedMessageInput?.allowCreate ?? false;
        if (!await _isStillRunningAttempt(
          messageId: job.messageId,
          attemptId: attemptId,
        )) {
          continue;
        }
        if (refreshedAnalysisText.isEmpty ||
            refreshedAnalysisText != analysisText) {
          await _markJobCanceledIfStillRunning(
            messageId: job.messageId,
            attemptId: attemptId,
            nowMs: nowMs,
          );

          continue;
        }

        final normalizedSuggestedTags = normalizeSemanticTagNames(
          parsed.suggestedTags,
        );
        List<String>? pendingSuggestedTags;
        List<String>? autoApplySuggestedTags;
        double? suggestedTagConfidence;

        if (normalizedSuggestedTags.isNotEmpty) {
          if (!await _isStillRunningAttempt(
            messageId: job.messageId,
            attemptId: attemptId,
          )) {
            continue;
          }
          if (parsed.tagConfidence >= settings.minAutoTagConfidence) {
            autoApplySuggestedTags = normalizedSuggestedTags;
            suggestedTagConfidence = parsed.tagConfidence;
          } else if (parsed.tagConfidence >= settings.minPendingTagConfidence) {
            pendingSuggestedTags = normalizedSuggestedTags;
            suggestedTagConfidence = parsed.tagConfidence;
          }
        }

        if (parsed.confidence < settings.minAutoConfidence) {
          final appliedTagIds = await store.completeNoActionIfCurrentAttempt(
            messageId: job.messageId,
            expectedAttemptId: attemptId,
            pendingSuggestedTags: pendingSuggestedTags,
            autoApplySuggestedTags: autoApplySuggestedTags,
            suggestedTagConfidence: suggestedTagConfidence,
            nowMs: nowMs,
          );
          if (appliedTagIds == null) {
            continue;
          }
          if (appliedTagIds.isNotEmpty) {
            didMutateAny = true;
          }

          continue;
        }

        switch (parsed.decision) {
          case MessageActionCreateDecision(
              :final title,
              :final status,
              :final dueAtLocal,
              :final recurrenceRule,
            ):
            if (!allowCreate) {
              final appliedTagIds =
                  await store.completeNoActionIfCurrentAttempt(
                messageId: job.messageId,
                expectedAttemptId: attemptId,
                pendingSuggestedTags: pendingSuggestedTags,
                autoApplySuggestedTags: autoApplySuggestedTags,
                suggestedTagConfidence: suggestedTagConfidence,
                nowMs: nowMs,
              );
              if (appliedTagIds == null) {
                continue;
              }
              if (appliedTagIds.isNotEmpty) {
                didMutateAny = true;
              }

              break;
            }
            if (!await _isStillRunningAttempt(
              messageId: job.messageId,
              attemptId: attemptId,
            )) {
              continue;
            }
            List<String> generatedChecklistSuggestions = const <String>[];
            try {
              generatedChecklistSuggestions =
                  await client.generateChecklistSuggestions(
                taskTitle: title,
                taskContext: analysisText,
                localeTag: localeTag,
                status: status,
                dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
                timeout: settings.hardTimeout,
              );
            } catch (_) {
              // Best effort only. Checklist suggestions must not block todo creation.
            }
            if (!await _isStillRunningAttempt(
              messageId: job.messageId,
              attemptId: attemptId,
            )) {
              continue;
            }
            final didFinalize = await store.completeCreateTodoIfCurrentAttempt(
              messageId: job.messageId,
              expectedAttemptId: attemptId,
              title: title,
              status: status,
              dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
              recurrenceRuleJson: recurrenceRule?.toJsonString(),
              followupTaskTypeHint: parsed.taskType,
              checklistSuggestions: generatedChecklistSuggestions,
              checklistSource: switch (client) {
                BackendSemanticParseAutoActionsClient(:final askAiRoute) =>
                  askAiRoute == AskAiRouteKind.cloudGateway ? 'cloud' : 'byok',
                _ => 'byok',
              },
              checklistGenerationKey: 'semantic_parse_auto:${job.messageId}',
              pendingSuggestedTags: pendingSuggestedTags,
              autoApplySuggestedTags: autoApplySuggestedTags,
              suggestedTagConfidence: suggestedTagConfidence,
              nowMs: nowMs,
            );

            if (didFinalize) {
              await _recordSecretaryTodoMutation(
                messageId: job.messageId,
                toolName: 'todo.create',
                inputJson: jsonEncode({
                  'message_id': job.messageId,
                  'title': title,
                  'status': status,
                  'due_at_ms': dueAtLocal?.toUtc().millisecondsSinceEpoch,
                }),
                outputJson: jsonEncode({
                  'todo_id': 'todo:${job.messageId}',
                  'title': title,
                  'status': status,
                }),
                nowMs: nowMs,
              );
              didMutateAny = true;
              processed += 1;
            }
            break;
          case MessageActionFollowUpDecision(
              :final todoId,
              :final newStatus,
              :final dueAtLocal,
            ):
            if (!await _isStillRunningAttempt(
              messageId: job.messageId,
              attemptId: attemptId,
            )) {
              continue;
            }
            final candidate = candidates
                .where((c) => c.id == todoId)
                .cast<SemanticParseTodoCandidate?>()
                .firstWhere((_) => true, orElse: () => null);
            final candidateTitle = candidate?.title;
            if (candidate == null || candidateTitle == null) {
              final appliedTagIds =
                  await store.completeNoActionIfCurrentAttempt(
                messageId: job.messageId,
                expectedAttemptId: attemptId,
                pendingSuggestedTags: pendingSuggestedTags,
                autoApplySuggestedTags: autoApplySuggestedTags,
                suggestedTagConfidence: suggestedTagConfidence,
                nowMs: nowMs,
              );
              if (appliedTagIds == null) {
                continue;
              }
              if (appliedTagIds.isNotEmpty) {
                didMutateAny = true;
              }
              continue;
            }

            final requestedDueAtMs = dueAtLocal?.toUtc().millisecondsSinceEpoch;
            final candidateDueAtMs = candidate.dueLocalIso == null
                ? null
                : DateTime.tryParse(candidate.dueLocalIso!)
                    ?.toUtc()
                    .millisecondsSinceEpoch;
            final requestsStatusChange = newStatus != null;
            final requestsDueChange = requestedDueAtMs != null;
            final statusAlreadyMatches =
                !requestsStatusChange || newStatus == candidate.status;
            final dueAlreadyMatches =
                !requestsDueChange || requestedDueAtMs == candidateDueAtMs;
            if ((requestsStatusChange || requestsDueChange) &&
                statusAlreadyMatches &&
                dueAlreadyMatches) {
              final appliedTagIds =
                  await store.completeNoActionIfCurrentAttempt(
                messageId: job.messageId,
                expectedAttemptId: attemptId,
                pendingSuggestedTags: pendingSuggestedTags,
                autoApplySuggestedTags: autoApplySuggestedTags,
                suggestedTagConfidence: suggestedTagConfidence,
                nowMs: nowMs,
              );
              if (appliedTagIds == null) {
                continue;
              }
              if (appliedTagIds.isNotEmpty) {
                didMutateAny = true;
              }
              continue;
            }

            final didFinalize = await store.completeFollowupIfCurrentAttempt(
              messageId: job.messageId,
              expectedAttemptId: attemptId,
              todoId: todoId,
              todoTitle: candidateTitle,
              newStatus: newStatus,
              dueAtMs: requestedDueAtMs,
              pendingSuggestedTags: pendingSuggestedTags,
              autoApplySuggestedTags: autoApplySuggestedTags,
              suggestedTagConfidence: suggestedTagConfidence,
              nowMs: nowMs,
            );

            if (didFinalize) {
              await _recordSecretaryTodoMutation(
                messageId: job.messageId,
                toolName: 'todo.update',
                inputJson: jsonEncode({
                  'message_id': job.messageId,
                  'todo_id': todoId,
                  'new_status': newStatus,
                  'due_at_ms': requestedDueAtMs,
                }),
                outputJson: jsonEncode({
                  'todo_id': todoId,
                  'title': candidateTitle,
                  'new_status': newStatus,
                  'due_at_ms': requestedDueAtMs,
                }),
                nowMs: nowMs,
              );
              didMutateAny = true;
              processed += 1;
            }
            break;
          case MessageActionNoneDecision():
            final appliedTagIds = await store.completeNoActionIfCurrentAttempt(
              messageId: job.messageId,
              expectedAttemptId: attemptId,
              pendingSuggestedTags: pendingSuggestedTags,
              autoApplySuggestedTags: autoApplySuggestedTags,
              suggestedTagConfidence: suggestedTagConfidence,
              nowMs: nowMs,
            );
            if (appliedTagIds == null) {
              continue;
            }
            if (appliedTagIds.isNotEmpty) {
              didMutateAny = true;
            }

            break;
        }
      } catch (e) {
        if (attemptId == null) {
          rethrow;
        }
        final attempts = job.attempts + 1;
        final nextRetryAtMs = nowMs + _retryBackoffMs(attempts);
        await _markJobFailedIfStillRunning(
          SemanticParseJobFailedArgs(
            messageId: job.messageId,
            attempts: attempts,
            nextRetryAtMs: nextRetryAtMs,
            error: e.toString(),
            nowMs: nowMs,
          ),
          attemptId: attemptId,
        );
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
    final parts = normalized
        .split(RegExp(r'[-_]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return const Locale('en');
    }

    String? scriptCode;
    String? countryCode;
    for (final part in parts.skip(1)) {
      if (scriptCode == null && RegExp(r'^[A-Za-z]{4}$').hasMatch(part)) {
        scriptCode =
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        continue;
      }
      if (countryCode == null &&
          (RegExp(r'^[A-Za-z]{2}$').hasMatch(part) ||
              RegExp(r'^\d{3}$').hasMatch(part))) {
        countryCode = part.toUpperCase();
        continue;
      }
    }

    return Locale.fromSubtags(
      languageCode: parts.first.toLowerCase(),
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }

  static bool _shouldRetryRemoteParseError(Object error) {
    if (error is TimeoutException) return true;

    final statusCode = parseHttpStatusFromError(error);
    if (statusCode == 408 || statusCode == 429 || statusCode == 499) {
      return true;
    }
    if (statusCode != null && statusCode >= 500) return true;

    final message = error.toString().toLowerCase();
    const retryableKeywords = <String>[
      'cancelled',
      'canceled',
      'operation canceled',
      'operation cancelled',
      'request canceled',
      'request cancelled',
      'aborted',
      'background',
      'connection reset',
      'connection closed',
      'broken pipe',
      'socket',
      'network is unreachable',
      'timed out',
      'timeout',
    ];
    for (final keyword in retryableKeywords) {
      if (message.contains(keyword)) return true;
    }

    return false;
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

  Future<bool> _isStillRunningAttempt({
    required String messageId,
    required int attemptId,
  }) async {
    final currentJob = await store.getJob(messageId);
    if (currentJob == null) {
      return false;
    }
    return currentJob.status == 'running' &&
        currentJob.attemptId.toInt() == attemptId;
  }

  Future<bool> _markJobFailedIfStillRunning(
    SemanticParseJobFailedArgs args, {
    required int attemptId,
  }) async {
    return store.markJobFailedIfCurrentAttempt(
      args,
      expectedAttemptId: attemptId,
    );
  }

  Future<bool> _markJobCanceledIfStillRunning({
    required String messageId,
    required int attemptId,
    required int nowMs,
  }) async {
    return store.markJobCanceledIfCurrentAttempt(
      messageId: messageId,
      expectedAttemptId: attemptId,
      nowMs: nowMs,
    );
  }

  Future<void> _recordSecretaryTodoMutation({
    required String messageId,
    required String toolName,
    required String inputJson,
    required String outputJson,
    required int nowMs,
  }) async {
    final recorder = _secretaryAuditRecorder;
    if (recorder == null) return;
    await recorder.recordRun(
      SecretaryAuditRunDraft(
        triggerKind: 'capture',
        route: _secretaryAuditRoute(),
        status: 'succeeded',
        inputSummary: 'Semantic parse applied to message $messageId',
        outputSummary: 'Applied $toolName',
        nowMs: nowMs,
        toolCalls: [
          SecretaryToolCallDraft(
            toolName: toolName,
            status: 'succeeded',
            requiresConfirmation: false,
            inputJson: inputJson,
            outputJson: outputJson,
          ),
        ],
      ),
    );
  }

  String _secretaryAuditRoute() {
    return switch (client) {
      BackendSemanticParseAutoActionsClient(:final askAiRoute) => switch (
            askAiRoute) {
          AskAiRouteKind.cloudGateway => 'cloud',
          AskAiRouteKind.byok => 'byok',
          AskAiRouteKind.needsSetup => 'local_rules',
        },
      _ => 'local_rules',
    };
  }
}
