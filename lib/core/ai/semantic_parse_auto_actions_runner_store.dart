part of 'semantic_parse_auto_actions_runner.dart';

final class BackendSemanticParseAutoActionsStore
    implements SemanticParseAutoActionsStore {
  BackendSemanticParseAutoActionsStore({
    required AppBackend backend,
    required Uint8List sessionKey,
    TagRepository tagRepository = const TagRepository(),
  })  : _backend = backend,
        _sessionKey = Uint8List.fromList(sessionKey),
        _tagRepository = tagRepository;

  final AppBackend _backend;
  final Uint8List _sessionKey;
  final TagRepository _tagRepository;

  static const int _kMaxAttachmentSemanticSnippets = 10;
  static const int _kMaxAttachmentSnippetRunes = 320;
  static const int _kMaxSemanticAnalysisRunes = 2400;
  static const String _kUrlAttachmentMimeType =
      'application/x.secondloop.url+json';
  static const List<String> _kAttachmentSemanticPayloadKeys = <String>[
    'caption_long',
    'manual_summary',
    'llm_summary',
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

      final attachmentMime = attachment.mimeType.trim().toLowerCase();
      final isUrlAttachment = attachmentMime == _kUrlAttachmentMimeType;
      var skipCaptionForAttachment = false;

      if (backend is NativeAppBackend) {
        try {
          final payloadJson = await backend.readAttachmentAnnotationPayloadJson(
            _sessionKey,
            sha256: attachment.sha256,
          );
          if (payloadJson != null && payloadJson.trim().isNotEmpty) {
            final payloadSnippets =
                _extractSemanticSnippetsFromPayload(payloadJson);
            if (isUrlAttachment && payloadSnippets.hasPreferredSummary) {
              skipCaptionForAttachment = true;
            }
            for (final snippet in payloadSnippets.snippets) {
              addSnippet(snippet);
              if (snippets.length >= _kMaxAttachmentSemanticSnippets) break;
            }
          }
        } catch (_) {
          // Ignore and continue with other attachments.
        }
      }

      if (skipCaptionForAttachment) continue;

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
    }

    return snippets;
  }

  static _SemanticPayloadSnippetResult _extractSemanticSnippetsFromPayload(
    String payloadJson,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } catch (_) {
      return const _SemanticPayloadSnippetResult(
        snippets: <String>[],
      );
    }
    if (decoded is! Map) {
      return const _SemanticPayloadSnippetResult(
        snippets: <String>[],
      );
    }

    final payload = Map<String, Object?>.from(decoded);
    if (_isUrlSemanticPayload(payload)) {
      final preferredSummary = _extractPreferredUrlSummarySnippet(payload);
      if (preferredSummary != null) {
        return _SemanticPayloadSnippetResult(
          snippets: <String>[preferredSummary],
          hasPreferredSummary: true,
        );
      }
    }

    final out = <String>[];
    for (final key in _kAttachmentSemanticPayloadKeys) {
      final value = payload[key];
      if (value == null) continue;
      final normalized = _normalizeSemanticSnippet(value.toString());
      if (normalized == null) continue;
      out.add(normalized);
    }
    return _SemanticPayloadSnippetResult(snippets: out);
  }

  static bool _isUrlSemanticPayload(Map<String, Object?> payload) {
    final mimeType =
        payload['mime_type']?.toString().trim().toLowerCase() ?? '';
    if (mimeType == _kUrlAttachmentMimeType) return true;
    const urlKeys = <String>['final_url', 'canonical_url', 'original_url'];
    for (final key in urlKeys) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return true;
    }
    return false;
  }

  static String? _extractPreferredUrlSummarySnippet(
    Map<String, Object?> payload,
  ) {
    const summaryKeys = <String>['manual_summary', 'llm_summary', 'summary'];
    for (final key in summaryKeys) {
      final value = payload[key];
      if (value == null) continue;
      final normalized = _normalizeSemanticSnippet(value.toString());
      if (normalized == null) continue;
      return normalized;
    }
    return null;
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
    List<String> preferredTodoIds = const <String>[],
  }) async {
    final todos = await _backend.listTodos(_sessionKey);
    final targets = <TodoLinkTarget>[];
    final targetsById = <String, TodoLinkTarget>{};
    for (final todo in todos) {
      if (todo.status == 'done' || todo.status == 'dismissed') continue;
      final dueMs = todo.dueAtMs;
      final target = TodoLinkTarget(
        id: todo.id,
        title: todo.title,
        status: todo.status,
        dueLocal: dueMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                dueMs,
                isUtc: true,
              ).toLocal(),
      );
      targets.add(target);
      targetsById[target.id] = target;
    }

    final out = <SemanticParseTodoCandidate>[];
    final seen = <String>{};

    void appendTarget(TodoLinkTarget target) {
      if (!seen.add(target.id)) return;
      out.add(
        SemanticParseTodoCandidate(
          id: target.id,
          title: target.title,
          status: target.status,
          dueLocalIso: target.dueLocal?.toIso8601String(),
        ),
      );
    }

    for (final rawId in preferredTodoIds) {
      if (out.length >= limit) break;
      final id = rawId.trim();
      if (id.isEmpty) continue;
      final target = targetsById[id];
      if (target == null) continue;
      appendTarget(target);
    }

    if (out.length >= limit) {
      return out;
    }

    final rankingLimit = (limit + preferredTodoIds.length).clamp(limit, 64);

    final ranked = rankTodoCandidates(
      query,
      targets,
      nowLocal: nowLocal,
      limit: rankingLimit,
    );
    for (final c in ranked) {
      if (out.length >= limit) break;
      appendTarget(c.target);
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
      suggestedTags: args.suggestedTags,
      suggestedTagConfidence: args.suggestedTagConfidence,
      tagSuggestionState: args.tagSuggestionState,
      appliedTagIds: args.appliedTagIds,
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
  Future<SemanticParseTagApplyResult> applySemanticTags({
    required String messageId,
    required List<String> suggestedTags,
  }) async {
    final dedupedTagNames = normalizeSemanticTagNames(suggestedTags);
    if (dedupedTagNames.isEmpty) {
      return const SemanticParseTagApplyResult(
        appliedCount: 0,
        appliedTagIds: <String>[],
      );
    }

    final manualTagNames = await _tagRepository.listManualMessageTagNames(
      _sessionKey,
      messageId,
    );
    if (manualTagNames.length >= kMaxSemanticTagsPerMessage) {
      return const SemanticParseTagApplyResult(
        appliedCount: 0,
        appliedTagIds: <String>[],
      );
    }

    final manualTagNameSet = manualTagNames
        .map((name) => normalizeSemanticTagName(name))
        .whereType<String>()
        .toSet();
    final allowedAutoFillCount =
        kMaxSemanticTagsPerMessage - manualTagNameSet.length;
    if (allowedAutoFillCount <= 0) {
      return const SemanticParseTagApplyResult(
        appliedCount: 0,
        appliedTagIds: <String>[],
      );
    }

    final existingMessageTags =
        await _tagRepository.listMessageTags(_sessionKey, messageId);
    final nextTagIds = existingMessageTags.map((tag) => tag.id).toSet();

    final appliedTagIds = <String>[];
    for (final tagName in dedupedTagNames) {
      if (manualTagNameSet.contains(tagName)) continue;
      final tag = await _tagRepository.upsertTag(_sessionKey, tagName);
      if (nextTagIds.add(tag.id)) {
        appliedTagIds.add(tag.id);
        if (appliedTagIds.length >= allowedAutoFillCount) {
          break;
        }
      }
    }

    if (appliedTagIds.isEmpty) {
      return const SemanticParseTagApplyResult(
        appliedCount: 0,
        appliedTagIds: <String>[],
      );
    }

    final sortedTagIds = nextTagIds.toList(growable: false)..sort();
    await _tagRepository.setMessageTags(_sessionKey, messageId, sortedTagIds);
    return SemanticParseTagApplyResult(
      appliedCount: appliedTagIds.length,
      appliedTagIds: List<String>.from(appliedTagIds, growable: false),
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

final class _SemanticPayloadSnippetResult {
  const _SemanticPayloadSnippetResult({
    required this.snippets,
    this.hasPreferredSummary = false,
  });

  final List<String> snippets;
  final bool hasPreferredSummary;
}
