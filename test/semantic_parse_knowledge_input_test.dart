import 'dart:convert';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

void main() {
  final sessionKey = Uint8List.fromList(List<int>.filled(32, 7));

  test(
      'semantic parse knowledge prefers knowledge transcript snippets over raw payload fields',
      () async {
    const transcriptDocumentId = 'attachment:sha-transcript:transcript';
    final backend = _SemanticKnowledgeBackend(
      messages: <String, Message>{
        'msg:knowledge': _message(
          id: 'msg:knowledge',
          content: 'budget freeze follow up',
        ),
      },
      attachmentsByMessageId: <String, List<Attachment>>{
        'msg:knowledge': <Attachment>[
          _attachment(
            sha256: 'sha-transcript',
            mimeType: 'application/pdf',
          ),
        ],
      },
      payloadJsonBySha: <String, String>{
        'sha-transcript': jsonEncode(
          <String, Object?>{
            'mime_type': 'application/pdf',
            'transcript_full':
                'RAW PAYLOAD transcript that should not dominate semantic parse.',
          },
        ),
      },
      documentsById: <String, KnowledgeViewerDocument>{
        transcriptDocumentId: _viewerDocument(
          documentId: transcriptDocumentId,
          sourceKind: KnowledgeSourceKind.transcript,
          role: KnowledgeRole.evidence,
          summary: 'Quarterly planning transcript.',
        ),
      },
      unitsByDocumentId: <String, List<KnowledgeUnit>>{
        transcriptDocumentId: <KnowledgeUnit>[
          _unit(
            documentId: transcriptDocumentId,
            unitId: 'chunk-transcript-1',
            sourceKind: KnowledgeSourceKind.transcript,
            role: KnowledgeRole.evidence,
            rawText: 'Speaker Charlie: freeze-signal budget decision',
            sectionLabel: 'Speaker Charlie',
          ),
        ],
      },
      searchResultsByDocumentQuery: <String, List<KnowledgeSearchResult>>{
        '$transcriptDocumentId|budget freeze follow up':
            <KnowledgeSearchResult>[
          _searchResult(
            documentId: transcriptDocumentId,
            unitId: 'chunk-transcript-1',
            sourceKind: KnowledgeSourceKind.transcript,
            role: KnowledgeRole.evidence,
            snippet: 'Speaker Charlie: freeze-signal budget decision',
            sectionLabel: 'Speaker Charlie',
          ),
        ],
      },
    );

    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: sessionKey,
    );

    final input = await store.getMessageInput('msg:knowledge');

    expect(input, isNotNull);
    expect(input!.analysisText, contains('budget freeze follow up'));
    expect(
        input.analysisText,
        contains(
            'Transcript evidence: Speaker Charlie: freeze-signal budget decision'));
    expect(input.analysisText, isNot(contains('RAW PAYLOAD transcript')));
    expect(input.allowCreate, isFalse);
  });

  test(
      'semantic parse knowledge includes mixed-source knowledge snippets before payload fallback',
      () async {
    const transcriptDocumentId = 'attachment:sha-mixed:transcript';
    const metadataDocumentId = 'attachment:sha-mixed:metadata';
    final backend = _SemanticKnowledgeBackend(
      messages: <String, Message>{
        'msg:mixed': _message(
          id: 'msg:mixed',
          content: 'follow up orchard invoice and budget freeze',
        ),
      },
      attachmentsByMessageId: <String, List<Attachment>>{
        'msg:mixed': <Attachment>[
          _attachment(
            sha256: 'sha-mixed',
            mimeType: 'application/pdf',
          ),
        ],
      },
      payloadJsonBySha: <String, String>{
        'sha-mixed': jsonEncode(
          <String, Object?>{
            'mime_type': 'application/pdf',
            'ocr_text_full': 'NOISY OCR PAYLOAD',
            'readable_text_full': 'NOISY READABLE PAYLOAD',
          },
        ),
      },
      documentsById: <String, KnowledgeViewerDocument>{
        transcriptDocumentId: _viewerDocument(
          documentId: transcriptDocumentId,
          sourceKind: KnowledgeSourceKind.transcript,
          role: KnowledgeRole.evidence,
          summary: 'Quarterly planning transcript.',
        ),
        metadataDocumentId: _viewerDocument(
          documentId: metadataDocumentId,
          sourceKind: KnowledgeSourceKind.metadata,
          role: KnowledgeRole.metadata,
          summary: 'Budget freeze overview metadata.',
        ),
      },
      unitsByDocumentId: <String, List<KnowledgeUnit>>{
        transcriptDocumentId: <KnowledgeUnit>[
          _unit(
            documentId: transcriptDocumentId,
            unitId: 'chunk-transcript-2',
            sourceKind: KnowledgeSourceKind.transcript,
            role: KnowledgeRole.evidence,
            rawText: 'Speaker Charlie: orchard invoice needs approval',
            sectionLabel: 'Speaker Charlie',
          ),
        ],
        metadataDocumentId: <KnowledgeUnit>[
          _unit(
            documentId: metadataDocumentId,
            unitId: 'chunk-metadata-1',
            sourceKind: KnowledgeSourceKind.metadata,
            role: KnowledgeRole.metadata,
            rawText: 'Title: Budget freeze overview\nFilename: roadmap-q1.pdf',
            sectionLabel: 'Metadata',
          ),
        ],
      },
      searchResultsByDocumentQuery: <String, List<KnowledgeSearchResult>>{
        '$transcriptDocumentId|follow up orchard invoice and budget freeze':
            <KnowledgeSearchResult>[
          _searchResult(
            documentId: transcriptDocumentId,
            unitId: 'chunk-transcript-2',
            sourceKind: KnowledgeSourceKind.transcript,
            role: KnowledgeRole.evidence,
            snippet: 'Speaker Charlie: orchard invoice needs approval',
            sectionLabel: 'Speaker Charlie',
          ),
        ],
        '$metadataDocumentId|follow up orchard invoice and budget freeze':
            <KnowledgeSearchResult>[
          _searchResult(
            documentId: metadataDocumentId,
            unitId: 'chunk-metadata-1',
            sourceKind: KnowledgeSourceKind.metadata,
            role: KnowledgeRole.metadata,
            snippet: 'Title: Budget freeze overview • Filename: roadmap-q1.pdf',
            sectionLabel: 'Metadata',
          ),
        ],
      },
    );

    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: sessionKey,
    );

    final input = await store.getMessageInput('msg:mixed');

    expect(input, isNotNull);
    expect(
        input!.analysisText,
        contains(
            'Transcript evidence: Speaker Charlie: orchard invoice needs approval'));
    expect(
        input.analysisText,
        contains(
            'Metadata metadata: Title: Budget freeze overview • Filename: roadmap-q1.pdf'));
    expect(input.analysisText, isNot(contains('NOISY OCR PAYLOAD')));
    expect(input.analysisText, isNot(contains('NOISY READABLE PAYLOAD')));
    expect(input.allowCreate, isFalse);
  });
}

Message _message({
  required String id,
  required String content,
}) {
  return Message(
    id: id,
    conversationId: 'loop_home',
    role: 'user',
    content: content,
    createdAtMs: PlatformInt64Util.from(1),
    isMemory: true,
  );
}

Attachment _attachment({
  required String sha256,
  required String mimeType,
}) {
  return Attachment(
    sha256: sha256,
    mimeType: mimeType,
    path: '/tmp/$sha256',
    byteLen: PlatformInt64Util.from(1),
    createdAtMs: PlatformInt64Util.from(1),
  );
}

KnowledgeViewerDocument _viewerDocument({
  required String documentId,
  required KnowledgeSourceKind sourceKind,
  required KnowledgeRole role,
  required String summary,
}) {
  return KnowledgeViewerDocument(
    document: ContentKnowledgeDocument(
      documentId: documentId,
      originType: KnowledgeOriginType.attachment,
      sourceKind: sourceKind,
      role: role,
      language: 'en',
      qualityScore: 0.9,
      createdAtMs: 0,
      updatedAtMs: 0,
      versions: const KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
      anchors: KnowledgeAnchorSet(
        attachmentSha256: documentId.split(':')[1],
      ),
      title: 'Knowledge doc',
      summary: summary,
      rawText: summary,
      normalizedText: summary.toLowerCase(),
      memoryFeedback: const KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    ),
    totalUnits: 1,
    sectionCount: 1,
    chunkCount: 1,
  );
}

KnowledgeUnit _unit({
  required String documentId,
  required String unitId,
  required KnowledgeSourceKind sourceKind,
  required KnowledgeRole role,
  required String rawText,
  required String sectionLabel,
}) {
  return KnowledgeUnit(
    unitId: unitId,
    documentId: documentId,
    parentUnitId: null,
    unitKind: KnowledgeUnitKind.chunk,
    sourceKind: sourceKind,
    role: role,
    ordinal: 0,
    tokenCount: 48,
    rawText: rawText,
    normalizedText: rawText.toLowerCase(),
    anchors: KnowledgeAnchorSet(
      attachmentSha256: documentId.split(':')[1],
      sectionLabel: sectionLabel,
    ),
    prevUnitId: null,
    nextUnitId: null,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

KnowledgeSearchResult _searchResult({
  required String documentId,
  required String unitId,
  required KnowledgeSourceKind sourceKind,
  required KnowledgeRole role,
  required String snippet,
  required String sectionLabel,
}) {
  return KnowledgeSearchResult(
    documentId: documentId,
    unitId: unitId,
    unitKind: KnowledgeUnitKind.chunk,
    layer: KnowledgeRetrievalLayer.chunk,
    sourceKind: sourceKind,
    role: role,
    title: 'Knowledge hit',
    summary: snippet,
    snippet: snippet,
    score: 0.95,
    semanticScore: 0.92,
    lexicalScore: 0.98,
    anchors: KnowledgeAnchorSet(
      attachmentSha256: documentId.split(':')[1],
      sectionLabel: sectionLabel,
    ),
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

final class _SemanticKnowledgeBackend extends NativeAppBackend
    implements KnowledgeViewerBackend {
  _SemanticKnowledgeBackend({
    required this.messages,
    required this.attachmentsByMessageId,
    this.payloadJsonBySha = const <String, String>{},
    this.documentsById = const <String, KnowledgeViewerDocument>{},
    this.unitsByDocumentId = const <String, List<KnowledgeUnit>>{},
    this.searchResultsByDocumentQuery =
        const <String, List<KnowledgeSearchResult>>{},
  }) : super(appDirProvider: () async => '/tmp/secondloop-semantic-knowledge');

  final Map<String, Message> messages;
  final Map<String, List<Attachment>> attachmentsByMessageId;
  final Map<String, String> payloadJsonBySha;
  final Map<String, KnowledgeViewerDocument> documentsById;
  final Map<String, List<KnowledgeUnit>> unitsByDocumentId;
  final Map<String, List<KnowledgeSearchResult>> searchResultsByDocumentQuery;

  @override
  Future<Message?> getMessageById(Uint8List key, String messageId) async {
    return messages[messageId];
  }

  @override
  Future<List<Attachment>> listMessageAttachments(
    Uint8List key,
    String messageId,
  ) async {
    return List<Attachment>.from(
      attachmentsByMessageId[messageId] ?? const <Attachment>[],
    );
  }

  @override
  Future<String?> readAttachmentAnnotationCaptionLong(
    Uint8List key, {
    required String sha256,
  }) async {
    return null;
  }

  @override
  Future<String?> readAttachmentAnnotationPayloadJson(
    Uint8List key, {
    required String sha256,
  }) async {
    return payloadJsonBySha[sha256];
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async {
    if (documentId == null) return const <KnowledgeSearchResult>[];
    return searchKnowledgeDocumentUnits(
      key,
      documentId: documentId,
      query: query,
      limit: limit,
    );
  }

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    final document = documentsById[documentId];
    if (document == null) {
      throw StateError('unknown knowledge document: $documentId');
    }
    return document;
  }

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final units = unitsByDocumentId[documentId] ?? const <KnowledgeUnit>[];
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
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async {
    return List<KnowledgeSearchResult>.from(
      searchResultsByDocumentQuery['$documentId|${query.trim()}'] ??
          const <KnowledgeSearchResult>[],
    ).take(limit).toList(growable: false);
  }

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async {
    return List<KnowledgeUnit>.from(
      unitsByDocumentId[documentId] ?? const <KnowledgeUnit>[],
    );
  }
}
