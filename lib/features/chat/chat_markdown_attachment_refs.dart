import '../attachments/attachment_deeplink.dart';

final RegExp _kMarkdownImageRefPattern = RegExp(
  r'!\[[^\]]*\]\((<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\)',
);

final class DraftMarkdownImageRef {
  const DraftMarkdownImageRef({required this.localId});

  final String localId;
}

DraftMarkdownImageRef? parseDraftMarkdownImageRef(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'secondloop-draft') return null;
  if (uri.host.toLowerCase() != 'image') return null;
  if (uri.pathSegments.isEmpty) return null;

  final localId = uri.pathSegments.first.trim();
  if (localId.isEmpty) return null;
  return DraftMarkdownImageRef(localId: localId);
}

String buildDraftMarkdownImageSource(String localId) {
  final normalized = localId.trim();
  return 'secondloop-draft://image/$normalized';
}

String buildPersistedMarkdownAttachmentImageSource(String attachmentSha256) {
  final normalized = attachmentSha256.trim();
  return 'secondloop://attachment/$normalized';
}

String rewriteDraftMarkdownImageRefs(
  String markdown,
  Map<String, String> attachmentShaByLocalId,
) {
  if (markdown.isEmpty || attachmentShaByLocalId.isEmpty) {
    return markdown;
  }

  return markdown.replaceAllMapped(_kMarkdownImageRefPattern, (match) {
    final imageSegment = match.group(0);
    final sourceToken = match.group(1);
    if (imageSegment == null || sourceToken == null) {
      return match.group(0) ?? '';
    }

    final source = _unwrapMarkdownImageSource(sourceToken);
    final parsed = parseDraftMarkdownImageRef(source);
    if (parsed == null) {
      return imageSegment;
    }

    final attachmentSha = attachmentShaByLocalId[parsed.localId]?.trim();
    if (attachmentSha == null || attachmentSha.isEmpty) {
      return imageSegment;
    }

    final replacement = buildPersistedMarkdownAttachmentImageSource(
      attachmentSha,
    );
    final wrapped = sourceToken.startsWith('<') && sourceToken.endsWith('>')
        ? '<$replacement>'
        : replacement;
    return imageSegment.replaceFirst(sourceToken, wrapped);
  });
}

Set<String> collectPersistedMarkdownAttachmentShas(String markdown) {
  final shas = <String>{};
  if (markdown.isEmpty) return shas;

  for (final match in _kMarkdownImageRefPattern.allMatches(markdown)) {
    final sourceToken = match.group(1);
    if (sourceToken == null) continue;
    final source = _unwrapMarkdownImageSource(sourceToken);
    final parsed = parseAttachmentDeepLink(source);
    if (parsed == null) continue;
    shas.add(parsed.attachmentSha256);
  }

  return shas;
}

Set<String> collectDraftMarkdownImageLocalIds(String markdown) {
  final localIds = <String>{};
  if (markdown.isEmpty) return localIds;

  for (final match in _kMarkdownImageRefPattern.allMatches(markdown)) {
    final sourceToken = match.group(1);
    if (sourceToken == null) continue;
    final source = _unwrapMarkdownImageSource(sourceToken);
    final parsed = parseDraftMarkdownImageRef(source);
    if (parsed == null) continue;
    localIds.add(parsed.localId);
  }

  return localIds;
}

String _unwrapMarkdownImageSource(String token) {
  final trimmed = token.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('<') && trimmed.endsWith('>')) {
    return trimmed.substring(1, trimmed.length - 1).trim();
  }
  return trimmed;
}
