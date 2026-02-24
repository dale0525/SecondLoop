class AttachmentDeepLink {
  const AttachmentDeepLink({
    required this.attachmentSha256,
    this.kind,
    this.chunk,
  });

  final String attachmentSha256;
  final String? kind;
  final int? chunk;
}

AttachmentDeepLink? parseAttachmentDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'attachment') return null;

  final sha = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
  if (sha.isEmpty) return null;

  final kind = uri.queryParameters['kind']?.trim();
  final chunkRaw = uri.queryParameters['chunk']?.trim();
  final chunk =
      chunkRaw == null || chunkRaw.isEmpty ? null : int.tryParse(chunkRaw);

  return AttachmentDeepLink(
    attachmentSha256: sha,
    kind: (kind == null || kind.isEmpty) ? null : kind,
    chunk: chunk,
  );
}
