import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/knowledge_center/knowledge_page_detail.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/lint.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'KnowledgePageDetailPage keeps summary and body separate when correcting',
      (tester) async {
    final backend = _MutableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Correct current conclusion'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('memory_correction_summary_field')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('memory_correction_body_field')),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Short corrected summary.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_body_field')),
      'Detailed corrected body.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(backend.correctedSummary, 'Short corrected summary.');
    expect(backend.correctedBody, 'Detailed corrected body.');
  });

  testWidgets('KnowledgePageDetailPage asks user to choose merge target',
      (tester) async {
    final backend = _MutableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge Pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent Events'));
    await tester.pumpAndSettle();

    expect(backend.mergedTargetPageId, 'page:recent-events');
  });

  testWidgets('KnowledgePageDetailPage shows final governance sections',
      (tester) async {
    final backend = _KnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current conclusion'), findsOneWidget);
    expect(find.text('System Judgment'), findsOneWidget);
    expect(find.text('View Evidence'), findsOneWidget);
    expect(find.text('View History'), findsOneWidget);
    expect(find.text('Archive Page'), findsOneWidget);
    expect(find.text('Permanently Remove'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('You May Want to Do'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('You May Want to Do'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Evidence Basis'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Evidence Basis'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Related Pages'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Related Pages'), findsOneWidget);
  });
}

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
  String? correctedSummary;
  String? correctedBody;
  String? mergedTargetPageId;

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
  }) async {
    mergedTargetPageId = targetPageId;
    return _buildDetail(pageId: pageId);
  }

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async {
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

KnowledgePageDetail _buildDetail({required String pageId}) {
  return const KnowledgePageDetail(
    page: KnowledgePage(
      pageId: 'page:preferences',
      pageType: KnowledgePageType.preferences,
      title: 'Preferences',
      currentSummary: 'Reply in Chinese by default.',
      currentBody: 'Reply in Chinese by default.\nKeep answers concise.',
      state: KnowledgePageState.active,
      answerPolicy: KnowledgeAnswerPolicy(
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
      tags: ['preferences'],
      primaryEvidenceIds: ['doc:language', 'doc:style'],
      relatedPageIds: ['page:about-me', 'page:recent-events'],
    ),
    sourceDocumentIds: ['doc:language', 'doc:style'],
    claimIds: ['claim:language', 'claim:style'],
    history: [
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
    versionSnapshots: [
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
    evidenceEntries: [
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
    lintRecords: [
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
