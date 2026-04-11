class ChatAnswerEvidence {
  const ChatAnswerEvidence({
    required this.directSources,
    required this.memoryCards,
  });

  final List<ChatAnswerEvidenceDirectSource> directSources;
  final List<ChatAnswerEvidenceMemoryCard> memoryCards;

  bool get hasEvidence => directSources.isNotEmpty || memoryCards.isNotEmpty;

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

class ChatAnswerEvidenceMemoryCard {
  const ChatAnswerEvidenceMemoryCard({
    required this.documentId,
    required this.title,
    required this.summary,
    this.body,
    required this.sourceKind,
    required this.role,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.status,
    required this.sourceCount,
    required this.whyUsed,
  });

  final String documentId;
  final String? title;
  final String? summary;
  final String? body;
  final String sourceKind;
  final String role;
  final int createdAtMs;
  final int updatedAtMs;
  final String status;
  final int sourceCount;
  final String? whyUsed;

  ChatAnswerEvidenceMemoryCard copyWith({
    String? title,
    String? summary,
    String? body,
    String? status,
    int? sourceCount,
    String? whyUsed,
    int? updatedAtMs,
  }) {
    return ChatAnswerEvidenceMemoryCard(
      documentId: documentId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      body: body ?? this.body,
      sourceKind: sourceKind,
      role: role,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      status: status ?? this.status,
      sourceCount: sourceCount ?? this.sourceCount,
      whyUsed: whyUsed ?? this.whyUsed,
    );
  }

  String get displayTitle {
    final normalizedTitle = title?.trim();
    if (normalizedTitle != null && normalizedTitle.isNotEmpty) {
      return normalizedTitle;
    }
    return fallbackMemoryTitleFromDocumentId(documentId);
  }

  String get displaySummary {
    final normalizedSummary = summary?.trim();
    if (normalizedSummary != null && normalizedSummary.isNotEmpty) {
      return normalizedSummary;
    }
    return documentId;
  }
}

String sourceTypeDisplayLabel(String rawType) {
  final normalized = rawType.trim().toLowerCase();
  return switch (normalized) {
    'message' => 'Message',
    'attachment' => 'Attachment',
    'document' => 'Document',
    'transcript' => 'Transcript',
    'summary' => 'Summary',
    _ => _titleCase(rawType),
  };
}

String fallbackMemoryTitleFromDocumentId(String documentId) {
  final trimmed = documentId.trim();
  if (trimmed.isEmpty) return 'Memory';
  final segments = trimmed.split(':');
  if (segments.length >= 3) {
    return _titleCase(segments.sublist(2).join(' '));
  }
  return _titleCase(trimmed.replaceAll(':', ' '));
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
