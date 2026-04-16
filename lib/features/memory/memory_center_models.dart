import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/models.dart';
import 'memory_display_text.dart';

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
  Translations t,
) {
  final bySection = <MemoryCenterSection, List<MemoryCenterCard>>{};
  for (final document in documents) {
    final section = memoryCenterSectionForData(document);
    if (section == null) continue;
    final display = document.memoryDisplay;
    bySection.putIfAbsent(section, () => <MemoryCenterCard>[]).add(
          MemoryCenterCard(
            documentId: document.documentId,
            title: resolveMemoryDisplayTitle(
              t,
              documentId: document.documentId,
              explicitTitle: document.title,
              correctedTitle: document.memoryFeedback.correctedTitle,
            ),
            summary: resolveMemoryDisplaySummary(
              t,
              documentId: document.documentId,
              explicitSummary: document.summary,
              rawText: document.rawText,
              correctedSummary: document.memoryFeedback.correctedSummary,
            ),
            updatedAtMs: document.updatedAtMs.toInt(),
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

bool isMemoryCenterDocument(ContentKnowledgeDocument document) =>
    memoryCenterSectionForData(document) != null;

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
  final ageMs = nowMs - document.updatedAtMs.toInt();
  if (document.documentId.startsWith('generated:event:') &&
      ageMs > const Duration(days: 30).inMilliseconds) {
    return MemoryCardStatus.maybeOutdated;
  }
  return MemoryCardStatus.inferred;
}
