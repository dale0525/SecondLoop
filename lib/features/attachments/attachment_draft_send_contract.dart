import 'dart:typed_data';

enum AttachmentDraftItemStatus {
  queued,
  ingesting,
  linked,
  failed,
}

enum SendFailureKind {
  messageCreateFailed,
  ingestFailed,
  linkFailed,
  unsupportedFile,
}

final class AttachmentDraftPayload {
  const AttachmentDraftPayload({
    required this.localId,
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  final String localId;
  final String filename;
  final String mimeType;
  final Uint8List bytes;

  String get normalizedFilename {
    final trimmed = filename.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'attachment.bin';
  }

  String get normalizedMimeType {
    final trimmed = mimeType.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return 'application/octet-stream';
  }

  String fingerprint() {
    final name = normalizedFilename.toLowerCase();
    final mime = normalizedMimeType.toLowerCase();
    final hash = _fnv1a64Hex(bytes);
    return '$name|$mime|${bytes.length}|$hash';
  }
}

final class AttachmentDraftProgress {
  const AttachmentDraftProgress({
    required this.localId,
    required this.status,
    this.attachmentSha256,
    this.failureKind,
    this.error,
  });

  final String localId;
  final AttachmentDraftItemStatus status;
  final String? attachmentSha256;
  final SendFailureKind? failureKind;
  final String? error;
}

final class FailedAttachmentDraft {
  const FailedAttachmentDraft({
    required this.payload,
    required this.kind,
    this.error,
  });

  final AttachmentDraftPayload payload;
  final SendFailureKind kind;
  final String? error;
}

final class SendDraftResult {
  SendDraftResult({
    required this.messageId,
    required this.sourceMessageId,
    required List<String> linkedAttachmentShas,
    required List<FailedAttachmentDraft> failedItems,
    required this.attemptedCount,
  })  : linkedAttachmentShas = List<String>.unmodifiable(linkedAttachmentShas),
        failedItems = List<FailedAttachmentDraft>.unmodifiable(failedItems);

  final String? messageId;
  final String? sourceMessageId;
  final List<String> linkedAttachmentShas;
  final List<FailedAttachmentDraft> failedItems;
  final int attemptedCount;
}

List<AttachmentDraftPayload> dedupeAttachmentDraftPayloads(
  List<AttachmentDraftPayload> payloads,
) {
  if (payloads.isEmpty) return const <AttachmentDraftPayload>[];

  final seen = <String>{};
  final deduped = <AttachmentDraftPayload>[];
  for (final payload in payloads) {
    final key = payload.fingerprint();
    if (!seen.add(key)) continue;
    deduped.add(payload);
  }
  return deduped;
}

String _fnv1a64Hex(Uint8List bytes) {
  const fnvOffset = 0xcbf29ce484222325;
  const fnvPrime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;

  var hash = fnvOffset;
  for (final value in bytes) {
    hash ^= value;
    hash = (hash * fnvPrime) & mask;
  }

  return hash.toRadixString(16).padLeft(16, '0');
}
