import 'dart:typed_data';

import '../../core/backend/attachments_backend.dart';
import '../../src/rust/db.dart';

final class AttachmentDeepLink {
  const AttachmentDeepLink({
    required this.sha256,
    this.kind,
    this.chunkIndex,
  });

  final String sha256;
  final String? kind;
  final int? chunkIndex;
}

AttachmentDeepLink? parseAttachmentDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'attachment') return null;

  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final sha = segments.first.trim();
  if (sha.isEmpty) return null;

  final kind = uri.queryParameters['kind']?.trim();
  final chunkRaw = uri.queryParameters['chunk']?.trim();
  final chunkIndex =
      chunkRaw == null || chunkRaw.isEmpty ? null : int.tryParse(chunkRaw);

  return AttachmentDeepLink(
    sha256: sha,
    kind: (kind == null || kind.isEmpty) ? null : kind,
    chunkIndex: chunkIndex,
  );
}

Future<Attachment?> findAttachmentBySha(
  AttachmentsBackend backend,
  Uint8List key, {
  required String sha256,
}) async {
  final normalized = sha256.trim();
  if (normalized.isEmpty) return null;

  final recent = await backend.listRecentAttachments(key, limit: 500);
  for (final attachment in recent) {
    if (attachment.sha256 == normalized) {
      return attachment;
    }
  }
  return null;
}
