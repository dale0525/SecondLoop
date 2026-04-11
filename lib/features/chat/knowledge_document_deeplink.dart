class KnowledgeDocumentDeepLink {
  const KnowledgeDocumentDeepLink({required this.documentId});

  final String documentId;
}

KnowledgeDocumentDeepLink? parseKnowledgeDocumentDeepLink(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  if (uri.scheme.toLowerCase() != 'secondloop') return null;
  if (uri.host.toLowerCase() != 'knowledge-document') return null;

  final rawDocumentId = uri.pathSegments.isEmpty
      ? ''
      : Uri.decodeComponent(uri.pathSegments.first);
  final documentId = rawDocumentId.trim();
  if (documentId.isEmpty) return null;

  return KnowledgeDocumentDeepLink(documentId: documentId);
}
