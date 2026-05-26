part of 'agent_conversation_page.dart';

final class _RuntimeMessageProjection {
  const _RuntimeMessageProjection({
    required this.messages,
    required this.attachmentsByMessageId,
    required this.mediaResultsByMessageId,
  });

  final List<Message> messages;
  final Map<String, List<_AgentMessageAttachmentView>> attachmentsByMessageId;
  final Map<String, List<_AgentMessageMediaResultView>> mediaResultsByMessageId;
}

final class _AgentMessageAttachmentView {
  const _AgentMessageAttachmentView({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.mediaType,
    this.sizeLabel = '',
    this.durationLabel = '',
    this.bytes,
  });

  final String id;
  final String filename;
  final String mimeType;
  final String mediaType;
  final String sizeLabel;
  final String durationLabel;
  final Uint8List? bytes;

  _AgentMessageAttachmentView copyWith({
    Uint8List? bytes,
  }) {
    return _AgentMessageAttachmentView(
      id: id,
      filename: filename,
      mimeType: mimeType,
      mediaType: mediaType,
      sizeLabel: sizeLabel,
      durationLabel: durationLabel,
      bytes: bytes ?? this.bytes,
    );
  }

  bool get isImage {
    final normalizedMediaType = mediaType.trim().toLowerCase();
    final normalizedMimeType = mimeType.trim().toLowerCase();
    return normalizedMediaType == 'image' ||
        normalizedMimeType.startsWith('image/');
  }

  bool get isAudio {
    final normalizedMediaType = mediaType.trim().toLowerCase();
    final normalizedMimeType = mimeType.trim().toLowerCase();
    return normalizedMediaType == 'audio' ||
        normalizedMimeType.startsWith('audio/');
  }

  bool get needsHydratedBytesForPreview => isImage || isAudio;

  String get secondaryLabel {
    return [
      durationLabel.trim(),
      sizeLabel.trim(),
    ].where((value) => value.isNotEmpty).join(' • ');
  }
}

extension _AgentConversationAttachmentHydration on _AgentConversationPageState {
  Future<Map<String, List<_AgentMessageAttachmentView>>>
      _hydrateRuntimeAttachmentBytes(
    Map<String, List<_AgentMessageAttachmentView>> attachmentsByMessageId, {
    required String vaultId,
  }) async {
    if (attachmentsByMessageId.isEmpty) return attachmentsByMessageId;
    final fetcher = _runtimeAttachmentContentFetcher();
    if (fetcher == null) return attachmentsByMessageId;

    final hydrated = <String, List<_AgentMessageAttachmentView>>{};
    for (final entry in attachmentsByMessageId.entries) {
      final attachments = <_AgentMessageAttachmentView>[];
      for (final attachment in entry.value) {
        if (!attachment.needsHydratedBytesForPreview ||
            attachment.bytes != null) {
          attachments.add(attachment);
          continue;
        }
        try {
          final bytes = await fetcher.fetchAttachmentBytes(
            vaultId: vaultId,
            attachmentId: attachment.id,
          );
          attachments.add(
            bytes == null || bytes.isEmpty
                ? attachment
                : attachment.copyWith(bytes: bytes),
          );
        } catch (_) {
          attachments.add(attachment);
        }
      }
      hydrated[entry.key] = List<_AgentMessageAttachmentView>.unmodifiable(
        attachments,
      );
    }
    return Map<String, List<_AgentMessageAttachmentView>>.unmodifiable(
      hydrated,
    );
  }
}

_RuntimeMessageProjection _runtimeMessagesFromTurns(
  List<RuntimeConversationTurn> turns, {
  required Map<String, _AgentMessageAttachmentView> localAttachmentsByRef,
  List<RuntimeWorkingSetRecord> mediaRecords =
      const <RuntimeWorkingSetRecord>[],
  required _RuntimeMediaInlineLabels mediaLabels,
}) {
  final messages = <Message>[];
  final attachmentsByMessageId = <String, List<_AgentMessageAttachmentView>>{};
  for (final turn in turns) {
    final message = Message(
      id: turn.turnId,
      conversationId: turn.conversationId,
      role: turn.role,
      content: turn.content,
      createdAtMs: turn.createdAtMs,
      isMemory: true,
      citationsJson: turn.citationsJson,
    );
    messages.add(message);
    final attachments = _messageAttachmentsFromRuntimeTurn(
      turn,
      localAttachmentsByRef: localAttachmentsByRef,
    );
    if (attachments.isNotEmpty) {
      attachmentsByMessageId[message.id] = attachments;
    }
  }
  return _RuntimeMessageProjection(
    messages: messages,
    attachmentsByMessageId: Map.unmodifiable(attachmentsByMessageId),
    mediaResultsByMessageId: _messageMediaResultsFromRuntimeRecords(
      turns: turns,
      mediaRecords: mediaRecords,
      localAttachmentsByRef: localAttachmentsByRef,
      labels: mediaLabels,
    ),
  );
}

List<_AgentMessageAttachmentView> _messageAttachmentsFromRuntimeTurn(
  RuntimeConversationTurn turn, {
  required Map<String, _AgentMessageAttachmentView> localAttachmentsByRef,
}) {
  final rawAttachments = turn.raw['attachments'];
  final parsed = rawAttachments is List
      ? _messageAttachmentsFromRuntimePayloads(
          rawAttachments
              .whereType<Map>()
              .map((item) => item.map(
                    (key, value) => MapEntry('$key', value as Object?),
                  ))
              .toList(growable: false),
        )
      : const <_AgentMessageAttachmentView>[];
  if (parsed.isNotEmpty) {
    return parsed.map((attachment) {
      final local = localAttachmentsByRef[attachment.id.trim()];
      if (attachment.bytes == null && local?.bytes != null) {
        return attachment.copyWith(bytes: local!.bytes);
      }
      return attachment;
    }).toList(growable: false);
  }
  return turn.attachmentRefs
      .map((ref) {
        final normalized = ref.trim();
        final local = localAttachmentsByRef[normalized];
        if (local != null) return local;
        return _AgentMessageAttachmentView(
          id: normalized,
          filename: normalized,
          mimeType: 'application/octet-stream',
          mediaType: 'file',
        );
      })
      .where((attachment) => attachment.id.trim().isNotEmpty)
      .toList(growable: false);
}

List<_AgentMessageAttachmentView> _messageAttachmentsFromRuntimePayloads(
  List<Map<String, Object?>> attachments,
) {
  return attachments
      .map(_messageAttachmentFromRuntimePayload)
      .whereType<_AgentMessageAttachmentView>()
      .toList(growable: false);
}

_AgentMessageAttachmentView? _messageAttachmentFromRuntimePayload(
  Map<String, Object?> attachment,
) {
  final id = _firstRuntimeAttachmentString(
    attachment,
    const ['attachment_id', 'id', 'sha256', 'blob_id'],
  );
  if (id.isEmpty) return null;
  final mimeType = _firstRuntimeAttachmentString(
    attachment,
    const ['mime_type', 'content_type'],
    fallback: 'application/octet-stream',
  );
  return _AgentMessageAttachmentView(
    id: id,
    filename: _firstRuntimeAttachmentString(
      attachment,
      const ['filename', 'display_name', 'name'],
      fallback: id,
    ),
    mimeType: mimeType,
    mediaType: _firstRuntimeAttachmentString(
      attachment,
      const ['media_type', 'type'],
      fallback: _runtimeAttachmentMediaType(mimeType),
    ),
    sizeLabel: _runtimeAttachmentSizeLabel(attachment, mimeType),
    durationLabel: _runtimeAttachmentDurationLabel(attachment),
    bytes: _attachmentBytesFromRuntimePayload(attachment),
  );
}

String _runtimeAttachmentDurationLabel(Map<String, Object?> attachment) {
  final explicitLabel = _firstRuntimeAttachmentString(
    attachment,
    const ['duration_label', 'durationLabel', 'display_duration'],
  );
  if (explicitLabel.isNotEmpty) return explicitLabel;

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
      attachment[entry.$1],
      milliseconds: entry.$2,
    );
    if (label.isNotEmpty) return label;
  }
  return '';
}

String _runtimeDurationLabelFromRaw(
  Object? raw, {
  required bool milliseconds,
}) {
  if (raw == null) return '';
  if (raw is String) {
    final value = raw.trim();
    if (value.isEmpty || value == 'null') return '';
    if (value.contains(':')) return value;
    final parsed = double.tryParse(value);
    if (parsed == null) return value;
    return _runtimeDurationSecondsLabel(
      (milliseconds ? parsed / 1000 : parsed).round(),
    );
  }
  if (raw is num) {
    return _runtimeDurationSecondsLabel(
      (milliseconds ? raw / 1000 : raw).round(),
    );
  }
  return '';
}

String _runtimeDurationSecondsLabel(int totalSeconds) {
  if (totalSeconds <= 0) return '';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _runtimeAttachmentSizeLabel(
  Map<String, Object?> attachment,
  String mimeType,
) {
  final explicitLabel = _firstRuntimeAttachmentString(
    attachment,
    const ['size_label', 'sizeLabel', 'display_size', 'displaySize'],
  );
  if (explicitLabel.isNotEmpty) return explicitLabel;
  final byteLength = _firstRuntimeAttachmentInt(
    attachment,
    const ['byte_len', 'byteLen', 'byte_length', 'byteLength', 'size_bytes'],
  );
  final typeLabel = _runtimeAttachmentTypeLabel(mimeType);
  if (byteLength == null || byteLength <= 0) return typeLabel;
  final sizeLabel = byteLength >= 1024 * 1024
      ? '${(byteLength / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(byteLength / 1024).ceil()} KB';
  return typeLabel.isEmpty ? sizeLabel : '$sizeLabel • $typeLabel';
}

int? _firstRuntimeAttachmentInt(
  Map<String, Object?> attachment,
  List<String> keys,
) {
  for (final key in keys) {
    final value = attachment[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String _runtimeAttachmentTypeLabel(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized == 'application/pdf') return 'PDF';
  if (normalized.startsWith('image/')) return 'Image';
  if (normalized.startsWith('audio/')) return 'Audio';
  if (normalized.startsWith('video/')) return 'Video';
  return '';
}

Uint8List? _attachmentBytesFromRuntimePayload(Map<String, Object?> attachment) {
  final rawBase64 = _firstRuntimeAttachmentString(
    attachment,
    const ['content_base64', 'bytes_base64'],
  );
  final dataUrl = _firstRuntimeAttachmentString(
    attachment,
    const ['data_url', 'image_url'],
  );
  final encoded = rawBase64.isNotEmpty
      ? rawBase64
      : (dataUrl.contains(',') ? dataUrl.split(',').last : '');
  if (encoded.isEmpty) return null;
  try {
    return Uint8List.fromList(base64Decode(encoded));
  } catch (_) {
    return null;
  }
}

String _firstRuntimeAttachmentString(
  Map<String, Object?> attachment,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = '${attachment[key] ?? ''}'.trim();
    if (value.isNotEmpty && value != 'null') return value;
  }
  return fallback;
}

String _attachmentOnlyFallbackText(List<AttachmentDraftPayload> attachments) {
  final names = attachments
      .map((attachment) => attachment.normalizedFilename)
      .where((name) => name.trim().isNotEmpty)
      .toList(growable: false);
  if (names.isEmpty) return 'Uploaded attachment.';
  if (names.length == 1) return 'Uploaded attachment: ${names.single}';
  return 'Uploaded attachments: ${names.join(', ')}';
}

String? _runtimeAttachmentIntent(
  String message,
  List<AttachmentDraftPayload> attachments,
) {
  if (message.trim().isNotEmpty || attachments.isEmpty) return null;
  return 'understand_uploaded_files';
}

Future<List<Map<String, Object?>>> _runtimeAttachmentPayloads(
  List<AttachmentDraftPayload> attachments,
) async {
  final payloads = <Map<String, Object?>>[];
  for (final attachment in attachments) {
    final sha256 = await _sha256Hex(attachment.bytes);
    final mimeType = attachment.normalizedMimeType;
    final mediaType = _runtimeAttachmentMediaType(mimeType);
    final contentBase64 = base64Encode(attachment.bytes);
    payloads.add(<String, Object?>{
      'id': sha256,
      'attachment_id': sha256,
      'blob_id': sha256,
      'sha256': sha256,
      'local_id': attachment.localId,
      'filename': attachment.normalizedFilename,
      'display_name': attachment.normalizedFilename,
      'mime_type': mimeType,
      'media_type': mediaType,
      'byte_size': attachment.bytes.length,
      'size_bytes': attachment.bytes.length,
      'vault_uri': 'vault://attachment/$sha256',
      'content_base64': contentBase64,
      if (mediaType == 'image')
        'data_url': 'data:$mimeType;base64,$contentBase64',
    });
  }
  return payloads;
}

List<Map<String, Object?>> _runtimeMessageAttachmentPayloads(
  List<Map<String, Object?>> attachments,
) {
  return attachments
      .map(
        (attachment) => Map<String, Object?>.from(attachment)
          ..remove('content_base64')
          ..remove('bytes_base64')
          ..remove('data_url')
          ..remove('image_url'),
      )
      .toList(growable: false);
}

String _runtimeAttachmentMediaType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  if (normalized.startsWith('image/')) return 'image';
  if (normalized.startsWith('audio/')) return 'audio';
  if (normalized.startsWith('video/')) return 'video';
  if (normalized == 'application/pdf') return 'document';
  return 'file';
}

Future<String> _sha256Hex(List<int> bytes) async {
  final digest = await Sha256().hash(bytes);
  final buffer = StringBuffer();
  for (final byte in digest.bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
