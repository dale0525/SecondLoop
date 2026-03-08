import 'dart:convert';

import 'attachment_draft_send_contract.dart';
import 'attachment_ingest_pipeline.dart';

bool looksLikeHttpUrlText(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  if (uri.host.isEmpty) return false;
  return true;
}

String buildUrlManifestDraftFilename(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return 'shared-link.url';
  final uri = Uri.tryParse(trimmed);
  final host = uri?.host.trim() ?? '';
  if (host.isNotEmpty) return host;
  if (trimmed.length <= 96) return trimmed;
  return '${trimmed.substring(0, 93)}...';
}

AttachmentDraftPayload buildUrlManifestDraftPayload({
  required String localId,
  required String url,
}) {
  final normalized = url.trim();
  return AttachmentDraftPayload(
    localId: localId,
    filename: buildUrlManifestDraftFilename(normalized),
    mimeType: kSecondLoopUrlManifestMimeType,
    bytes: buildUrlManifestAttachmentBytes(normalized),
  );
}

String? readUrlFromManifestDraft(AttachmentDraftPayload draft) {
  final mimeType = draft.normalizedMimeType.trim().toLowerCase();
  if (mimeType != kSecondLoopUrlManifestMimeType) return null;

  try {
    final decoded = jsonDecode(utf8.decode(draft.bytes, allowMalformed: false));
    if (decoded is! Map) return null;
    final schema = decoded['schema'];
    if (schema is! String || schema.trim() != kSecondLoopUrlManifestSchema) {
      return null;
    }
    final url = decoded['url'];
    if (url is! String) return null;
    final normalized = url.trim();
    if (!looksLikeHttpUrlText(normalized)) return null;
    return normalized;
  } catch (_) {
    return null;
  }
}
