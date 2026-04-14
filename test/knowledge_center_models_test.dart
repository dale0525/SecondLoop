import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/knowledge_center/knowledge_center_models.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

void main() {
  test(
      'buildKnowledgeCenterHomeData does not treat related pages as attention by default',
      () {
    final summaries = <KnowledgePageSummary>[
      const KnowledgePageSummary(
        pageId: 'page:preferences',
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Reply in Chinese.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 10,
        lastUsedAtMs: 10,
        sourceCount: 2,
        conflictCount: 0,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
      const KnowledgePageSummary(
        pageId: 'page:about-me',
        pageType: KnowledgePageType.aboutMe,
        title: 'About Me',
        currentSummary: 'Stable identity.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 9,
        lastUsedAtMs: 9,
        sourceCount: 2,
        conflictCount: 0,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
    ];

    final data = buildKnowledgeCenterHomeData(
      summaries: summaries,
      recentChangeRecords: const <KnowledgePageChangeRecord>[],
    );

    expect(data.needsAttention, isEmpty);
    expect(
        data.currentMe.map((page) => page.pageId),
        containsAll(<String>[
          'page:preferences',
          'page:about-me',
        ]));
  });

  test(
      'buildKnowledgeCenterHomeData only lists pages used in answers recently when they were actually used',
      () {
    final summaries = <KnowledgePageSummary>[
      const KnowledgePageSummary(
        pageId: 'page:preferences',
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Reply in Chinese.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 10,
        lastUsedAtMs: 10,
        sourceCount: 2,
        conflictCount: 0,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
      const KnowledgePageSummary(
        pageId: 'page:topics',
        pageType: KnowledgePageType.topics,
        title: 'Topics',
        currentSummary: 'Potentially useful later.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 9,
        lastUsedAtMs: null,
        sourceCount: 2,
        conflictCount: 0,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
    ];

    final data = buildKnowledgeCenterHomeData(
      summaries: summaries,
      recentChangeRecords: const <KnowledgePageChangeRecord>[],
    );

    expect(
      data.systemActivity.pagesUsedInAnswersRecently.map((page) => page.pageId),
      <String>['page:preferences'],
    );
  });

  test(
      'buildKnowledgeCenterHomeData does not treat single-source active pages as needing review',
      () {
    final summaries = <KnowledgePageSummary>[
      const KnowledgePageSummary(
        pageId: 'page:topics:solo',
        pageType: KnowledgePageType.topics,
        title: 'Solo Topic',
        currentSummary: 'Only one supporting memory.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: true,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 10,
        lastUsedAtMs: 10,
        sourceCount: 1,
        conflictCount: 0,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
    ];

    final data = buildKnowledgeCenterHomeData(
      summaries: summaries,
      recentChangeRecords: const <KnowledgePageChangeRecord>[],
    );

    expect(data.needsAttention, isEmpty);
    expect(data.systemActivity.pagesNeedingReview, 0);
  });

  test(
      'buildKnowledgeCenterHomeData keeps audit-only pages out of needs attention',
      () {
    final summaries = <KnowledgePageSummary>[
      const KnowledgePageSummary(
        pageId: 'page:preferences',
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Archived preference page.',
        state: KnowledgePageState.archived,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: false,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 10,
        lastUsedAtMs: null,
        sourceCount: 3,
        conflictCount: 2,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
      const KnowledgePageSummary(
        pageId: 'page:topics:removed',
        pageType: KnowledgePageType.topics,
        title: 'Removed Topic',
        currentSummary: 'Removed topic page.',
        state: KnowledgePageState.removed,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: false,
          requiresTemporalFraming: false,
        ),
        updatedAtMs: 11,
        lastUsedAtMs: null,
        sourceCount: 2,
        conflictCount: 1,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
      ),
    ];

    final data = buildKnowledgeCenterHomeData(
      summaries: summaries,
      recentChangeRecords: const <KnowledgePageChangeRecord>[],
    );

    expect(data.needsAttention, isEmpty);
    expect(data.systemActivity.pagesNeedingReview, 0);
  });
}
