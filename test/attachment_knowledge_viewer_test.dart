import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/attachment_detail_text_content.dart';
import 'package:secondloop/features/attachments/attachment_knowledge_viewer.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  test('candidateAttachmentKnowledgeDocumentIds prefers summary targets', () {
    final ids = candidateAttachmentKnowledgeDocumentIds(
      const Attachment(
        sha256: 'sha-doc',
        mimeType: 'text/plain',
        path: 'attachments/sha-doc.txt',
        byteLen: 32,
        createdAtMs: 1,
      ),
      const <String, Object?>{
        'summary': 'A short summary',
      },
      'summary',
    );

    expect(ids.first, 'attachment:sha-doc:summary');
  });

  testWidgets(
      'AttachmentKnowledgeContentPane forwards initial chunk targeting to knowledge viewer',
      (tester) async {
    final backend = _AttachmentKnowledgeViewerBackend();
    final largeReadableText = List<String>.generate(
      180,
      (index) =>
          'Chunk line $index with enough text to use the knowledge viewer.',
    ).join('\n');

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: AttachmentKnowledgeContentPane(
                  attachment: const Attachment(
                    sha256: 'sha-doc',
                    mimeType: 'text/plain',
                    path: 'attachments/sha-doc.txt',
                    byteLen: 32,
                    createdAtMs: 1,
                  ),
                  payload: <String, Object?>{
                    'readable_text_full': largeReadableText,
                    kPreferredAttachmentContentKindKey: 'readable_text_full',
                    kPreferredAttachmentChunkIndexKey: 4,
                  },
                  text: largeReadableText,
                  emptyText: 'empty',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'knowledge_viewer_unit_highlight_attachment:sha-doc:readable_text:chunk:0004',
        ),
      ),
      findsOneWidget,
    );
  });
}

final class _AttachmentKnowledgeViewerBackend extends TestAppBackend
    implements KnowledgeViewerBackend {
  final String documentId = 'attachment:sha-doc:readable_text';

  late final KnowledgeViewerDocument viewerDocument = KnowledgeViewerDocument(
    document: ContentKnowledgeDocument(
      documentId: documentId,
      originType: KnowledgeOriginType.attachment,
      sourceKind: KnowledgeSourceKind.readableText,
      role: KnowledgeRole.body,
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
      anchors: const KnowledgeAnchorSet(
        attachmentSha256: 'sha-doc',
        sourceFilename: 'notes.txt',
      ),
      title: 'Notes',
      summary: 'Project notes',
      rawText: 'Chunk one two three four five',
      normalizedText: 'chunk one two three four five',
      memoryFeedback: const KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    ),
    totalUnits: 6,
    sectionCount: 1,
    chunkCount: 6,
  );

  late final List<KnowledgeUnit> units = List<KnowledgeUnit>.generate(
    6,
    (index) => KnowledgeUnit(
      unitId:
          'attachment:sha-doc:readable_text:chunk:${index.toString().padLeft(4, '0')}',
      documentId: documentId,
      parentUnitId: 'attachment:sha-doc:readable_text:section:0',
      unitKind: KnowledgeUnitKind.chunk,
      sourceKind: KnowledgeSourceKind.readableText,
      role: KnowledgeRole.body,
      ordinal: index,
      tokenCount: 8,
      rawText: 'Chunk $index',
      normalizedText: 'chunk $index',
      anchors: const KnowledgeAnchorSet(attachmentSha256: 'sha-doc'),
      prevUnitId: index == 0
          ? null
          : 'attachment:sha-doc:readable_text:chunk:${(index - 1).toString().padLeft(4, '0')}',
      nextUnitId: index == 5
          ? null
          : 'attachment:sha-doc:readable_text:chunk:${(index + 1).toString().padLeft(4, '0')}',
      createdAtMs: 1,
      updatedAtMs: 2,
    ),
  );

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != this.documentId) {
      throw StateError('unexpected document id: $documentId');
    }
    return viewerDocument;
  }

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    return KnowledgeViewerPage(
      documentId: documentId,
      unitKind: unitKind,
      offset: offset,
      limit: limit,
      total: units.length,
      units: units.skip(offset).take(limit).toList(growable: false),
    );
  }

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      units.sublist(2, 6);

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
}
