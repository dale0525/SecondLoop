part of 'agent_conversation_page.dart';

final class _AgentMessageMediaResultView {
  const _AgentMessageMediaResultView({
    required this.id,
    required this.title,
    required this.mediaType,
    this.ocrText,
    this.transcript,
    this.summary,
    this.meetingId,
    this.durationLabel,
    this.sourceId,
    this.confidenceLabel,
    this.savedToVaultLabel,
    this.processingConfirmationLabel,
    this.decisions = const <String>[],
    this.actionItems = const <String>[],
    this.sources = const <String>[],
  });

  final String id;
  final String title;
  final String mediaType;
  final String? ocrText;
  final String? transcript;
  final String? summary;
  final String? meetingId;
  final String? durationLabel;
  final String? sourceId;
  final String? confidenceLabel;
  final String? savedToVaultLabel;
  final String? processingConfirmationLabel;
  final List<String> decisions;
  final List<String> actionItems;
  final List<String> sources;

  bool get hasVisibleContent {
    return (ocrText?.trim().isNotEmpty ?? false) ||
        (transcript?.trim().isNotEmpty ?? false) ||
        (summary?.trim().isNotEmpty ?? false) ||
        (meetingId?.trim().isNotEmpty ?? false) ||
        (durationLabel?.trim().isNotEmpty ?? false) ||
        (sourceId?.trim().isNotEmpty ?? false) ||
        (confidenceLabel?.trim().isNotEmpty ?? false) ||
        (savedToVaultLabel?.trim().isNotEmpty ?? false) ||
        (processingConfirmationLabel?.trim().isNotEmpty ?? false) ||
        decisions.isNotEmpty ||
        actionItems.isNotEmpty ||
        sources.isNotEmpty;
  }

  bool get isOcrResult => ocrText?.trim().isNotEmpty ?? false;
  bool get isAudioResult => mediaType.trim().toLowerCase() == 'audio';
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
  final mediaType = _firstRuntimeMediaString([
        raw['media_type'],
        raw['mediaType'],
        attachment?.mediaType,
      ]) ??
      'file';
  final ocrText = _runtimeMediaOcrText(raw, record: record);
  final transcript = _runtimeMediaTranscript(raw, mediaType: mediaType);
  final primaryText = ocrText ?? transcript;
  final rawSummary = _firstRuntimeMediaString([
    raw['meeting_summary'],
    raw['meetingSummary'],
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
  final summary = _sameRuntimeMediaText(rawSummary, primaryText)
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

  return _AgentMessageMediaResultView(
    id: record.id,
    title: title,
    mediaType: mediaType,
    ocrText: _runtimeMediaPreviewText(ocrText),
    transcript: _runtimeMediaPreviewText(transcript),
    summary: summary,
    meetingId: _runtimeMediaMeetingId(raw),
    durationLabel: _runtimeMediaDurationLabel(raw, attachment: attachment),
    sourceId: _runtimeMediaSourceId(raw),
    confidenceLabel: _runtimeMediaConfidenceLabel(raw),
    savedToVaultLabel: _runtimeMediaSavedToVaultLabel(raw),
    processingConfirmationLabel: _runtimeMediaProcessingConfirmationLabel(
      raw,
      mediaType: mediaType,
    ),
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

String? _runtimeMediaOcrText(
  Map<String, Object?> raw, {
  required RuntimeWorkingSetRecord record,
}) {
  return _firstRuntimeMediaString([
    raw['ocr_text'],
    raw['ocrText'],
    raw['ocr_text_full'],
    raw['ocrTextFull'],
    raw['ocr_text_excerpt'],
    raw['ocrTextExcerpt'],
    raw['readable_text_full'],
    raw['readableTextFull'],
    raw['readable_text_excerpt'],
    raw['readableTextExcerpt'],
    record.text,
  ]);
}

String? _runtimeMediaTranscript(
  Map<String, Object?> raw, {
  required String mediaType,
}) {
  final normalized = mediaType.trim().toLowerCase();
  if (normalized != 'audio' && normalized != 'video') return null;
  return _firstRuntimeMediaString([
    raw['transcript'],
    raw['transcript_text'],
    raw['transcriptText'],
    raw['transcript_full'],
    raw['transcriptFull'],
    raw['transcription_text'],
    raw['transcriptionText'],
    raw['transcription'],
  ]);
}

String? _runtimeMediaMeetingId(Map<String, Object?> raw) {
  return _firstRuntimeMediaString([
    raw['meeting_id'],
    raw['meetingId'],
    raw['minutes_id'],
    raw['minutesId'],
  ]);
}

String? _runtimeMediaDurationLabel(
  Map<String, Object?> raw, {
  _AgentMessageAttachmentView? attachment,
}) {
  final attachmentDuration = attachment?.durationLabel.trim();
  if (attachmentDuration != null && attachmentDuration.isNotEmpty) {
    return attachmentDuration;
  }
  final explicit = _firstRuntimeMediaString([
    raw['duration_label'],
    raw['durationLabel'],
    raw['display_duration'],
    raw['displayDuration'],
  ]);
  if (explicit != null) return explicit;
  for (final entry in const [
    ('duration_seconds', false),
    ('durationSeconds', false),
    ('duration_sec', false),
    ('durationSec', false),
    ('duration_ms', true),
    ('durationMs', true),
    ('duration', false),
  ]) {
    final label = _runtimeDurationLabelFromRaw(
      raw[entry.$1],
      milliseconds: entry.$2,
    );
    if (label.isNotEmpty) return label;
  }
  return null;
}

String? _runtimeMediaSourceId(Map<String, Object?> raw) {
  return _firstRuntimeMediaString([
    raw['source_id'],
    raw['sourceId'],
    raw['source_attachment_id'],
    raw['sourceAttachmentId'],
    raw['attachment_id'],
    raw['attachmentId'],
    raw['blob_id'],
    raw['blobId'],
    raw['sha256'],
  ]);
}

String? _runtimeMediaConfidenceLabel(Map<String, Object?> raw) {
  final value = _firstRuntimeMediaValue([
    raw['confidence_label'],
    raw['confidenceLabel'],
    raw['confidence_percent'],
    raw['confidencePercent'],
    raw['confidence'],
    raw['confidence_score'],
    raw['confidenceScore'],
    raw['ocr_confidence'],
    raw['ocrConfidence'],
  ]);
  if (value == null) return null;
  if (value is num) {
    final percent = value > 0 && value <= 1 ? value * 100 : value;
    return '${percent.round()}%';
  }
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  final parsed = double.tryParse(text);
  if (parsed != null) {
    final percent = parsed > 0 && parsed <= 1 ? parsed * 100 : parsed;
    return '${percent.round()}%';
  }
  return text;
}

String? _runtimeMediaSavedToVaultLabel(Map<String, Object?> raw) {
  final explicit = _firstRuntimeMediaValue([
    raw['saved_to_vault'],
    raw['savedToVault'],
    raw['vault_saved'],
    raw['vaultSaved'],
    raw['synced_to_vault'],
    raw['syncedToVault'],
  ]);
  if (explicit is bool) return explicit ? 'Yes' : 'No';
  if (explicit is String) {
    final normalized = explicit.trim().toLowerCase();
    if (normalized == 'true' || normalized == 'yes' || normalized == 'synced') {
      return 'Yes';
    }
    if (normalized == 'false' || normalized == 'no') return 'No';
  }

  final status = _firstRuntimeMediaString([
    raw['vault_status'],
    raw['vaultStatus'],
    raw['source_sync_status'],
    raw['sourceSyncStatus'],
    raw['status'],
  ])?.toLowerCase();
  if (status == null) return null;
  if (status.contains('vault') && status.contains('sync')) return 'Yes';
  if (status == 'synced' || status == 'saved' || status == 'saved_to_vault') {
    return 'Yes';
  }
  if (status.contains('failed')) return 'No';
  return null;
}

String? _runtimeMediaProcessingConfirmationLabel(
  Map<String, Object?> raw, {
  required String mediaType,
}) {
  final explicit = _firstRuntimeMediaString([
    raw['processing_confirmation_label'],
    raw['processingConfirmationLabel'],
    raw['confirmation_label'],
    raw['confirmationLabel'],
    raw['high_fidelity_label'],
    raw['highFidelityLabel'],
  ]);
  if (explicit != null) return explicit;

  final normalizedMediaType = mediaType.trim().toLowerCase();
  if (normalizedMediaType != 'audio' && normalizedMediaType != 'video') {
    return null;
  }
  final confirmed = _firstRuntimeMediaBool([
    raw['high_fidelity_confirmed'],
    raw['highFidelityConfirmed'],
    raw['high_cost_confirmed'],
    raw['highCostConfirmed'],
    raw['processing_confirmed'],
    raw['processingConfirmed'],
    raw['confirmed'],
  ]);
  return confirmed == true ? 'High-fidelity processing confirmed' : null;
}

bool? _firstRuntimeMediaBool(Iterable<Object?> values) {
  for (final value in values) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'confirmed') {
        return true;
      }
      if (normalized == 'false' || normalized == 'no') return false;
    }
  }
  return null;
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

extension on String {
  String? get ifNotBlank {
    final value = trim();
    return value.isEmpty ? null : value;
  }
}
