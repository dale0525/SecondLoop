class KnowledgeDocumentDeepLink {
  const KnowledgeDocumentDeepLink({
    required this.documentId,
    this.chunkIndex,
    this.unitId,
  });

  final String documentId;
  final int? chunkIndex;
  final String? unitId;
}

KnowledgeDocumentDeepLink? parseKnowledgeDocumentDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'knowledge-document') return null;

  final rawDocumentId = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  final documentId = rawDocumentId.trim();
  if (documentId.isEmpty) return null;

  final chunkIndex = int.tryParse((uri.queryParameters['chunk'] ?? '').trim());
  final rawUnitId = (uri.queryParameters['unit'] ?? '').trim();
  final unitId = rawUnitId.isEmpty
      ? _deriveChunkUnitId(documentId, chunkIndex)
      : rawUnitId;

  return KnowledgeDocumentDeepLink(
    documentId: documentId,
    chunkIndex: chunkIndex,
    unitId: unitId,
  );
}

String? _deriveChunkUnitId(String documentId, int? chunkIndex) {
  if (chunkIndex == null) return null;
  final normalizedDocumentId = documentId.trim();
  if (normalizedDocumentId.isEmpty) return null;
  return '$normalizedDocumentId:chunk:${chunkIndex.toString().padLeft(4, '0')}';
}
