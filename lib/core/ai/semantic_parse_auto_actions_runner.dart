import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'ai_routing.dart';
import 'embeddings_source_prefs.dart';
import 'semantic_parse_edit_policy.dart';
import 'local_semantic_parse_result.dart';
import 'local_semantic_parser.dart';
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
import 'semantic_parse.dart';

part 'semantic_parse_auto_actions_runner_store.dart';
part 'semantic_parse_auto_actions_runner_client.dart';

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

        List<String> preferredTodoIds = const <String>[];
        try {
          preferredTodoIds = await client
              .retrieveTodoCandidateIds(
                query: analysisText,
                topK: 8,
              )
              .timeout(settings.hardTimeout);
        } catch (_) {
          preferredTodoIds = const <String>[];
        }

        final candidates = await store.listOpenTodoCandidates(
          query: analysisText,
          nowLocal: nowLocal,
          limit: 8,
          preferredTodoIds: preferredTodoIds,
        );

        final locale = _localeFromTag(localeTag);
        final resolvedMorningMinutes = morningMinutes ?? dayEndMinutes;

        final localTargets = candidates
            .map(
              (c) => TodoLinkTarget(
                id: c.id,
                title: c.title,
                status: c.status,
                dueLocal: c.dueLocalIso == null
                    ? null
                    : DateTime.tryParse(c.dueLocalIso!),
              ),
            )
            .toList(growable: false);
        final localParsedResult = LocalSemanticParser.parse(
          text: analysisText,
          nowLocal: nowLocal,
          locale: locale,
          openTodoTargets: localTargets,
          dayEndMinutes: dayEndMinutes,
          morningMinutes: resolvedMorningMinutes,
          firstDayOfWeekIndex: firstDayOfWeekIndex,
        );
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
            parsed = remoteParsed;
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
            final candidateTitle = candidates
                .where((c) => c.id == todoId)
                .map((c) => c.title)
                .cast<String?>()
                .firstWhere((_) => true, orElse: () => null);
            if (candidateTitle == null) {
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
              dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
              pendingSuggestedTags: pendingSuggestedTags,
              autoApplySuggestedTags: autoApplySuggestedTags,
              suggestedTagConfidence: suggestedTagConfidence,
              nowMs: nowMs,
            );

            if (didFinalize) {
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
    final parts = normalized.split(RegExp(r'[-_]'));
    final language = parts.isNotEmpty ? parts[0] : 'en';
    final country = parts.length > 1 ? parts[1] : null;
    return Locale(language, country);
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

  static String _localResultJson(LocalSemanticParseResult result) {
    return jsonEncode(<String, Object?>{
      'kind': switch (result.kind) {
        LocalSemanticParseKind.none => 'none',
        LocalSemanticParseKind.create => 'create',
        LocalSemanticParseKind.followup => 'followup',
      },
      'confidence': result.confidence,
      'resolver': switch (result.resolver) {
        SemanticResolver.local => 'local',
        SemanticResolver.llm => 'llm',
        SemanticResolver.hybrid => 'hybrid',
      },
      'title': result.title,
      'status': result.status,
      'todo_id': result.todoId,
      'due_local_iso': result.dueAtLocal?.toIso8601String(),
      'recurrence': result.recurrenceRule?.toJsonMap(),
      'task_type': result.taskType,
      'suggested_tags': result.suggestedTags,
      'tag_confidence': result.tagConfidence,
      'diagnostics': <String, Object?>{
        'local_intent': result.diagnostics.localIntent,
        'has_explicit_status_update':
            result.diagnostics.hasExplicitStatusUpdate,
        'has_due_signal': result.diagnostics.hasDueSignal,
        'temporal_needs_enhancement':
            result.diagnostics.temporalNeedsEnhancement,
        'semantic_needs_enhancement':
            result.diagnostics.semanticNeedsEnhancement,
      },
    });
  }

  static List<String> _unresolvedFields(LocalSemanticParseResult result) {
    final fields = <String>[];

    void add(String value) {
      if (!fields.contains(value)) {
        fields.add(value);
      }
    }

    switch (result.kind) {
      case LocalSemanticParseKind.create:
        if ((result.title ?? '').trim().isEmpty) add('title');
        if ((result.status ?? '').trim().isEmpty) add('status');
        break;
      case LocalSemanticParseKind.followup:
        if ((result.todoId ?? '').trim().isEmpty) add('todo_id');
        if ((result.status ?? '').trim().isEmpty && result.dueAtLocal == null) {
          add('new_status');
        }
        break;
      case LocalSemanticParseKind.none:
        switch (result.diagnostics.localIntent) {
          case 'ambiguous_followup':
            add('todo_id');
            if (result.diagnostics.hasExplicitStatusUpdate) {
              add('new_status');
            }
            if (result.diagnostics.hasDueSignal) {
              add('due_local_iso');
            }
            break;
          case 'needs_enhancement':
            add('kind');
            if (result.diagnostics.semanticNeedsEnhancement) {
              add('title');
              add('status');
              add('todo_id');
            }
            if (result.diagnostics.hasExplicitStatusUpdate) {
              add('new_status');
            }
            if (result.diagnostics.hasDueSignal ||
                result.diagnostics.temporalNeedsEnhancement) {
              add('due_local_iso');
            }
            break;
          default:
            add('kind');
        }
        break;
    }

    return fields;
  }

  static bool _shouldRequestEnhancement(
    LocalSemanticParseResult result, {
    required double minAutoConfidence,
  }) {
    if (result.confidence < minAutoConfidence) {
      return true;
    }

    return switch (result.kind) {
      LocalSemanticParseKind.create => false,
      LocalSemanticParseKind.followup => false,
      LocalSemanticParseKind.none => result.diagnostics.localIntent != 'none',
    };
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
}
