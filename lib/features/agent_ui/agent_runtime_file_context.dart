import '../../core/cloud/runtime_agent_state_models.dart';
import '../conversation_context/conversation_context_models.dart';

List<ConversationContextItem> agentRuntimeRecentFileItems(
  RuntimeAgentState state,
  Map<String, Object?>? latestPacket,
) {
  final attachmentsById = <String, _RuntimeFileAttachment>{};
  void collectAttachment(Object? raw) {
    final attachment = _runtimeFileAttachment(raw);
    if (attachment == null || attachmentsById.containsKey(attachment.id)) {
      return;
    }
    attachmentsById[attachment.id] = attachment;
  }

  for (final turn in state.conversationTurns) {
    for (final attachment in _runtimeObjectList(turn.raw['attachments'])) {
      collectAttachment(attachment);
    }
  }
  if (latestPacket != null) {
    for (final attachment in _runtimeObjectList(latestPacket['attachments'])) {
      collectAttachment(attachment);
    }
    for (final turn in _runtimeObjectList(latestPacket['recent_turns'])) {
      for (final attachment in _runtimeObjectList(turn['attachments'])) {
        collectAttachment(attachment);
      }
    }
  }

  final records = _mergeRuntimeRecordsById([
    ...state.workingSetRecords,
    ..._runtimeRecordsFromWorkingSet(latestPacket?['working_set']),
  ]).where((record) => record.kind == 'media_result');
  final items = <ConversationContextItem>[];
  final seenAttachmentIds = <String>{};
  for (final record in records) {
    final attachmentId = _firstRuntimeString([
      record.raw['attachment_id'],
      record.raw['attachmentId'],
      record.raw['source_attachment_id'],
      record.raw['sourceAttachmentId'],
    ]);
    final attachment =
        attachmentId == null ? null : attachmentsById[attachmentId];
    final title = attachment?.filename ??
        _firstRuntimeString([
          record.raw['filename'],
          record.raw['display_name'],
          record.raw['title'],
          attachmentId,
          record.id,
        ]) ??
        record.id;
    final subtitle = _runtimeFileSubtitle(
      summary: _firstRuntimeString([
        record.raw['summary'],
        record.raw['body'],
        record.raw['content'],
        record.summary,
      ]),
      text: _firstRuntimeString([
        record.raw['ocr_text'],
        record.raw['ocrText'],
        record.raw['transcript'],
        record.raw['text'],
      ]),
      status: _firstRuntimeString([record.raw['status']]),
      mimeType: attachment?.mimeType,
    );
    items.add(ConversationContextItem(title: title, subtitle: subtitle));
    if (attachmentId != null) seenAttachmentIds.add(attachmentId);
  }

  for (final attachment in attachmentsById.values) {
    if (seenAttachmentIds.contains(attachment.id)) continue;
    items.add(
      ConversationContextItem(
        title: attachment.filename,
        subtitle: _uploadedFileSubtitle(attachment.mimeType),
      ),
    );
  }
  return items.take(5).toList(growable: false);
}

String _runtimeFileSubtitle({
  required String? summary,
  required String? text,
  required String? status,
  required String? mimeType,
}) {
  final normalizedSummary = _compactRuntimeText(summary);
  if (normalizedSummary != null) return normalizedSummary;

  final normalizedText = _compactRuntimeText(text);
  if (normalizedText != null) return 'Extracted text: $normalizedText';

  final kind = _fileKindLabel(mimeType);
  final normalizedStatus = status?.trim().toLowerCase() ?? '';
  if (normalizedStatus.contains('fail') || normalizedStatus.contains('error')) {
    return '$kind processing failed';
  }
  if (normalizedStatus.contains('running') ||
      normalizedStatus.contains('pending') ||
      normalizedStatus.contains('processing')) {
    return '$kind processing';
  }
  if (normalizedStatus.isNotEmpty && normalizedStatus != 'registered') {
    return '$kind processed';
  }
  return _uploadedFileSubtitle(mimeType);
}

String _uploadedFileSubtitle(String? mimeType) {
  return '${_fileKindLabel(mimeType)} uploaded';
}

String _fileKindLabel(String? mimeType) {
  final normalized = mimeType?.trim().toLowerCase() ?? '';
  if (normalized.startsWith('image/')) return 'Image';
  if (normalized == 'application/pdf') return 'PDF';
  if (normalized.startsWith('audio/')) return 'Audio';
  if (normalized.startsWith('video/')) return 'Video';
  return 'File';
}

String? _compactRuntimeText(String? value) {
  final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.length <= 96) return normalized;
  return '${normalized.substring(0, 95)}…';
}

_RuntimeFileAttachment? _runtimeFileAttachment(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.map((key, value) => MapEntry('$key', value as Object?));
  final id = _firstRuntimeString([
    map['attachment_id'],
    map['attachmentId'],
    map['id'],
    map['sha256'],
    map['blob_id'],
    map['blobId'],
  ]);
  if (id == null) return null;
  final filename = _firstRuntimeString([
        map['filename'],
        map['display_name'],
        map['displayName'],
        map['name'],
      ]) ??
      id;
  final mimeType = _firstRuntimeString([
        map['mime_type'],
        map['mimeType'],
        map['content_type'],
        map['contentType'],
      ]) ??
      'application/octet-stream';
  return _RuntimeFileAttachment(
    id: id,
    filename: filename,
    mimeType: mimeType,
  );
}

final class _RuntimeFileAttachment {
  const _RuntimeFileAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
  });

  final String id;
  final String filename;
  final String mimeType;
}

List<RuntimeWorkingSetRecord> _runtimeRecordsFromWorkingSet(Object? raw) {
  if (raw is! Map) return const <RuntimeWorkingSetRecord>[];
  return _runtimeRecordList(raw['records']);
}

List<RuntimeWorkingSetRecord> _runtimeRecordList(Object? raw) {
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

List<Map<String, Object?>> _runtimeObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map(
        (item) => item.map((key, value) => MapEntry('$key', value as Object?)),
      )
      .toList(growable: false);
}

List<RuntimeWorkingSetRecord> _mergeRuntimeRecordsById(
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

String? _firstRuntimeString(Iterable<Object?> values) {
  for (final value in values) {
    final parsed = _runtimeString(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _runtimeString(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}
