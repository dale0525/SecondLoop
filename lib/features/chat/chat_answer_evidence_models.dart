class ChatAnswerEvidence {
  const ChatAnswerEvidence({
    required this.directSources,
  });

  final List<ChatAnswerEvidenceDirectSource> directSources;

  bool get hasEvidence => directSources.isNotEmpty;

  List<ChatAnswerEvidenceDirectSource> findDirectSourcesByHref(String href) {
    final normalized = href.trim();
    if (normalized.isEmpty) return const <ChatAnswerEvidenceDirectSource>[];
    return directSources
        .where((source) => source.href == normalized)
        .toList(growable: false);
  }

  bool hasDirectSourceForHref(String href) =>
      findDirectSourcesByHref(href).isNotEmpty;

  List<int> directSourceIndexesForHref(String href) {
    final normalized = href.trim();
    if (normalized.isEmpty) return const <int>[];
    final indexes = <int>[];
    for (var i = 0; i < directSources.length; i += 1) {
      if (directSources[i].href == normalized) {
        indexes.add(i + 1);
      }
    }
    return indexes;
  }

  String? chipLabelForHref(String href) {
    final indexes = directSourceIndexesForHref(href);
    if (indexes.isEmpty) return null;
    if (indexes.length == 1) {
      return '[${indexes.single}]';
    }
    return '[${indexes.join(', ')}]';
  }
}

class ChatAnswerEvidenceDirectSource {
  const ChatAnswerEvidenceDirectSource({
    required this.id,
    required this.href,
    required this.sourceType,
    required this.label,
    required this.sourceTypeLabel,
    required this.scopeLabel,
    required this.confidenceLabel,
    required this.title,
    required this.snippet,
    required this.highlightedText,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.documentId,
    required this.unitId,
  });

  final String id;
  final String href;
  final String sourceType;
  final String label;
  final String? sourceTypeLabel;
  final String? scopeLabel;
  final String? confidenceLabel;
  final String? title;
  final String snippet;
  final String? highlightedText;
  final int? createdAtMs;
  final int? updatedAtMs;
  final String? documentId;
  final String? unitId;

  String get displayTitle {
    final normalizedTitle = title?.trim();
    if (normalizedTitle != null && normalizedTitle.isNotEmpty) {
      return normalizedTitle;
    }
    final normalizedLabel = label.trim();
    if (normalizedLabel.isNotEmpty) {
      return normalizedLabel;
    }
    return sourceTypeDisplayLabel(sourceType);
  }

  String get displaySnippet {
    final highlight = highlightedText?.trim();
    if (highlight != null && highlight.isNotEmpty) return highlight;
    final normalized = snippet.trim();
    if (normalized.isNotEmpty) return normalized;
    return href;
  }

  String get displaySourceTypeLabel {
    final explicit = sourceTypeLabel?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return sourceTypeDisplayLabel(sourceType);
  }
}

String sourceTypeDisplayLabel(String rawType) {
  final normalized = rawType.trim().toLowerCase();
  return switch (normalized) {
    'item' => 'Item',
    'todo' => 'Item',
    'message' => 'Message',
    'attachment' => 'Attachment',
    'document' => 'Document',
    'transcript' => 'Transcript',
    'summary' => 'Summary',
    _ => _titleCase(rawType),
  };
}

String _titleCase(String value) {
  final words = value
      .trim()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return value.trim();
  return words
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
