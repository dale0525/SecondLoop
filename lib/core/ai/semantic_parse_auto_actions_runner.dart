import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'ai_routing.dart';
import 'semantic_parse_edit_policy.dart';
import '../../features/actions/review/review_backoff.dart';
import '../../features/actions/settings/actions_settings_store.dart';
import '../../features/actions/todo/message_action_resolver.dart';
import '../../features/actions/todo/todo_linking.dart';
import '../../src/rust/db.dart';
import '../../src/rust/semantic_parse.dart' as rust_semantic;
import '../backend/app_backend.dart';
import '../backend/attachments_backend.dart';
import '../backend/native_backend.dart';
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

  Future<SemanticParseMessageInput?> getMessageInput(String messageId);

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

  Future<String> upsertTodoFromMessage({
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

        final candidates = await store.listOpenTodoCandidates(
          query: analysisText,
          nowLocal: nowLocal,
          limit: 8,
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
        } catch (_) {
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
            if (!(messageInput?.allowCreate ?? false)) {
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
            final appliedTodoId = await store.upsertTodoFromMessage(
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
                appliedTodoId: appliedTodoId,
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

  static const int _kMaxAttachmentSemanticSnippets = 10;
  static const int _kMaxAttachmentSnippetRunes = 320;
  static const int _kMaxSemanticAnalysisRunes = 2400;
  static const List<String> _kAttachmentSemanticPayloadKeys = <String>[
    'caption_long',
    'summary',
    'video_summary',
    'extracted_text_excerpt',
    'extracted_text_full',
    'readable_text_excerpt',
    'readable_text_full',
    'ocr_text_excerpt',
    'ocr_text_full',
    'ocr_text',
    'transcript_excerpt',
    'transcript_full',
  ];

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
  Future<SemanticParseMessageInput?> getMessageInput(String messageId) async {
    final msg = await _backend.getMessageById(_sessionKey, messageId);
    final sourceText = (msg?.content ?? '').trim();

    final attachmentSnippets = await _loadAttachmentSemanticSnippets(messageId);
    final hasAttachmentSemanticContext = attachmentSnippets.isNotEmpty;

    final chunks = <String>[];
    if (sourceText.isNotEmpty) chunks.add(sourceText);
    chunks.addAll(attachmentSnippets);

    final analysisText = _truncateToRunes(
      chunks.join('\n'),
      _kMaxSemanticAnalysisRunes,
    ).trim();
    if (analysisText.isEmpty) return null;

    final allowCreate = sourceText.isNotEmpty &&
        !isLongTextForTodoAutomation(sourceText) &&
        !hasAttachmentSemanticContext;

    return SemanticParseMessageInput(
      sourceText: sourceText,
      analysisText: analysisText,
      allowCreate: allowCreate,
    );
  }

  Future<List<String>> _loadAttachmentSemanticSnippets(String messageId) async {
    if (_backend is! AttachmentsBackend) return const <String>[];

    final attachmentsBackend = _backend as AttachmentsBackend;
    List<Attachment> attachments = const <Attachment>[];
    try {
      attachments = await attachmentsBackend.listMessageAttachments(
        _sessionKey,
        messageId,
      );
    } catch (_) {
      return const <String>[];
    }
    if (attachments.isEmpty) return const <String>[];

    final snippets = <String>[];
    final seen = <String>{};

    void addSnippet(String? raw) {
      final normalized = _normalizeSemanticSnippet(raw);
      if (normalized == null) return;
      if (!seen.add(normalized)) return;
      snippets.add(normalized);
    }

    final backend = _backend;

    for (final attachment in attachments) {
      if (snippets.length >= _kMaxAttachmentSemanticSnippets) break;

      try {
        final caption =
            await attachmentsBackend.readAttachmentAnnotationCaptionLong(
          _sessionKey,
          sha256: attachment.sha256,
        );
        addSnippet(caption);
      } catch (_) {
        // Ignore and continue with other signals.
      }

      if (backend is NativeAppBackend) {
        try {
          final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
            _sessionKey,
            sha256: attachment.sha256,
          );
          if (payloadJson != null && payloadJson.trim().isNotEmpty) {
            for (final snippet in _extractSemanticSnippetsFromPayload(
              payloadJson,
            )) {
              addSnippet(snippet);
              if (snippets.length >= _kMaxAttachmentSemanticSnippets) break;
            }
          }
        } catch (_) {
          // Ignore and continue with other attachments.
        }
      }
    }

    return snippets;
  }

  static List<String> _extractSemanticSnippetsFromPayload(String payloadJson) {
    Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } catch (_) {
      return const <String>[];
    }
    if (decoded is! Map) return const <String>[];

    final payload = Map<String, Object?>.from(decoded);
    final out = <String>[];
    for (final key in _kAttachmentSemanticPayloadKeys) {
      final value = payload[key];
      if (value is! String) continue;
      final normalized = _normalizeSemanticSnippet(value);
      if (normalized == null) continue;
      out.add(normalized);
    }
    return out;
  }

  static String? _normalizeSemanticSnippet(String? raw) {
    if (raw == null) return null;
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    return _truncateToRunes(collapsed, _kMaxAttachmentSnippetRunes);
  }

  static String _truncateToRunes(String value, int maxRunes) {
    if (maxRunes <= 0) return '';
    final runes = value.runes;
    if (runes.length <= maxRunes) return value;
    return String.fromCharCodes(runes.take(maxRunes));
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
  Future<String> upsertTodoFromMessage({
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

    final todoId = await _resolveCreateTodoId(messageId);
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

    return todoId;
  }

  Future<String> _resolveCreateTodoId(String messageId) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return 'todo:$messageId';
    }

    try {
      final todos = await _backend.listTodos(_sessionKey);
      for (final todo in todos) {
        final sourceMessageId = todo.sourceEntryId?.trim();
        if (sourceMessageId != normalizedMessageId) continue;
        if (todo.status != 'done' && todo.status != 'dismissed') {
          return todo.id;
        }
      }

      for (final todo in todos) {
        final sourceMessageId = todo.sourceEntryId?.trim();
        if (sourceMessageId == normalizedMessageId) {
          return todo.id;
        }
      }
    } catch (_) {
      // ignore and fall back to deterministic todo id
    }

    return 'todo:$messageId';
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
