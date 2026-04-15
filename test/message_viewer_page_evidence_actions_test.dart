import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/lint.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'message viewer keeps page evidence actions without a viewer backend',
      (tester) async {
    final backend = _PageOnlyEvidenceBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: 'Answer with evidence.',
                citationsJson: '''
{
  "direct_sources": [],
  "memory_cards": [
    {
      "document_id": "page:preferences",
      "title": "Preferences",
      "summary": "Reply in Chinese.",
      "source_kind": "summary",
      "role": "summary",
      "created_at_ms": 1,
      "updated_at_ms": 2,
      "status": "confirmed",
      "source_count": 2
    }
  ]
}
''',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip).first);
    await tester.pumpAndSettle();

    expect(find.text('Inspect page'), findsOneWidget);
    expect(find.text('Stop using in answers'), findsOneWidget);

    await tester.tap(find.text('Stop using in answers'));
    await tester.pumpAndSettle();
    expect(backend.lastMutedPageId, 'page:preferences');

    await tester.tap(find.text('Permanently Remove'));
    await tester.pumpAndSettle();
    expect(backend.lastRemovedPageId, 'page:preferences');

    await tester.tap(find.text('Inspect page'));
    await tester.pumpAndSettle();
    expect(find.text('Current conclusion'), findsOneWidget);
  });

  testWidgets(
      'message viewer open evidence prioritizes knowledge page actions when mixed evidence exists',
      (tester) async {
    final backend = _PageOnlyEvidenceBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: const MessageViewerPage(
                content: 'Answer with evidence.',
                citationsJson: '''
{
  "direct_sources": [
    {
      "id": "message:source-1",
      "href": "secondloop://message/source-1",
      "source_type": "message",
      "label": "History",
      "source_type_label": "chat_message",
      "scope_label": "this_thread",
      "confidence_label": "high_relevance",
      "snippet": "Reply in Chinese.",
      "highlighted_text": "Reply in Chinese.",
      "created_at_ms": 1,
      "updated_at_ms": 1
    }
  ],
  "memory_cards": [
    {
      "document_id": "page:preferences",
      "title": "Preferences",
      "summary": "Reply in Chinese.",
      "source_kind": "summary",
      "role": "summary",
      "created_at_ms": 1,
      "updated_at_ms": 2,
      "status": "confirmed",
      "source_count": 2
    }
  ]
}
''',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Open evidence'));
    await tester.pumpAndSettle();

    expect(find.text('Inspect page'), findsOneWidget);
    expect(find.text('Stop using in answers'), findsOneWidget);
    expect(find.text('View original'), findsNothing);
  });
}

final class _PageOnlyEvidenceBackend extends TestAppBackend
    implements KnowledgePagesBackend {
  String? lastMutedPageId;
  String? lastRemovedPageId;

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      const <KnowledgePageSummary>[
        KnowledgePageSummary(
          pageId: 'page:preferences',
          pageType: KnowledgePageType.preferences,
          title: 'Preferences',
          currentSummary: 'Reply in Chinese.',
          state: KnowledgePageState.active,
          answerPolicy: KnowledgeAnswerPolicy(
            defaultAllowed: true,
            requiresTemporalFraming: false,
          ),
          updatedAtMs: 2,
          lastUsedAtMs: 2,
          sourceCount: 2,
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
      const <KnowledgePageSummary>[];

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      const <KnowledgePageChangeRecord>[];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async =>
      _detail();

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async =>
      _detail();

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      _detail();

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async {
    if (!allowed) {
      lastMutedPageId = pageId;
    }
    return _detail(
      allowed: allowed,
    );
  }

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      _detail();

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async {
    lastRemovedPageId = pageId;
    return _detail();
  }

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      _detail();

  KnowledgePageDetail _detail({
    bool allowed = true,
  }) {
    return KnowledgePageDetail(
      page: KnowledgePage(
        pageId: 'page:preferences',
        pageType: KnowledgePageType.preferences,
        title: 'Preferences',
        currentSummary: 'Reply in Chinese.',
        currentBody: 'Reply in Chinese.\nKeep answers concise.',
        state: KnowledgePageState.active,
        answerPolicy: KnowledgeAnswerPolicy(
          defaultAllowed: allowed,
          requiresTemporalFraming: false,
        ),
        confidenceLevel: 0.9,
        createdAtMs: 1,
        updatedAtMs: 2,
        lastUsedAtMs: 2,
        sourceCount: 2,
        conflictCount: 0,
        humanCorrected: false,
        tags: const [],
        primaryEvidenceIds: const ['doc:language'],
        relatedPageIds: const [],
      ),
      sourceDocumentIds: const ['doc:language'],
      claimIds: const ['claim:language'],
      history: const <KnowledgePageChangeRecord>[],
      versionSnapshots: const <KnowledgePageVersionSnapshot>[],
      evidenceEntries: const <KnowledgePageEvidenceEntry>[],
      lintRecords: const <KnowledgeLintRecord>[],
    );
  }
}
