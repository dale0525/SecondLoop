import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'ai_routing.dart';
import 'embeddings_source_prefs.dart';
import 'semantic_parse_edit_policy.dart';
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
import '../backend/knowledge_index_models.dart';
import '../backend/knowledge_viewer_backend.dart';
import '../backend/native_backend.dart';
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

  Future<SemanticParseMessageInput?> getMessageInput(String messageId);

  Future<List<SemanticParseTodoCandidate>> listOpenTodoCandidates({
    required String query,
    required DateTime nowLocal,
    required int limit,
    List<String> preferredTodoIds = const <String>[],
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

  Future<SemanticParseTagApplyResult> applySemanticTags({
    required String messageId,
    required List<String> suggestedTags,
  });

  Future<String> upsertTodoFromMessage({
    required String messageId,
    required String title,
    required String status,
    int? dueAtMs,
    String? recurrenceRuleJson,
    String? followupTaskTypeHint,
  });

  Future<void> upsertGeneratedChecklistSuggestions({
    required String todoId,
    required List<String> suggestions,
    required String source,
    String? generationKey,
  });

  /// Returns the previous status when available (for Undo).
  Future<String?> setTodoStatusFromMessage({
    required String messageId,
    required String todoId,
    required String newStatus,
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

      try {
        await store.markJobRunning(messageId: job.messageId, nowMs: nowMs);
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

        AiSemanticDecision? parsed;
        try {
          final json = await client
              .parseMessageActionJson(
                text: analysisText,
                nowLocalIso: nowLocal.toIso8601String(),
                localeTag: localeTag,
                dayEndMinutes: dayEndMinutes,
                candidates: candidates,
                timeout: settings.hardTimeout,
              )
              .timeout(settings.hardTimeout);

          parsed = AiSemanticParse.tryParseMessageAction(
            json,
            nowLocal: nowLocal,
            locale: locale,
            dayEndMinutes: dayEndMinutes,
            morningMinutes: resolvedMorningMinutes,
            firstDayOfWeekIndex: firstDayOfWeekIndex,
          );
          if (parsed == null) {
            throw StateError('invalid_json');
          }
        } catch (error) {
          if (_shouldRetryRemoteParseError(error)) {
            rethrow;
          }
          final localDecision = _resolveLocallyWhenRemoteFails(
            analysisText,
            locale: locale,
            nowLocal: nowLocal,
            dayEndMinutes: dayEndMinutes,
            morningMinutes: resolvedMorningMinutes,
            firstDayOfWeekIndex: firstDayOfWeekIndex,
            candidates: candidates,
          );
          parsed = AiSemanticDecision(decision: localDecision, confidence: 1.0);
        }

        final normalizedSuggestedTags = normalizeSemanticTagNames(
          parsed.suggestedTags,
        );
        List<String>? suggestedTags;
        double? suggestedTagConfidence;
        String tagSuggestionState = 'none';
        List<String>? appliedTagIds;

        if (normalizedSuggestedTags.isNotEmpty) {
          if (parsed.tagConfidence >= settings.minAutoTagConfidence) {
            final result = await store.applySemanticTags(
              messageId: job.messageId,
              suggestedTags: normalizedSuggestedTags,
            );
            if (result.appliedCount > 0) {
              didMutateAny = true;
              suggestedTags = normalizedSuggestedTags;
              suggestedTagConfidence = parsed.tagConfidence;
              tagSuggestionState = 'applied';
              if (result.appliedTagIds.isNotEmpty) {
                appliedTagIds = result.appliedTagIds;
              }
            }
          } else if (parsed.tagConfidence >= settings.minPendingTagConfidence) {
            suggestedTags = normalizedSuggestedTags;
            suggestedTagConfidence = parsed.tagConfidence;
            tagSuggestionState = 'pending';
          }
        }

        if (parsed.confidence < settings.minAutoConfidence) {
          await store.markJobSucceeded(
            SemanticParseJobSucceededArgs(
              messageId: job.messageId,
              appliedActionKind: 'none',
              appliedTodoId: null,
              appliedTodoTitle: null,
              appliedPrevTodoStatus: null,
              suggestedTags: suggestedTags,
              suggestedTagConfidence: suggestedTagConfidence,
              tagSuggestionState: tagSuggestionState,
              appliedTagIds: appliedTagIds,
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
            if (!(messageInput?.allowCreate ?? false)) {
              await store.markJobSucceeded(
                SemanticParseJobSucceededArgs(
                  messageId: job.messageId,
                  appliedActionKind: 'none',
                  appliedTodoId: null,
                  appliedTodoTitle: null,
                  appliedPrevTodoStatus: null,
                  suggestedTags: suggestedTags,
                  suggestedTagConfidence: suggestedTagConfidence,
                  tagSuggestionState: tagSuggestionState,
                  appliedTagIds: appliedTagIds,
                  nowMs: nowMs,
                ),
              );
              didUpdateJobs = true;
              break;
            }
            final appliedTodoId = await store.upsertTodoFromMessage(
              messageId: job.messageId,
              title: title,
              status: status,
              dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
              recurrenceRuleJson: recurrenceRule?.toJsonString(),
              followupTaskTypeHint: parsed.taskType,
            );
            try {
              final generatedChecklistSuggestions =
                  await client.generateChecklistSuggestions(
                taskTitle: title,
                taskContext: analysisText,
                localeTag: localeTag,
                status: status,
                dueAtMs: dueAtLocal?.toUtc().millisecondsSinceEpoch,
                timeout: settings.hardTimeout,
              );
              if (generatedChecklistSuggestions.isNotEmpty) {
                await store.upsertGeneratedChecklistSuggestions(
                  todoId: appliedTodoId,
                  suggestions: generatedChecklistSuggestions,
                  source: switch (client) {
                    BackendSemanticParseAutoActionsClient(
                      :final askAiRoute,
                    ) =>
                      askAiRoute == AskAiRouteKind.cloudGateway
                          ? 'cloud'
                          : 'byok',
                    _ => 'byok',
                  },
                  generationKey: 'semantic_parse_auto:${job.messageId}',
                );
              }
            } catch (_) {
              // Best effort only. Checklist suggestions must not block todo creation.
            }
            await store.markJobSucceeded(
              SemanticParseJobSucceededArgs(
                messageId: job.messageId,
                appliedActionKind: 'create',
                appliedTodoId: appliedTodoId,
                appliedTodoTitle: title,
                appliedPrevTodoStatus: null,
                suggestedTags: suggestedTags,
                suggestedTagConfidence: suggestedTagConfidence,
                tagSuggestionState: tagSuggestionState,
                appliedTagIds: appliedTagIds,
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
                suggestedTags: suggestedTags,
                suggestedTagConfidence: suggestedTagConfidence,
                tagSuggestionState: tagSuggestionState,
                appliedTagIds: appliedTagIds,
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
                suggestedTags: suggestedTags,
                suggestedTagConfidence: suggestedTagConfidence,
                tagSuggestionState: tagSuggestionState,
                appliedTagIds: appliedTagIds,
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

  static MessageActionDecision _resolveLocallyWhenRemoteFails(
    String text, {
    required Locale locale,
    required DateTime nowLocal,
    required int dayEndMinutes,
    required int morningMinutes,
    required int firstDayOfWeekIndex,
    required List<SemanticParseTodoCandidate> candidates,
  }) {
    final targets = candidates
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

    return MessageActionResolver.resolve(
      text,
      locale: locale,
      nowLocal: nowLocal,
      dayEndMinutes: dayEndMinutes,
      morningMinutes: morningMinutes,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
      openTodoTargets: targets,
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
}
