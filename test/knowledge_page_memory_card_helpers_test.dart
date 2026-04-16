import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_answer_evidence_models.dart';
import 'package:secondloop/features/chat/knowledge_page_memory_card_helpers.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

void main() {
  test('page-backed evidence correction skips unchanged fields', () {
    final patch = buildPageBackedEvidenceCorrectionPatch(
      currentTitle: 'Preferences',
      currentSummary: 'Reply in Chinese.',
      nextTitle: 'Preferences',
      nextSummary: 'Reply in Chinese.',
    );

    expect(patch.hasChanges, isFalse);
    expect(patch.title, isNull);
    expect(patch.summary, isNull);
    expect(patch.body, isNull);
  });

  test('page-backed evidence correction updates only changed title/summary',
      () {
    final patch = buildPageBackedEvidenceCorrectionPatch(
      currentTitle: 'Preferences',
      currentSummary: 'Reply in Chinese.',
      nextTitle: 'Language Preferences',
      nextSummary: 'Reply in Chinese and keep it concise.',
    );

    expect(patch.hasChanges, isTrue);
    expect(patch.title, 'Language Preferences');
    expect(patch.summary, 'Reply in Chinese and keep it concise.');
    expect(patch.body, isNull);
  });

  test('resolveKnowledgePageCorrectionBody preserves the existing body', () {
    final resolved = resolveKnowledgePageCorrectionBody(
      existingBody: 'Keep the long-form details.',
      summary: 'Short updated summary.',
    );

    expect(resolved, 'Keep the long-form details.');
  });

  test('resolveKnowledgePageCorrectionBody falls back to summary when empty',
      () {
    final resolved = resolveKnowledgePageCorrectionBody(
      existingBody: '   ',
      summary: 'Short updated summary.',
    );

    expect(resolved, 'Short updated summary.');
  });

  test('memory card conversion keeps body and muted state from knowledge page',
      () {
    const card = ChatAnswerEvidenceMemoryCard(
      documentId: 'page:preferences',
      title: 'Old title',
      summary: 'Old summary',
      body: 'Old body',
      sourceKind: 'summary',
      role: 'summary',
      createdAtMs: 1,
      updatedAtMs: 2,
      status: 'inferred',
      sourceCount: 1,
      whyUsed: 'Because it matched',
    );
    const detail = KnowledgePageDetail(
      page: KnowledgePage(
        pageId: 'page:preferences',
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Reply in Chinese.',
        currentBody: 'Reply in Chinese.\nKeep it concise.',
        state: KnowledgePageState.needsReview,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: false,
          requiresTemporalFraming: false,
        ),
        confidenceLevel: 0.9,
        createdAtMs: 1,
        updatedAtMs: 5,
        lastUsedAtMs: 4,
        sourceCount: 3,
        conflictCount: 1,
        humanCorrected: false,
        tags: [],
        primaryEvidenceIds: [],
        relatedPageIds: [],
      ),
      sourceDocumentIds: [],
      claimIds: [],
      history: [],
      versionSnapshots: [],
      evidenceEntries: [],
      lintRecords: [],
    );

    final updated = knowledgePageMemoryCardFromDetail(card, detail);

    expect(updated.body, 'Reply in Chinese.\nKeep it concise.');
    expect(updated.useForAskAi, isFalse);
    expect(updated.markedInaccurate, isTrue);
  });

  test(
      'memory card conversion does not mark needs-review pages as confirmed just because they were corrected',
      () {
    const card = ChatAnswerEvidenceMemoryCard(
      documentId: 'page:preferences',
      title: 'Old title',
      summary: 'Old summary',
      body: 'Old body',
      sourceKind: 'summary',
      role: 'summary',
      createdAtMs: 1,
      updatedAtMs: 2,
      status: 'confirmed',
      sourceCount: 1,
      whyUsed: 'Because it matched',
    );
    const detail = KnowledgePageDetail(
      page: KnowledgePage(
        pageId: 'page:preferences',
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Reply in Chinese.',
        currentBody: 'Reply in Chinese.\nKeep it concise.',
        state: KnowledgePageState.needsReview,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: false,
          requiresTemporalFraming: false,
        ),
        confidenceLevel: 0.9,
        createdAtMs: 1,
        updatedAtMs: 5,
        lastUsedAtMs: 4,
        sourceCount: 3,
        conflictCount: 1,
        humanCorrected: true,
        tags: [],
        primaryEvidenceIds: [],
        relatedPageIds: [],
      ),
      sourceDocumentIds: [],
      claimIds: [],
      history: [],
      versionSnapshots: [],
      evidenceEntries: [],
      lintRecords: [],
    );

    final updated = knowledgePageMemoryCardFromDetail(card, detail);

    expect(updated.status, isNot('confirmed'));
    expect(updated.markedInaccurate, isTrue);
  });

  test('page memory cards can open without a viewer backend', () {
    expect(
      canOpenEvidenceMemoryCard(
        'page:preferences',
        hasPagesBackend: true,
        hasViewerBackend: false,
      ),
      isTrue,
    );
    expect(
      canOpenEvidenceMemoryCard(
        'generated:preference:response-language',
        hasPagesBackend: true,
        hasViewerBackend: false,
      ),
      isFalse,
    );
  });

  test('page memory cards can mutate without knowledge or viewer backends', () {
    expect(
      canMutateEvidenceMemoryCard(
        'page:preferences',
        hasPagesBackend: true,
        hasKnowledgeBackend: false,
        hasViewerBackend: false,
      ),
      isTrue,
    );
    expect(
      canMutateEvidenceMemoryCard(
        'generated:preference:response-language',
        hasPagesBackend: true,
        hasKnowledgeBackend: false,
        hasViewerBackend: false,
      ),
      isFalse,
    );
  });
}
