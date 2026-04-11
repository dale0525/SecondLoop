import '../../src/rust/knowledge/models.dart';

enum MemoryCenterSection {
  preferences,
  people,
  projects,
  topics,
  recentEvents,
}

enum MemoryCardStatus {
  confirmed,
  inferred,
  maybeOutdated,
}

class MemoryCenterCard {
  const MemoryCenterCard({
    required this.documentId,
    required this.title,
    required this.summary,
    required this.updatedAtMs,
    required this.sourceCount,
    required this.section,
    required this.status,
  });

  final String documentId;
  final String title;
  final String summary;
  final int updatedAtMs;
  final int sourceCount;
  final MemoryCenterSection section;
  final MemoryCardStatus status;
}

class MemoryCenterSectionData {
  const MemoryCenterSectionData({
    required this.section,
    required this.cards,
  });

  final MemoryCenterSection section;
  final List<MemoryCenterCard> cards;
}

List<MemoryCenterSectionData> buildMemoryCenterSections(
  List<ContentKnowledgeDocument> documents,
) {
  final bySection = <MemoryCenterSection, List<MemoryCenterCard>>{};
  for (final document in documents) {
    final section = memoryCenterSectionForData(document);
    if (section == null) continue;
    final display = document.memoryDisplay;
    bySection.putIfAbsent(section, () => <MemoryCenterCard>[]).add(
          MemoryCenterCard(
            documentId: document.documentId,
            title: _memoryTitleForDocument(document),
            summary: _memorySummaryForDocument(document),
            updatedAtMs: document.updatedAtMs,
            sourceCount: display?.sourceCount.toInt() ?? 1,
            section: section,
            status: _deriveStatus(document),
          ),
        );
  }

  final orderedSections = <MemoryCenterSection>[
    MemoryCenterSection.preferences,
    MemoryCenterSection.people,
    MemoryCenterSection.projects,
    MemoryCenterSection.topics,
    MemoryCenterSection.recentEvents,
  ];

  return orderedSections
      .where(bySection.containsKey)
      .map(
        (section) => MemoryCenterSectionData(
          section: section,
          cards: (bySection[section]!
                ..sort(
                  (left, right) =>
                      right.updatedAtMs.compareTo(left.updatedAtMs),
                ))
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}

MemoryCenterSection? memoryCenterSectionForDocument(String documentId) {
  final normalized = documentId.trim();
  if (normalized.startsWith('generated:preference:')) {
    return MemoryCenterSection.preferences;
  }
  if (normalized.startsWith('generated:profile:')) {
    return MemoryCenterSection.people;
  }
  if (normalized.startsWith('generated:pattern:')) {
    return MemoryCenterSection.topics;
  }
  if (normalized.startsWith('generated:event:')) {
    return MemoryCenterSection.recentEvents;
  }
  return null;
}

MemoryCenterSection? memoryCenterSectionForData(
  ContentKnowledgeDocument document,
) {
  final display = document.memoryDisplay;
  if (display != null) {
    return switch (display.section) {
      KnowledgeMemorySection.preference => MemoryCenterSection.preferences,
      KnowledgeMemorySection.person => MemoryCenterSection.people,
      KnowledgeMemorySection.project => MemoryCenterSection.projects,
      KnowledgeMemorySection.topic => MemoryCenterSection.topics,
      KnowledgeMemorySection.recentEvent => MemoryCenterSection.recentEvents,
    };
  }
  return memoryCenterSectionForDocument(document.documentId);
}

MemoryCardStatus _deriveStatus(ContentKnowledgeDocument document) {
  switch (document.memoryDisplay?.status ?? document.memoryFeedback.status) {
    case KnowledgeMemoryStatus.confirmed:
      return MemoryCardStatus.confirmed;
    case KnowledgeMemoryStatus.maybeOutdated:
      return MemoryCardStatus.maybeOutdated;
    case KnowledgeMemoryStatus.inferred:
      return MemoryCardStatus.inferred;
    case null:
      break;
  }
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final ageMs = nowMs - document.updatedAtMs;
  if (document.documentId.startsWith('generated:event:') &&
      ageMs > const Duration(days: 30).inMilliseconds) {
    return MemoryCardStatus.maybeOutdated;
  }
  return MemoryCardStatus.inferred;
}

String _memoryTitleForDocument(ContentKnowledgeDocument document) {
  final explicit = document.title?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final parts = document.documentId.split(':');
  if (parts.length >= 3) {
    return _titleCase(parts.sublist(2).join(' '));
  }
  return _titleCase(document.documentId.replaceAll(':', ' '));
}

String _memorySummaryForDocument(ContentKnowledgeDocument document) {
  final summary = document.summary?.trim();
  if (summary != null && summary.isNotEmpty) {
    return summary;
  }

  final raw = document.rawText.trim();
  if (raw.isNotEmpty) {
    return raw.split('\n').first.trim();
  }
  return document.normalizedText.trim();
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
