part of 'agent_conversation_page.dart';

final class _RuntimeMessageProjection {
  const _RuntimeMessageProjection({
    required this.messages,
    required this.attachmentsByMessageId,
  });

  final List<Message> messages;
  final Map<String, List<_AgentMessageAttachmentView>> attachmentsByMessageId;
}

final class _AgentMessageAttachmentView {
  const _AgentMessageAttachmentView({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.mediaType,
    this.bytes,
  });

  final String id;
  final String filename;
  final String mimeType;
  final String mediaType;
  final Uint8List? bytes;

  bool get isImage {
    final normalizedMediaType = mediaType.trim().toLowerCase();
    final normalizedMimeType = mimeType.trim().toLowerCase();
    return normalizedMediaType == 'image' ||
        normalizedMimeType.startsWith('image/');
  }
}

_RuntimeMessageProjection _runtimeMessagesFromTurns(
  List<RuntimeConversationTurn> turns, {
  required Map<String, _AgentMessageAttachmentView> localAttachmentsByRef,
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
  if (parsed.isNotEmpty) return parsed;
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
    bytes: _attachmentBytesFromRuntimePayload(attachment),
  );
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
