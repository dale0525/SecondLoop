part of 'knowledge_page_detail_test.dart';

final class _KnowledgePageDetailBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return KnowledgePageDetail(
      page: KnowledgePage(
        pageId: pageId,
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Reply in Chinese by default.',
        currentBody: 'Reply in Chinese by default.\nKeep answers concise.',
        state: KnowledgePageState.active,
        answerPolicy: const KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        confidenceLevel: 0.92,
        createdAtMs: 1,
        updatedAtMs: 2,
        lastUsedAtMs: 3,
        sourceCount: 2,
        conflictCount: 1,
        humanCorrected: true,
        tags: const ['preferences'],
        primaryEvidenceIds: const ['doc:language', 'doc:style'],
        relatedPageIds: const ['page:about-me'],
      ),
      sourceDocumentIds: const ['doc:language', 'doc:style'],
      claimIds: const ['claim:language', 'claim:style'],
      history: const [
        KnowledgePageChangeRecord(
          changeId: 'change:1',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.corrected,
          actor: 'user',
          reason: 'Manual correction applied.',
          answerImpacted: true,
          createdAtMs: 2,
        ),
      ],
      versionSnapshots: const [
        KnowledgePageVersionSnapshot(
          versionId: 'version:1',
          pageId: 'page:preferences',
          title: 'Reply Preferences',
          summary: 'Reply in Chinese by default.',
          body: 'Reply in Chinese by default.\nKeep answers concise.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          confidenceLevel: 0.92,
          sourceCount: 2,
          conflictCount: 1,
          humanCorrected: true,
          actor: 'user',
          changeType: KnowledgePageChangeType.corrected,
          reason: 'Manual correction applied.',
          createdAtMs: 2,
        ),
      ],
      evidenceEntries: const [
        KnowledgePageEvidenceEntry(
          evidenceId: 'evidence:1',
          kind: KnowledgePageEvidenceKind.support,
          summary: 'Reply in Chinese by default.',
          sourceRefIds: ['doc:language'],
          createdAtMs: 2,
        ),
        KnowledgePageEvidenceEntry(
          evidenceId: 'evidence:2',
          kind: KnowledgePageEvidenceKind.conflict,
          summary: 'There is conflicting language evidence.',
          sourceRefIds: ['doc:style'],
          createdAtMs: 3,
        ),
      ],
      lintRecords: const [
        KnowledgeLintRecord(
          lintId: 'lint:1',
          pageId: 'page:preferences',
          kind: KnowledgeLintKind.conflict,
          summary: 'Conflicting language evidence was detected.',
          createdAtMs: 2,
        ),
      ],
    );
  }

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      const [
        KnowledgePageSummary(
          pageId: 'page:about-me',
          pageType: KnowledgePageType.aboutMe,
          title: 'About Me',
          currentSummary: 'Stable identity details.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 1,
          lastUsedAtMs: 1,
          sourceCount: 1,
          conflictCount: 0,
          humanCorrected: false,
          tags: [],
          primaryEvidenceIds: [],
        ),
      ];

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const [];

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      const [];

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async =>
      throw UnimplementedError();
}

final class _MutableKnowledgePageDetailBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  String? correctedTitle;
  String? correctedSummary;
  String? correctedBody;

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return _buildDetail(pageId: pageId);
  }

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      const [
        KnowledgePageSummary(
          pageId: 'page:about-me',
          pageType: KnowledgePageType.aboutMe,
          title: 'About Me',
          currentSummary: 'Stable identity details.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 1,
          lastUsedAtMs: 1,
          sourceCount: 1,
          conflictCount: 0,
          humanCorrected: false,
          tags: [],
          primaryEvidenceIds: [],
        ),
        KnowledgePageSummary(
          pageId: 'page:recent-events',
          pageType: KnowledgePageType.recentEvents,
          title: 'Recent Events',
          currentSummary: 'Recent changes.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 1,
          lastUsedAtMs: 1,
          sourceCount: 1,
          conflictCount: 0,
          humanCorrected: false,
          tags: [],
          primaryEvidenceIds: [],
        ),
      ];

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const [];

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      const [];

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      _buildDetail(pageId: pageId);

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      _buildDetail(pageId: pageId);

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      _buildDetail(pageId: pageId);

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async {
    correctedTitle = title;
    correctedSummary = summary;
    correctedBody = body;
    return _buildDetail(pageId: pageId);
  }

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      _buildDetail(pageId: pageId);

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async =>
      _buildDetail(pageId: pageId);
}

final class _ReloadAwareKnowledgePageDetailBackendStub
    extends _KnowledgePageDetailBackendStub {
  int loadCount = 0;
  List<int>? lastLoadedKey;

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    loadCount += 1;
    lastLoadedKey = List<int>.from(key);
    return super.getKnowledgePageDetail(key, pageId: pageId);
  }
}

final class _EvidenceCountKnowledgePageDetailBackendStub
    extends _KnowledgePageDetailBackendStub {
  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return _buildDetail(
      pageId: pageId,
      sourceCount: 4,
      evidenceEntries: const [
        KnowledgePageEvidenceEntry(
          evidenceId: 'evidence:1',
          kind: KnowledgePageEvidenceKind.support,
          summary: 'Reply in Chinese by default.',
          sourceRefIds: ['doc:language'],
          createdAtMs: 2,
        ),
        KnowledgePageEvidenceEntry(
          evidenceId: 'evidence:2',
          kind: KnowledgePageEvidenceKind.conflict,
          summary: 'There is conflicting language evidence.',
          sourceRefIds: ['doc:style'],
          createdAtMs: 3,
        ),
      ],
    );
  }
}

final class _RemovedKnowledgePageDetailBackendStub
    extends _KnowledgePageDetailBackendStub {
  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return _buildDetail(
      pageId: pageId,
      state: KnowledgePageState.removed,
      answerAllowed: false,
    );
  }
}

final class _ArchivedKnowledgePageDetailBackendStub
    extends _KnowledgePageDetailBackendStub {
  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return _buildDetail(
      pageId: pageId,
      state: KnowledgePageState.archived,
      answerAllowed: false,
    );
  }
}

final class _NeedsReviewKnowledgePageDetailBackendStub
    extends _KnowledgePageDetailBackendStub {
  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return _buildDetail(
      pageId: pageId,
      state: KnowledgePageState.needsReview,
      answerAllowed: false,
    );
  }
}

final class _MergeableKnowledgePageDetailBackendStub
    extends _MutableKnowledgePageDetailBackendStub {
  String? mergedPageId;
  String? mergedTargetPageId;

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    if (pageId == 'page:topics:beta') {
      return _buildDetail(
        pageId: pageId,
        pageType: KnowledgePageType.topics,
        title: 'Topic Beta',
        summary: 'Merged topic summary.',
        body: 'Merged topic summary.\nTopic beta details.',
        relatedPageIds: const ['page:about-me', 'page:topics:alpha'],
        tags: const ['topics'],
      );
    }
    return _buildDetail(
      pageId: pageId,
      pageType: KnowledgePageType.topics,
      title: 'Topic Alpha',
      summary: 'Current topic summary.',
      body: 'Current topic summary.\nTopic alpha details.',
      relatedPageIds: const ['page:about-me', 'page:topics:beta'],
      tags: const ['topics'],
    );
  }

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      const [
        KnowledgePageSummary(
          pageId: 'page:topics:beta',
          pageType: KnowledgePageType.topics,
          title: 'Topic Beta',
          currentSummary: 'Related topic summary.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 2,
          lastUsedAtMs: 2,
          sourceCount: 1,
          conflictCount: 0,
          humanCorrected: false,
          tags: [],
          primaryEvidenceIds: [],
        ),
        KnowledgePageSummary(
          pageId: 'page:about-me',
          pageType: KnowledgePageType.aboutMe,
          title: 'About Me',
          currentSummary: 'Stable identity details.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 1,
          lastUsedAtMs: 1,
          sourceCount: 1,
          conflictCount: 0,
          humanCorrected: false,
          tags: [],
          primaryEvidenceIds: [],
        ),
      ];

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const [
        KnowledgePageSummary(
          pageId: 'page:topics:beta',
          pageType: KnowledgePageType.topics,
          title: 'Topic Beta',
          currentSummary: 'Related topic summary.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 2,
          lastUsedAtMs: 2,
          sourceCount: 1,
          conflictCount: 0,
          humanCorrected: false,
          tags: [],
          primaryEvidenceIds: [],
        ),
      ];

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async {
    mergedPageId = pageId;
    mergedTargetPageId = targetPageId;
    return _buildDetail(
      pageId: pageId,
      pageType: KnowledgePageType.topics,
      title: 'Topic Alpha',
      summary: 'Current topic summary.',
      body: 'Current topic summary.\nTopic alpha details.',
      relatedPageIds: const ['page:about-me', 'page:topics:beta'],
      tags: const ['topics'],
      state: KnowledgePageState.archived,
      answerAllowed: false,
    );
  }
}

final class _UnrelatedMergeableKnowledgePageDetailBackendStub
    extends _MergeableKnowledgePageDetailBackendStub {
  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const [];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    if (pageId == 'page:topics:beta') {
      return _buildDetail(
        pageId: pageId,
        pageType: KnowledgePageType.topics,
        title: 'Topic Beta',
        summary: 'Separate topic summary.',
        body: 'Separate topic summary.\nTopic beta details.',
        relatedPageIds: const ['page:about-me'],
        tags: const ['topics'],
      );
    }
    return _buildDetail(
      pageId: pageId,
      pageType: KnowledgePageType.topics,
      title: 'Topic Alpha',
      summary: 'Current topic summary.',
      body: 'Current topic summary.\nTopic alpha details.',
      relatedPageIds: const ['page:about-me'],
      tags: const ['topics'],
    );
  }
}

final class _ReverseRelatedMergeableKnowledgePageDetailBackendStub
    extends _MergeableKnowledgePageDetailBackendStub {
  final List<String> detailLoadPageIds = <String>[];
  int mergeSummaryLoadCount = 0;

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    detailLoadPageIds.add(pageId);
    if (pageId == 'page:topics:beta') {
      return _buildDetail(
        pageId: pageId,
        pageType: KnowledgePageType.topics,
        title: 'Topic Beta',
        summary: 'Merged topic summary.',
        body: 'Merged topic summary.\nTopic beta details.',
        relatedPageIds: const ['page:about-me', 'page:topics:alpha'],
        tags: const ['topics'],
      );
    }
    return _buildDetail(
      pageId: pageId,
      pageType: KnowledgePageType.topics,
      title: 'Topic Alpha',
      summary: 'Current topic summary.',
      body: 'Current topic summary.\nTopic alpha details.',
      relatedPageIds: const ['page:about-me'],
      tags: const ['topics'],
    );
  }

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async {
    mergeSummaryLoadCount += 1;
    return const [
      KnowledgePageSummary(
        pageId: 'page:topics:beta',
        pageType: KnowledgePageType.topics,
        title: 'Topic Beta',
        currentSummary: 'Merged topic summary.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 4,
        lastUsedAtMs: 3,
        sourceCount: 2,
        conflictCount: 0,
        humanCorrected: false,
        tags: ['topics'],
        primaryEvidenceIds: ['doc:beta'],
      ),
    ];
  }
}

final class _RelatedSummaryKnowledgePageDetailBackendStub
    extends _KnowledgePageDetailBackendStub
    implements KnowledgePageSummariesByIdBackend {
  int fullSummaryLoadCount = 0;
  final List<List<String>> relatedSummaryRequests = <List<String>>[];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async {
    return _buildDetail(
      pageId: pageId,
      relatedPageIds: const ['page:about-me', 'page:recent-events'],
    );
  }

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async {
    fullSummaryLoadCount += 1;
    return super.listKnowledgePageSummaries(key);
  }

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummariesByIds(
    Uint8List key, {
    required List<String> pageIds,
  }) async {
    relatedSummaryRequests.add(List<String>.from(pageIds));
    return [
      for (final pageId in pageIds)
        switch (pageId) {
          'page:about-me' => const KnowledgePageSummary(
              pageId: 'page:about-me',
              pageType: KnowledgePageType.aboutMe,
              title: 'About Me',
              currentSummary: 'Stable identity details.',
              state: KnowledgePageState.active,
              answerPolicy: KnowledgeAnswerPolicy(
                defaultAllowed: true,
                requiresTemporalFraming: false,
              ),
              updatedAtMs: 1,
              lastUsedAtMs: 1,
              sourceCount: 1,
              conflictCount: 0,
              humanCorrected: false,
              tags: [],
              primaryEvidenceIds: [],
            ),
          'page:recent-events' => const KnowledgePageSummary(
              pageId: 'page:recent-events',
              pageType: KnowledgePageType.recentEvents,
              title: 'Recent Events',
              currentSummary: 'Recent changes.',
              state: KnowledgePageState.active,
              answerPolicy: KnowledgeAnswerPolicy(
                defaultAllowed: true,
                requiresTemporalFraming: false,
              ),
              updatedAtMs: 1,
              lastUsedAtMs: 1,
              sourceCount: 1,
              conflictCount: 0,
              humanCorrected: false,
              tags: [],
              primaryEvidenceIds: [],
            ),
          _ => throw StateError('unexpected related page id: $pageId'),
        },
    ];
  }
}

KnowledgePageDetail _buildDetail({
  required String pageId,
  KnowledgePageType pageType = KnowledgePageType.preferences,
  String title = 'Preferences',
  String summary = 'Reply in Chinese by default.',
  String body = 'Reply in Chinese by default.\nKeep answers concise.',
  List<String> tags = const ['preferences'],
  List<String> relatedPageIds = const ['page:about-me', 'page:recent-events'],
  KnowledgePageState state = KnowledgePageState.active,
  bool answerAllowed = true,
  int sourceCount = 2,
  List<KnowledgePageEvidenceEntry> evidenceEntries = const [
    KnowledgePageEvidenceEntry(
      evidenceId: 'evidence:1',
      kind: KnowledgePageEvidenceKind.support,
      summary: 'Reply in Chinese by default.',
      sourceRefIds: ['doc:language'],
      createdAtMs: 2,
    ),
    KnowledgePageEvidenceEntry(
      evidenceId: 'evidence:2',
      kind: KnowledgePageEvidenceKind.conflict,
      summary: 'There is conflicting language evidence.',
      sourceRefIds: ['doc:style'],
      createdAtMs: 3,
    ),
  ],
}) {
  return KnowledgePageDetail(
    page: KnowledgePage(
      pageId: pageId,
      pageType: pageType,
      title: title,
      currentSummary: summary,
      currentBody: body,
      state: state,
      answerPolicy: KnowledgeAnswerPolicy(
        defaultAllowed: answerAllowed,
        requiresTemporalFraming: false,
      ),
      confidenceLevel: 0.92,
      createdAtMs: 1,
      updatedAtMs: 2,
      lastUsedAtMs: 3,
      sourceCount: sourceCount,
      conflictCount: 1,
      humanCorrected: true,
      tags: tags,
      primaryEvidenceIds: const ['doc:language', 'doc:style'],
      relatedPageIds: relatedPageIds,
    ),
    sourceDocumentIds: const ['doc:language', 'doc:style'],
    claimIds: const ['claim:language', 'claim:style'],
    history: [
      KnowledgePageChangeRecord(
        changeId: 'change:1',
        pageId: pageId,
        changeType: KnowledgePageChangeType.corrected,
        actor: 'user',
        reason: 'Manual correction applied.',
        answerImpacted: true,
        createdAtMs: 2,
      ),
    ],
    versionSnapshots: [
      KnowledgePageVersionSnapshot(
        versionId: 'version:1',
        pageId: pageId,
        title: title,
        summary: summary,
        body: body,
        state: state,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: answerAllowed,
          requiresTemporalFraming: false,
        ),
        confidenceLevel: 0.92,
        sourceCount: sourceCount,
        conflictCount: 1,
        humanCorrected: true,
        actor: 'user',
        changeType: KnowledgePageChangeType.corrected,
        reason: 'Manual correction applied.',
        createdAtMs: 2,
      ),
    ],
    evidenceEntries: evidenceEntries,
    lintRecords: const [
      KnowledgeLintRecord(
        lintId: 'lint:1',
        pageId: 'page:preferences',
        kind: KnowledgeLintKind.conflict,
        summary: 'Conflicting language evidence was detected.',
        createdAtMs: 2,
      ),
    ],
  );
}
