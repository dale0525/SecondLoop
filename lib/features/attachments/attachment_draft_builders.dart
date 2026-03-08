import 'dart:typed_data';

import 'attachment_draft_send_contract.dart';

String resolveAttachmentDraftFilename(
  String? filename, {
  String fallback = 'attachment.bin',
}) {
  final trimmed = (filename ?? '').trim();
  if (trimmed.isNotEmpty) return trimmed;
  return fallback;
}

AttachmentDraftPayload buildAttachmentDraftPayload({
  required String localId,
  required String? filename,
  required String mimeType,
  required Uint8List rawBytes,
  String fallbackFilename = 'attachment.bin',
}) {
  return AttachmentDraftPayload(
    localId: localId,
    filename: resolveAttachmentDraftFilename(
      filename,
      fallback: fallbackFilename,
    ),
    mimeType: mimeType,
    bytes: rawBytes,
  );
}

AttachmentDraftPayload buildImageAttachmentDraftPayload({
  required String localId,
  required Uint8List rawBytes,
  required String inferredMimeType,
  String? filename,
}) {
  return buildAttachmentDraftPayload(
    localId: localId,
    filename: filename,
    mimeType: inferredMimeType,
    rawBytes: rawBytes,
    fallbackFilename: 'photo.jpg',
  );
}

String inferImageMimeTypeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heif';
  return 'image/jpeg';
}

String inferAttachmentMimeTypeFromFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif')) {
    return inferImageMimeTypeFromPath(filename);
  }
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.ini')) return 'text/plain';
  if (lower.endsWith('.md')) return 'text/markdown';
  if (lower.endsWith('.csv')) return 'text/csv';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
  if (lower.endsWith('.xml')) return 'application/xml';
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
    return 'application/x-yaml';
  }
  if (lower.endsWith('.toml')) return 'application/toml';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.aac')) return 'audio/aac';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.flac')) return 'audio/flac';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.opus')) return 'audio/opus';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.m4v')) return 'video/x-m4v';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.mkv')) return 'video/x-matroska';
  if (lower.endsWith('.avi')) return 'video/x-msvideo';
  if (lower.endsWith('.wmv')) return 'video/x-ms-wmv';
  if (lower.endsWith('.flv')) return 'video/x-flv';
  if (lower.endsWith('.mpeg') || lower.endsWith('.mpg')) {
    return 'video/mpeg';
  }
  if (lower.endsWith('.ts') ||
      lower.endsWith('.m2ts') ||
      lower.endsWith('.mts')) {
    return 'video/mp2t';
  }
  if (lower.endsWith('.3gp')) return 'video/3gpp';
  if (lower.endsWith('.3g2')) return 'video/3gpp2';
  if (lower.endsWith('.asf')) return 'video/x-ms-asf';
  if (lower.endsWith('.ogv')) return 'video/ogg';
  return 'application/octet-stream';
}

List<AttachmentDraftPayload> buildDesktopAttachmentDraftPayloads(
  List<({String filename, Uint8List bytes})> payloads, {
  required String Function() nextLocalId,
}) {
  return payloads
      .map(
        (payload) => buildAttachmentDraftPayload(
          localId: nextLocalId(),
          filename: payload.filename,
          mimeType: inferAttachmentMimeTypeFromFilename(payload.filename),
          rawBytes: payload.bytes,
        ),
      )
      .toList(growable: false);
}
