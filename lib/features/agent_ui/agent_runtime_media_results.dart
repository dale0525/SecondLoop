part of 'agent_conversation_page.dart';

final class _AgentMessageMediaResultView {
  const _AgentMessageMediaResultView({
    required this.id,
    required this.title,
    required this.mediaType,
    this.transcript,
    this.summary,
    this.decisions = const <String>[],
    this.actionItems = const <String>[],
    this.sources = const <String>[],
  });

  final String id;
  final String title;
  final String mediaType;
  final String? transcript;
  final String? summary;
  final List<String> decisions;
  final List<String> actionItems;
  final List<String> sources;

  bool get hasVisibleContent {
    return (transcript?.trim().isNotEmpty ?? false) ||
        (summary?.trim().isNotEmpty ?? false) ||
        decisions.isNotEmpty ||
        actionItems.isNotEmpty ||
        sources.isNotEmpty;
  }
}

List<RuntimeWorkingSetRecord> _runtimeMediaResultRecordsForState(
  RuntimeAgentState state,
) {
  return _mergeRuntimeMediaRecordsById([
    ...state.workingSetRecords,
    ..._runtimeMediaRecordsFromWorkingSet(
      state.latestContextSnapshot?.packet['working_set'],
    ),
  ]).where((record) => record.kind == 'media_result').toList(growable: false);
}

Map<String, List<_AgentMessageMediaResultView>>
    _messageMediaResultsFromRuntimeRecords({
  required List<RuntimeConversationTurn> turns,
  required List<RuntimeWorkingSetRecord> mediaRecords,
  required Map<String, _AgentMessageAttachmentView> localAttachmentsByRef,
  required _RuntimeMediaInlineLabels labels,
}) {
  if (turns.isEmpty || mediaRecords.isEmpty) {
    return const <String, List<_AgentMessageMediaResultView>>{};
  }

  final assistantTurnIds = turns
      .where((turn) => turn.role == 'assistant')
      .map((turn) => turn.turnId)
      .where((id) => id.trim().isNotEmpty)
      .toSet();
  if (assistantTurnIds.isEmpty) {
    return const <String, List<_AgentMessageMediaResultView>>{};
  }

  final attachmentById = <String, _AgentMessageAttachmentView>{};
  final nextAssistantByUserTurnId = <String, String>{};
  final assistantByAttachmentId = <String, String>{};
  String? pendingUserTurnId;
  var pendingAttachmentIds = <String>{};

  for (final turn in turns) {
    if (turn.role == 'user') {
      pendingUserTurnId = turn.turnId;
      pendingAttachmentIds = _runtimeAttachmentIdsForTurn(
        turn,
        attachmentById: attachmentById,
        localAttachmentsByRef: localAttachmentsByRef,
      );
      continue;
    }

    if (turn.role != 'assistant') continue;
    final userTurnId = pendingUserTurnId;
    if (userTurnId == null || userTurnId.isEmpty) continue;
    nextAssistantByUserTurnId[userTurnId] = turn.turnId;
    for (final attachmentId in pendingAttachmentIds) {
      assistantByAttachmentId.putIfAbsent(attachmentId, () => turn.turnId);
    }
    pendingUserTurnId = null;
    pendingAttachmentIds = <String>{};
  }

  final mediaResultsByMessageId =
      <String, List<_AgentMessageMediaResultView>>{};
  for (final record in mediaRecords) {
    final messageId = _mediaResultAssistantTurnId(
      record,
      assistantTurnIds: assistantTurnIds,
      nextAssistantByUserTurnId: nextAssistantByUserTurnId,
      assistantByAttachmentId: assistantByAttachmentId,
    );
    if (messageId == null) continue;

    final attachmentId = _runtimeMediaAttachmentId(record.raw);
    final view = _agentMessageMediaResultViewFromRecord(
      record,
      attachment: attachmentId == null ? null : attachmentById[attachmentId],
      labels: labels,
    );
    if (view == null || !view.hasVisibleContent) continue;
    mediaResultsByMessageId
        .putIfAbsent(messageId, () => <_AgentMessageMediaResultView>[])
        .add(view);
  }

  return Map<String, List<_AgentMessageMediaResultView>>.unmodifiable(
    mediaResultsByMessageId.map(
      (messageId, results) => MapEntry(
        messageId,
        List<_AgentMessageMediaResultView>.unmodifiable(results),
      ),
    ),
  );
}

List<_AgentMessageMediaResultView> _agentMessageMediaResultViewsFromRaw(
  List<Map<String, Object?>> rawResults, {
  required _RuntimeMediaInlineLabels labels,
}) {
  return rawResults
      .asMap()
      .entries
      .map((entry) {
        final raw = Map<String, Object?>.from(entry.value);
        raw['id'] = _firstRuntimeMediaString([
              raw['id'],
              raw['record_id'],
              raw['recordId'],
              raw['entity_id'],
              raw['entityId'],
            ]) ??
            'runtime-media-result-${entry.key}';
        raw['kind'] = _firstRuntimeMediaString([raw['kind']]) ?? 'media_result';
        return _agentMessageMediaResultViewFromRecord(
          RuntimeWorkingSetRecord.fromJson(raw),
          labels: labels,
        );
      })
      .whereType<_AgentMessageMediaResultView>()
      .where((view) => view.hasVisibleContent)
      .toList(growable: false);
}

Set<String> _runtimeAttachmentIdsForTurn(
  RuntimeConversationTurn turn, {
  required Map<String, _AgentMessageAttachmentView> attachmentById,
  required Map<String, _AgentMessageAttachmentView> localAttachmentsByRef,
}) {
  final attachments = _messageAttachmentsFromRuntimeTurn(
    turn,
    localAttachmentsByRef: localAttachmentsByRef,
  );
  for (final attachment in attachments) {
    attachmentById.putIfAbsent(attachment.id, () => attachment);
  }
  return <String>{
    ...turn.attachmentRefs.map((ref) => ref.trim()),
    ...attachments.map((attachment) => attachment.id.trim()),
  }..removeWhere((id) => id.isEmpty);
}

String? _mediaResultAssistantTurnId(
  RuntimeWorkingSetRecord record, {
  required Set<String> assistantTurnIds,
  required Map<String, String> nextAssistantByUserTurnId,
  required Map<String, String> assistantByAttachmentId,
}) {
  final raw = record.raw;
  final directTurnId = _firstRuntimeMediaString([
    raw['assistant_turn_id'],
    raw['assistantTurnId'],
    raw['assistant_message_id'],
    raw['assistantMessageId'],
    raw['message_id'],
    raw['messageId'],
    raw['turn_id'],
    raw['turnId'],
  ]);
  if (directTurnId != null && assistantTurnIds.contains(directTurnId)) {
    return directTurnId;
  }

  final sourceTurnId = _firstRuntimeMediaString([
    raw['source_message_id'],
    raw['sourceMessageId'],
    raw['source_turn_id'],
    raw['sourceTurnId'],
    raw['user_turn_id'],
    raw['userTurnId'],
  ]);
  if (sourceTurnId != null) {
    final assistantTurnId = nextAssistantByUserTurnId[sourceTurnId];
    if (assistantTurnId != null) return assistantTurnId;
  }

  final attachmentId = _runtimeMediaAttachmentId(raw);
  if (attachmentId != null) {
    final assistantTurnId = assistantByAttachmentId[attachmentId];
    if (assistantTurnId != null) return assistantTurnId;
  }

  if (assistantTurnIds.length == 1) return assistantTurnIds.single;
  return null;
}

_AgentMessageMediaResultView? _agentMessageMediaResultViewFromRecord(
  RuntimeWorkingSetRecord record, {
  _AgentMessageAttachmentView? attachment,
  required _RuntimeMediaInlineLabels labels,
}) {
  final raw = record.raw;
  final transcript = _firstRuntimeMediaString([
    raw['transcript'],
    raw['transcript_text'],
    raw['transcriptText'],
    raw['transcript_full'],
    raw['transcriptFull'],
    raw['transcription'],
    raw['ocr_text'],
    raw['ocrText'],
    record.text,
  ]);
  final rawSummary = _firstRuntimeMediaString([
    raw['meeting_minutes'],
    raw['meetingMinutes'],
    raw['minutes'],
    raw['summary'],
    raw['llm_summary'],
    raw['llmSummary'],
    raw['body'],
    raw['content'],
    record.summary,
    record.body,
  ]);
  final summary = _sameRuntimeMediaText(rawSummary, transcript)
      ? null
      : _runtimeMediaPreviewText(rawSummary);
  final title = _firstRuntimeMediaString([
        raw['filename'],
        raw['display_name'],
        raw['displayName'],
        raw['title'],
        attachment?.filename,
      ]) ??
      record.title.ifNotBlank ??
      record.id;
  final mediaType = _firstRuntimeMediaString([
        raw['media_type'],
        raw['mediaType'],
        attachment?.mediaType,
      ]) ??
      'file';

  return _AgentMessageMediaResultView(
    id: record.id,
    title: title,
    mediaType: mediaType,
    transcript: _runtimeMediaPreviewText(transcript),
    summary: summary,
    decisions: _runtimeMediaStringList(
      _firstRuntimeMediaValue([
        raw['decisions'],
        raw['decision_items'],
        raw['decisionItems'],
      ]),
      labels: labels,
    ),
    actionItems: _runtimeMediaStringList(
      _firstRuntimeMediaValue([
        raw['action_items'],
        raw['actionItems'],
        raw['actions'],
        raw['todos'],
        raw['task_candidates'],
        raw['taskCandidates'],
        raw['suggested_actions'],
        raw['suggestedActions'],
      ]),
      labels: labels,
    ),
    sources: _runtimeMediaSources(raw, attachment: attachment),
  );
}

List<String> _runtimeMediaSources(
  Map<String, Object?> raw, {
  _AgentMessageAttachmentView? attachment,
}) {
  final sources = <String>[];
  final attachmentTitle = attachment?.filename.trim();
  if (attachmentTitle != null && attachmentTitle.isNotEmpty) {
    sources.add(attachmentTitle);
  }
  for (final citation in _runtimeMediaObjectList(raw['citations'])) {
    final source = _firstRuntimeMediaString([
      citation['title'],
      citation['name'],
      citation['url'],
      citation['href'],
      citation['source_url'],
      citation['sourceUrl'],
    ]);
    if (source != null) sources.add(source);
  }
  return sources.toSet().toList(growable: false);
}

String? _runtimeMediaAttachmentId(Map<String, Object?> raw) {
  return _firstRuntimeMediaString([
    raw['attachment_id'],
    raw['attachmentId'],
    raw['source_attachment_id'],
    raw['sourceAttachmentId'],
    raw['blob_id'],
    raw['blobId'],
    raw['sha256'],
  ]);
}

List<RuntimeWorkingSetRecord> _runtimeMediaRecordsFromWorkingSet(Object? raw) {
  if (raw is! Map) return const <RuntimeWorkingSetRecord>[];
  return _runtimeMediaRecordList(raw['records']);
}

List<RuntimeWorkingSetRecord> _runtimeMediaRecordList(Object? raw) {
  if (raw is! List) return const <RuntimeWorkingSetRecord>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => RuntimeWorkingSetRecord.fromJson(
          item.map((key, value) => MapEntry('$key', value as Object?)),
        ),
      )
      .toList(growable: false);
}

List<RuntimeWorkingSetRecord> _mergeRuntimeMediaRecordsById(
  Iterable<RuntimeWorkingSetRecord> records,
) {
  final byId = <String, RuntimeWorkingSetRecord>{};
  for (final record in records) {
    final id = record.id.trim();
    if (id.isEmpty || byId.containsKey(id)) continue;
    byId[id] = record;
  }
  return byId.values.toList(growable: false);
}

Object? _firstRuntimeMediaValue(Iterable<Object?> values) {
  for (final value in values) {
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    if (value is List && value.isEmpty) continue;
    if (value is Map && value.isEmpty) continue;
    return value;
  }
  return null;
}

String? _firstRuntimeMediaString(Iterable<Object?> values) {
  for (final value in values) {
    final parsed = _runtimeMediaString(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _runtimeMediaString(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

String? _runtimeMediaPreviewText(String? value) {
  final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.length <= 1200) return normalized;
  return '${normalized.substring(0, 1197)}...';
}

bool _sameRuntimeMediaText(String? left, String? right) {
  final normalizedLeft = left?.trim().replaceAll(RegExp(r'\s+'), ' ');
  final normalizedRight = right?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalizedLeft != null &&
      normalizedRight != null &&
      normalizedLeft.isNotEmpty &&
      normalizedLeft == normalizedRight;
}

List<String> _runtimeMediaStringList(
  Object? raw, {
  required _RuntimeMediaInlineLabels labels,
}) {
  if (raw == null) return const <String>[];
  if (raw is String) {
    final value = _runtimeMediaPreviewText(raw);
    return value == null ? const <String>[] : <String>[value];
  }
  if (raw is Map) {
    final map = raw.map((key, value) => MapEntry('$key', value as Object?));
    final items = _runtimeMediaStringList(map['items'], labels: labels);
    if (items.isNotEmpty) return items;
    final text = _runtimeMediaItemText(map, labels: labels);
    return text == null ? const <String>[] : <String>[text];
  }
  if (raw is! List) return const <String>[];
  return raw
      .map((item) {
        if (item is Map) {
          return _runtimeMediaItemText(
            item.map((key, value) => MapEntry('$key', value as Object?)),
            labels: labels,
          );
        }
        final itemText = '$item';
        return _runtimeMediaPreviewText(itemText);
      })
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
}

String? _runtimeMediaItemText(
  Map<String, Object?> raw, {
  required _RuntimeMediaInlineLabels labels,
}) {
  final primary = _firstRuntimeMediaString([
    raw['title'],
    raw['text'],
    raw['summary'],
    raw['body'],
    raw['content'],
    raw['description'],
    raw['name'],
  ]);
  if (primary == null) return null;
  final owner = _firstRuntimeMediaString([raw['owner'], raw['assignee']]);
  final due =
      _firstRuntimeMediaString([raw['due'], raw['due_at'], raw['dueAt']]);
  return _runtimeMediaPreviewText([
    primary,
    if (owner != null) labels.owner(owner),
    if (due != null) labels.due(due),
  ].join(' - '));
}

final class _RuntimeMediaInlineLabels {
  const _RuntimeMediaInlineLabels({
    required this.transcript,
    required this.meetingMinutes,
    required this.summary,
    required this.decisions,
    required this.actionItems,
    required this.sources,
    required this.listItem,
    required this.owner,
    required this.due,
  });

  final String transcript;
  final String meetingMinutes;
  final String summary;
  final String decisions;
  final String actionItems;
  final String sources;
  final String Function(String value) listItem;
  final String Function(String value) owner;
  final String Function(String value) due;
}

_RuntimeMediaInlineLabels _runtimeMediaInlineLabels(BuildContext context) {
  final labels = context.t.chat.runtimeMediaResult;
  return _RuntimeMediaInlineLabels(
    transcript: labels.transcript,
    meetingMinutes: labels.meetingMinutes,
    summary: labels.summary,
    decisions: labels.decisions,
    actionItems: labels.actionItems,
    sources: labels.sources,
    listItem: (value) => labels.listItem(value: value),
    owner: (value) => labels.owner(value: value),
    due: (value) => labels.due(value: value),
  );
}

List<Map<String, Object?>> _runtimeMediaObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => item.map((key, value) => MapEntry('$key', value as Object?)),
      )
      .toList(growable: false);
}

final class _AssistantRuntimeMediaResults extends StatelessWidget {
  const _AssistantRuntimeMediaResults({required this.results});

  final List<_AgentMessageMediaResultView> results;

  @override
  Widget build(BuildContext context) {
    final labels = _runtimeMediaInlineLabels(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < results.length; index++) ...[
          _AssistantRuntimeMediaResult(
            result: results[index],
            labels: labels,
          ),
          if (index < results.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgentDesignTokens.gapMd),
              child: Divider(height: 1),
            ),
        ],
      ],
    );
  }
}

final class _AssistantRuntimeMediaResult extends StatelessWidget {
  const _AssistantRuntimeMediaResult({
    required this.result,
    required this.labels,
  });

  final _AgentMessageMediaResultView result;
  final _RuntimeMediaInlineLabels labels;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: _AgentConversationPageState._muted,
          fontWeight: FontWeight.w800,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.summarize_outlined, size: 18),
            const SizedBox(width: AgentDesignTokens.gapSm),
            Flexible(
              child: Text(
                result.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _AgentConversationPageState._ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
        if (result.transcript != null)
          _RuntimeMediaResultTextSection(
            title: labels.transcript,
            body: result.transcript!,
            labelStyle: labelStyle,
          ),
        if (result.summary != null)
          _RuntimeMediaResultTextSection(
            title: _runtimeMediaSummaryLabel(
              result.mediaType,
              labels: labels,
            ),
            body: result.summary!,
            labelStyle: labelStyle,
          ),
        if (result.decisions.isNotEmpty)
          _RuntimeMediaResultListSection(
            title: labels.decisions,
            items: result.decisions,
            labelStyle: labelStyle,
            listItem: labels.listItem,
          ),
        if (result.actionItems.isNotEmpty)
          _RuntimeMediaResultListSection(
            title: labels.actionItems,
            items: result.actionItems,
            labelStyle: labelStyle,
            listItem: labels.listItem,
          ),
        if (result.sources.isNotEmpty)
          _RuntimeMediaResultListSection(
            title: labels.sources,
            items: result.sources,
            labelStyle: labelStyle,
            listItem: labels.listItem,
            compact: true,
          ),
      ],
    );
  }
}

final class _RuntimeMediaResultTextSection extends StatelessWidget {
  const _RuntimeMediaResultTextSection({
    required this.title,
    required this.body,
    required this.labelStyle,
  });

  final String title;
  final String body;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: labelStyle),
          const SizedBox(height: AgentDesignTokens.gapXs),
          Text(
            body,
            style: const TextStyle(
              color: _AgentConversationPageState._ink,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

final class _RuntimeMediaResultListSection extends StatelessWidget {
  const _RuntimeMediaResultListSection({
    required this.title,
    required this.items,
    required this.labelStyle,
    required this.listItem,
    this.compact = false,
  });

  final String title;
  final List<String> items;
  final TextStyle? labelStyle;
  final String Function(String value) listItem;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: labelStyle),
          const SizedBox(height: AgentDesignTokens.gapXs),
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(
                bottom: compact ? 0 : AgentDesignTokens.gapXs,
              ),
              child: Text(
                compact ? item : listItem(item),
                style: const TextStyle(
                  color: _AgentConversationPageState._ink,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _runtimeMediaSummaryLabel(
  String mediaType, {
  required _RuntimeMediaInlineLabels labels,
}) {
  final normalized = mediaType.trim().toLowerCase();
  return normalized == 'audio' ? labels.meetingMinutes : labels.summary;
}

extension on String {
  String? get ifNotBlank {
    final value = trim();
    return value.isEmpty ? null : value;
  }
}
