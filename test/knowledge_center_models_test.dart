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
}
