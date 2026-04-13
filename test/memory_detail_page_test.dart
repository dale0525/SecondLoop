import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_viewer_page.dart';
import 'package:secondloop/features/knowledge_viewer/knowledge_document_viewer_page.dart';
import 'package:secondloop/features/memory/memory_center_models.dart';
import 'package:secondloop/features/memory/memory_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('MemoryDetailPage shows conclusion and evidence timeline',
      (tester) async {
    final backend = _MemoryDetailBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current conclusion'), findsOneWidget);
    expect(find.text('Response language'), findsWidgets);
    expect(find.text('User prefers Chinese.'), findsWidgets);
    expect(find.text('Evidence timeline'), findsOneWidget);
    expect(find.text('Chat message'), findsOneWidget);
    expect(find.text('Message source'), findsOneWidget);
    expect(find.text('Updated today'), findsWidgets);
    expect(find.text('Kickoff note confirms the user prefers Chinese.'),
        findsOneWidget);
    expect(find.text('View original'), findsOneWidget);
  });

  testWidgets(
      'MemoryDetailPage opens attachment evidence with preserved citation target',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryDetailBackend(
      unitsPageBuilder: ({required int limit, required int offset}) =>
          <KnowledgeUnit>[
        KnowledgeUnit(
          unitId: 'attachment:sha-attachment:transcript:chunk:4',
          documentId: 'attachment:sha-attachment:transcript',
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.chunk,
          sourceKind: KnowledgeSourceKind.transcript,
          role: KnowledgeRole.evidence,
          ordinal: 4,
          tokenCount: 16,
          rawText: 'Transcript chunk four.',
          normalizedText: 'transcript chunk four.',
          anchors: const KnowledgeAnchorSet(
            attachmentSha256: 'sha-attachment',
          ),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final openSourceButton = find.widgetWithText(TextButton, 'View original');
    await tester.scrollUntilVisible(
      openSourceButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(openSourceButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final page = tester.widget<AttachmentViewerPage>(
      find.byType(AttachmentViewerPage),
    );
    expect(page.initialContentKind, 'transcript_full');
    expect(page.initialChunkIndex, 4);
  });

  testWidgets('MemoryDetailPage preserves summary attachment citation targets',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryDetailBackend(
      unitsPageBuilder: ({required int limit, required int offset}) =>
          <KnowledgeUnit>[
        KnowledgeUnit(
          unitId: 'attachment:sha-attachment:summary:chunk:0',
          documentId: 'attachment:sha-attachment:summary',
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.chunk,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.evidence,
          ordinal: 0,
          tokenCount: 8,
          rawText: 'Summary chunk zero.',
          normalizedText: 'summary chunk zero.',
          anchors: const KnowledgeAnchorSet(
            attachmentSha256: 'sha-attachment',
          ),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final openSourceButton = find.widgetWithText(TextButton, 'View original');
    await tester.scrollUntilVisible(
      openSourceButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(openSourceButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final page = tester.widget<AttachmentViewerPage>(
      find.byType(AttachmentViewerPage),
    );
    expect(page.initialContentKind, 'summary');
    expect(page.initialChunkIndex, 0);
  });

  testWidgets(
      'MemoryDetailPage opens external document evidence with highlighted unit target',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryDetailBackend(
      unitsPageBuilder: ({required int limit, required int offset}) =>
          <KnowledgeUnit>[
        KnowledgeUnit(
          unitId: 'external:travel/doc-1:chunk:0007',
          documentId: 'external:travel/doc-1',
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.chunk,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.evidence,
          ordinal: 7,
          tokenCount: 24,
          rawText: 'Budget cap is documented in the imported expense sheet.',
          normalizedText:
              'budget cap is documented in the imported expense sheet.',
          anchors: const KnowledgeAnchorSet(sourceFilename: 'expense-sheet.md'),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final openSourceButton = find.widgetWithText(TextButton, 'View original');
    await tester.scrollUntilVisible(
      openSourceButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(openSourceButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final page = tester.widget<KnowledgeDocumentViewerPage>(
      find.byType(KnowledgeDocumentViewerPage),
    );
    expect(page.documentId, 'external:travel/doc-1');
    expect(page.initialHighlightedUnitId, 'external:travel/doc-1:chunk:0007');
  });

  testWidgets(
    'MemoryDetailPage loads later pages before sorting the latest evidence timeline',
    (tester) async {
      final backend = _MemoryDetailBackend(
        unitsPageBuilder: ({required int limit, required int offset}) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (offset == 0) {
            return List<KnowledgeUnit>.generate(
              limit,
              (index) => KnowledgeUnit(
                unitId: 'older-$index',
                documentId: 'generated:preference:response-language',
                parentUnitId: null,
                unitKind: KnowledgeUnitKind.segment,
                sourceKind: KnowledgeSourceKind.summary,
                role: KnowledgeRole.evidence,
                ordinal: index,
                tokenCount: 8,
                rawText: 'Older evidence $index',
                normalizedText: 'Older evidence $index',
                anchors: const KnowledgeAnchorSet(messageId: 'history-1'),
                prevUnitId: null,
                nextUnitId: null,
                createdAtMs: now - 1000 - index,
                updatedAtMs: now - 1000 - index,
              ),
            );
          }
          if (offset == limit) {
            return <KnowledgeUnit>[
              KnowledgeUnit(
                unitId: 'newest',
                documentId: 'generated:preference:response-language',
                parentUnitId: null,
                unitKind: KnowledgeUnitKind.segment,
                sourceKind: KnowledgeSourceKind.summary,
                role: KnowledgeRole.evidence,
                ordinal: limit,
                tokenCount: 12,
                rawText: 'Newest evidence from a later page.',
                normalizedText: 'Newest evidence from a later page.',
                anchors: const KnowledgeAnchorSet(messageId: 'history-latest'),
                prevUnitId: null,
                nextUnitId: null,
                createdAtMs: now + 1000,
                updatedAtMs: now + 1000,
              ),
            ];
          }
          return const <KnowledgeUnit>[];
        },
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const MemoryDetailPage(
                  documentId: 'generated:preference:response-language',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Newest evidence from a later page.'), findsOneWidget);
      expect(backend.viewerListOffsets, <int>[0, 48]);
    },
  );

  testWidgets('MemoryDetailPage edits memory and toggles usage actions',
      (tester) async {
    final backend = _MemoryDetailBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Correct current conclusion'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_title_field')),
      'Preferred reply language',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Always reply in Chinese unless I ask for another language.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Preferred reply language'), findsWidgets);
    expect(
      find.text('Always reply in Chinese unless I ask for another language.'),
      findsWidgets,
    );
    expect(find.text('Confirmed'), findsOneWidget);

    await tester.tap(find.text('Stop using in answers'));
    await tester.pumpAndSettle();
    expect(find.text('Not used in answers'), findsOneWidget);

    await tester.tap(find.text('Archive page'));
    await tester.pumpAndSettle();
    expect(find.text('Page deleted'), findsOneWidget);
    expect(find.text('Restore page'), findsOneWidget);
  });

  testWidgets(
    'MemoryDetailPage status toggles do not freeze autogenerated title or summary',
    (tester) async {
      final backend = _MemoryDetailBackend();

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const MemoryDetailPage(
                  documentId: 'generated:preference:response-language',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(backend.correctedTitle, isNull);
      expect(backend.correctedSummary, isNull);

      await tester.tap(find.text('Stop using in answers'));
      await tester.pumpAndSettle();

      expect(backend.correctedTitle, isNull);
      expect(backend.correctedSummary, isNull);
    },
  );

  testWidgets('MemoryDetailPage prefers recent-evidence loading when available',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final backend = _RecentMemoryDetailBackend(
      recentUnits: [
        KnowledgeUnit(
          unitId: 'recent-u1',
          documentId: 'generated:preference:response-language',
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.segment,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.evidence,
          ordinal: 1,
          tokenCount: 12,
          rawText: 'Most recent evidence only.',
          normalizedText: 'Most recent evidence only.',
          anchors: const KnowledgeAnchorSet(messageId: 'history-1'),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Most recent evidence only.'), findsOneWidget);
    expect(backend.recentListRequestCount, 1);
    expect(backend.viewerListOffsets, isEmpty);
  });

  testWidgets('MemoryDetailPage shows an error when feedback save fails',
      (tester) async {
    final backend = _FailingMemoryDetailBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryDetailPage(
                documentId: 'generated:preference:response-language',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Stop using in answers'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining('save_failed'), findsOneWidget);
    expect(find.text('Used in answers'), findsOneWidget);
    expect(find.text('Not used in answers'), findsNothing);
  });

  test('effectiveMemoryStatus uses memory display status when present', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final document = ContentKnowledgeDocument(
      documentId: 'generated:event:decision',
      originType: KnowledgeOriginType.generated,
      sourceKind: KnowledgeSourceKind.summary,
      role: KnowledgeRole.summary,
      language: 'en',
      qualityScore: 1,
      createdAtMs: now - 1000,
      updatedAtMs: now - const Duration(days: 60).inMilliseconds,
      versions: const KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
      anchors: const KnowledgeAnchorSet(),
      title: 'Decision memory',
      summary: 'A stale event memory',
      rawText: 'A stale event memory',
      normalizedText: 'a stale event memory',
      memoryDisplay: const KnowledgeMemoryDisplay(
        section: KnowledgeMemorySection.recentEvent,
        sourceCount: 1,
        status: KnowledgeMemoryStatus.confirmed,
      ),
      memoryFeedback: const KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    );

    expect(effectiveMemoryStatus(document), MemoryCardStatus.confirmed);
  });

  testWidgets(
    'MemoryDetailPage starts editing generated memories from the full body',
    (tester) async {
      final backend = _MemoryDetailBackend(
        documentSummary: 'User is actively working across these task threads:',
        documentRawText:
            'User is actively working across these task threads:\n- Draft roadmap [in_progress]\n- Review launch notes [open]',
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const MemoryDetailPage(
                  documentId: 'generated:pattern:active-task-focus',
                  startInEditMode: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final summaryField = tester.widget<TextField>(
        find.byKey(const ValueKey('memory_correction_summary_field')),
      );
      expect(
        summaryField.controller?.text,
        'User is actively working across these task threads:\n- Draft roadmap [in_progress]\n- Review launch notes [open]',
      );
    },
  );
}

final class _MemoryDetailBackend extends TestAppBackend
    implements KnowledgeBackend, KnowledgeViewerBackend, AttachmentsBackend {
  _MemoryDetailBackend({
    this.unitsPageBuilder,
    String? documentTitle,
    String? documentSummary,
    String? documentRawText,
  })  : _documentTitle = documentTitle ?? 'Response language',
        _documentSummary = documentSummary ?? 'User prefers Chinese.',
        _documentRawText =
            documentRawText ?? documentSummary ?? 'User prefers Chinese.';

  final List<KnowledgeUnit> Function({required int limit, required int offset})?
      unitsPageBuilder;
  final List<int> viewerListOffsets = <int>[];

  KnowledgeViewerDocument _document(String documentId) =>
      KnowledgeViewerDocument(
        document: ContentKnowledgeDocument(
          documentId: documentId,
          originType: KnowledgeOriginType.generated,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.summary,
          language: 'en',
          qualityScore: 1,
          createdAtMs: 1,
          updatedAtMs: 2,
          versions: const KnowledgeVersionSet(
            schemaVersion: 1,
            normalizationVersion: 1,
            segmentationVersion: 1,
            embeddingPolicyVersion: 1,
            retrievalPolicyVersion: 1,
          ),
          anchors: const KnowledgeAnchorSet(),
          title: _correctedTitle ?? _documentTitle,
          summary: _correctedSummary ?? _documentSummary,
          rawText: _correctedSummary ?? _documentRawText,
          normalizedText: _correctedSummary ?? _documentRawText,
          memoryFeedback: KnowledgeMemoryFeedback(
            status: _status,
            useForAskAi: _useForAskAi,
            isDeleted: _isDeleted,
            markedInaccurate: _markedInaccurate,
            correctedTitle: _correctedTitle,
            correctedSummary: _correctedSummary,
            updatedAtMs: 3,
          ),
        ),
        totalUnits: 1,
        sectionCount: 1,
        chunkCount: 1,
      );

  final String _documentTitle;
  final String _documentSummary;
  final String _documentRawText;
  String? _correctedTitle;
  String? _correctedSummary;
  KnowledgeMemoryStatus? _status = KnowledgeMemoryStatus.inferred;
  bool _useForAskAi = true;
  bool _isDeleted = false;
  bool _markedInaccurate = false;
  static const Attachment _attachment = Attachment(
    sha256: 'sha-attachment',
    mimeType: 'text/plain',
    path: 'attachments/sha-attachment.txt',
    byteLen: 16,
    createdAtMs: 1,
  );

  String? get correctedTitle => _correctedTitle;
  String? get correctedSummary => _correctedSummary;

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async =>
      _document(documentId);

  @override
  Future<KnowledgeMemoryFeedback> upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) async {
    _status = status;
    _useForAskAi = useForAskAi;
    _isDeleted = isDeleted;
    _markedInaccurate = markedInaccurate;
    _correctedTitle = correctedTitle;
    _correctedSummary = correctedSummary;
    return KnowledgeMemoryFeedback(
      status: _status,
      useForAskAi: _useForAskAi,
      isDeleted: _isDeleted,
      markedInaccurate: _markedInaccurate,
      correctedTitle: _correctedTitle,
      correctedSummary: _correctedSummary,
      updatedAtMs: 3,
    );
  }

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async =>
      <ContentKnowledgeDocument>[
        _document('generated:preference:response-language').document
      ];

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async =>
      const <KnowledgeUnit>[];

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async =>
      0;

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      const <KnowledgeUnit>[];

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    viewerListOffsets.add(offset);
    final customPage = unitsPageBuilder?.call(limit: limit, offset: offset);
    if (customPage != null) {
      return KnowledgeViewerPage(
        documentId: documentId,
        unitKind: KnowledgeUnitKind.segment,
        offset: offset,
        limit: limit,
        total: customPage.length < limit
            ? offset + customPage.length
            : offset + limit + 1,
        units: customPage,
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return KnowledgeViewerPage(
      documentId: documentId,
      unitKind: KnowledgeUnitKind.segment,
      offset: 0,
      limit: 20,
      total: 1,
      units: [
        KnowledgeUnit(
          unitId: 'u1',
          documentId: 'generated:preference:response-language',
          parentUnitId: null,
          unitKind: KnowledgeUnitKind.segment,
          sourceKind: KnowledgeSourceKind.summary,
          role: KnowledgeRole.evidence,
          ordinal: 0,
          tokenCount: 12,
          rawText: 'Kickoff note confirms the user prefers Chinese.',
          normalizedText: 'Kickoff note confirms the user prefers Chinese.',
          anchors: const KnowledgeAnchorSet(messageId: 'history-1'),
          prevUnitId: null,
          nextUnitId: null,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async =>
      attachmentSha256 == _attachment.sha256 ? _attachment : null;

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async =>
      const <Attachment>[];

  @override
  Future<void> linkAttachmentToMessage(
    Uint8List key,
    String messageId, {
    required String attachmentSha256,
  }) async {}

  @override
  Future<List<Attachment>> listRecentAttachments(
    Uint8List key, {
    int limit = 50,
  }) async =>
      <Attachment>[_attachment];

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<Uint8List> readAttachmentBytes(
    Uint8List key, {
    required String sha256,
  }) async =>
      Uint8List.fromList(const <int>[1, 2, 3]);

  @override
  Future<AttachmentExifMetadata?> readAttachmentExifMetadata(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;

  @override
  Future<String?> readAttachmentPlaceDisplayName(
    Uint8List key, {
    required String sha256,
  }) async =>
      null;
}

final class _RecentMemoryDetailBackend extends _MemoryDetailBackend
    implements RecentKnowledgeViewerBackend {
  _RecentMemoryDetailBackend({required this.recentUnits});

  final List<KnowledgeUnit> recentUnits;
  int recentListRequestCount = 0;

  @override
  Future<List<KnowledgeUnit>> listRecentKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 16,
  }) async {
    recentListRequestCount += 1;
    return recentUnits.take(limit).toList(growable: false);
  }
}

final class _FailingMemoryDetailBackend extends _MemoryDetailBackend {
  @override
  Future<KnowledgeMemoryFeedback> upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) async {
    throw StateError('save_failed');
  }
}
