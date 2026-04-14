import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/history.dart';
import '../../src/rust/knowledge/pages.dart';
import 'knowledge_page_display_text.dart';

class KnowledgeCenterHomeData {
  const KnowledgeCenterHomeData({
    required this.currentMe,
    required this.needsAttention,
    required this.recentChanges,
    required this.directory,
    required this.systemActivity,
  });

  final List<KnowledgePageSummary> currentMe;
  final List<KnowledgePageSummary> needsAttention;
  final List<KnowledgeRecentChangeItem> recentChanges;
  final List<KnowledgeDirectoryEntry> directory;
  final KnowledgeSystemActivityData systemActivity;
}

class KnowledgeRecentChangeItem {
  const KnowledgeRecentChangeItem({
    required this.page,
    required this.record,
  });

  final KnowledgePageSummary page;
  final KnowledgePageChangeRecord record;
}

class KnowledgeDirectoryEntry {
  const KnowledgeDirectoryEntry({
    required this.pageType,
    required this.pages,
  });

  final KnowledgePageType pageType;
  final List<KnowledgePageSummary> pages;
}

class KnowledgeSystemActivityData {
  const KnowledgeSystemActivityData({
    required this.totalPages,
    required this.pagesNeedingReview,
    required this.pagesUsedInAnswersRecently,
  });

  final int totalPages;
  final int pagesNeedingReview;
  final List<KnowledgePageSummary> pagesUsedInAnswersRecently;
}

KnowledgeCenterHomeData buildKnowledgeCenterHomeData({
  required List<KnowledgePageSummary> summaries,
  required List<KnowledgePageChangeRecord> recentChangeRecords,
  Map<String, KnowledgePageSummary> recentChangePagesById = const {},
}) {
  final currentMeTypes = <KnowledgePageType>{
    KnowledgePageType.aboutMe,
    KnowledgePageType.preferences,
    KnowledgePageType.currentFocus,
    KnowledgePageType.activeThreads,
  };
  final currentMe = summaries
      .where((page) =>
          page.state == KnowledgePageState.active &&
          currentMeTypes.contains(page.pageType))
      .toList(growable: false)
    ..sort(_sortByLastUsedThenUpdated);

  final needsAttention = summaries
      .where((page) =>
          page.state == KnowledgePageState.needsReview ||
          page.state == KnowledgePageState.outdated ||
          page.conflictCount > 0 ||
          page.sourceCount <= 1)
      .toList(growable: false)
    ..sort(_sortByLastUsedThenUpdated);

  final summariesByPageId = <String, KnowledgePageSummary>{
    for (final page in summaries) page.pageId: page,
  };
  final recentChanges = recentChangeRecords
      .map((record) {
        final page = summariesByPageId[record.pageId] ??
            recentChangePagesById[record.pageId];
        if (page == null) return null;
        return KnowledgeRecentChangeItem(page: page, record: record);
      })
      .nonNulls
      .toList(growable: false);

  final directory = _directoryOrder
      .map((type) {
        final pages = summaries
            .where((page) => page.pageType == type)
            .toList(growable: false)
          ..sort(_sortByLastUsedThenUpdated);
        if (pages.isEmpty) return null;
        return KnowledgeDirectoryEntry(pageType: type, pages: pages);
      })
      .nonNulls
      .toList(growable: false);

  final pagesUsedInAnswersRecently = summaries
      .where((page) =>
          page.answerPolicy.defaultAllowed && page.lastUsedAtMs != null)
      .toList(growable: false)
    ..sort(_sortByLastUsedThenUpdated);

  return KnowledgeCenterHomeData(
    currentMe: currentMe.take(5).toList(growable: false),
    needsAttention: needsAttention.take(6).toList(growable: false),
    recentChanges: recentChanges.take(8).toList(growable: false),
    directory: directory,
    systemActivity: KnowledgeSystemActivityData(
      totalPages: summaries.length,
      pagesNeedingReview: needsAttention.length,
      pagesUsedInAnswersRecently:
          pagesUsedInAnswersRecently.take(3).toList(growable: false),
    ),
  );
}

const List<KnowledgePageType> _directoryOrder = <KnowledgePageType>[
  KnowledgePageType.aboutMe,
  KnowledgePageType.preferences,
  KnowledgePageType.currentFocus,
  KnowledgePageType.activeThreads,
  KnowledgePageType.recentEvents,
  KnowledgePageType.people,
  KnowledgePageType.topics,
  KnowledgePageType.openQuestions,
];

int _sortByLastUsedThenUpdated(
  KnowledgePageSummary left,
  KnowledgePageSummary right,
) {
  final lastUsedCompare =
      (right.lastUsedAtMs ?? 0).compareTo(left.lastUsedAtMs ?? 0);
  if (lastUsedCompare != 0) return lastUsedCompare;
  return right.updatedAtMs.compareTo(left.updatedAtMs);
}

String knowledgeCenterSectionLabel(
  Translations t,
  KnowledgeCenterSectionKey key,
) {
  return switch (key) {
    KnowledgeCenterSectionKey.currentMe => t.memory.homepage.currentMe,
    KnowledgeCenterSectionKey.needsAttention =>
      t.memory.homepage.needsAttention,
    KnowledgeCenterSectionKey.recentChanges => t.memory.homepage.recentChanges,
    KnowledgeCenterSectionKey.myWiki => t.memory.homepage.myWiki,
    KnowledgeCenterSectionKey.systemActivity =>
      t.memory.homepage.systemActivity,
  };
}

enum KnowledgeCenterSectionKey {
  currentMe,
  needsAttention,
  recentChanges,
  myWiki,
  systemActivity,
}

String knowledgeDirectorySubtitle(
  Translations t,
  KnowledgeDirectoryEntry entry,
) {
  return t.memory.homepage.directoryCount(count: entry.pages.length);
}

String knowledgeRecentChangeSummary(
  Translations t,
  KnowledgeRecentChangeItem item,
) {
  final reason = item.record.reason?.trim();
  if (reason != null && reason.isNotEmpty) return reason;
  return knowledgePageChangeTypeLabel(t, item.record.changeType);
}

String knowledgeAttentionReason(
  Translations t,
  KnowledgePageSummary page,
) {
  if (page.state == KnowledgePageState.outdated) {
    return t.memory.homepage.outdatedReason;
  }
  if (page.conflictCount > 0) {
    return t.memory.detail.conflictingEvidencePresent;
  }
  if (page.sourceCount <= 1) {
    return t.memory.homepage.reviewReason;
  }
  return t.memory.homepage.reviewReason;
}
