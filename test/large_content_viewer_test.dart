import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/audio_attachment_player.dart';
import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'large content viewer uses knowledge viewer for message documents',
      (tester) async {
    final backend = _LargeMessageBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 2)),
              lock: () {},
              child: MessageViewerPage(
                content: _LargeMessageBackend.longText,
                messageId: 'msg-large',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_knowledge_viewer')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('message_viewer_markdown')), findsNothing);
  });
  testWidgets('large content viewer uses knowledge viewer instead of markdown',
      (tester) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final backend = _LargeContentBackend();
    const attachment = Attachment(
      sha256: 'sha-large-doc',
      mimeType: 'application/pdf',
      path: '/tmp/large.pdf',
      byteLen: 4096,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: NonImageAttachmentView(
                attachment: attachment,
                bytes: Uint8List(0),
                displayTitle: 'Large PDF',
                initialAnnotationPayload: <String, Object?>{
                  'mime_type': 'application/pdf',
                  'page_count': 4,
                  'extracted_text_full': _LargeContentBackend.longText,
                },
                onSaveFull: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_knowledge_viewer')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('attachment_text_full_markdown_display')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('attachment_knowledge_viewer_copy')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_knowledge_viewer_edit')),
        findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('attachment_knowledge_viewer_copy')),
    );
    await tester.tap(
      find.byKey(const ValueKey('attachment_knowledge_viewer_copy')),
    );
    await tester.pumpAndSettle();

    expect(clipboardText, contains('Section 1'));
    expect(find.byKey(const ValueKey('knowledge_viewer_search_field')),
        findsOneWidget);
  });
  testWidgets('large content viewer uses knowledge viewer for audio transcript',
      (tester) async {
    final backend = _LargeAudioTranscriptBackend();
    const attachment = Attachment(
      sha256: 'sha-audio-transcript',
      mimeType: 'audio/mp4',
      path: '/tmp/meeting.m4a',
      byteLen: 4096,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 3)),
              lock: () {},
              child: Scaffold(
                body: AudioTranscriptKnowledgeContentPane(
                  attachment: attachment,
                  text: _LargeAudioTranscriptBackend.longTranscript,
                  emptyText: 'Empty transcript',
                  onSave: (_) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_knowledge_viewer')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('attachment_text_full_markdown_display')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('attachment_text_full_markdown_deferred')),
      findsNothing,
    );
  });
}

final class _LargeContentBackend extends TestAppBackend
    implements KnowledgeViewerBackend {
  static final String longText = List<String>.generate(
    240,
    (index) => '## Section ${index + 1}\nLine ${index + 1} for the PDF body',
  ).join('\n\n');

  static const String _documentId = 'attachment:sha-large-doc:extracted_text';

  late final ContentKnowledgeDocument _document = ContentKnowledgeDocument(
    documentId: _documentId,
    originType: KnowledgeOriginType.attachment,
    sourceKind: KnowledgeSourceKind.extractedText,
    role: KnowledgeRole.evidence,
    language: 'en',
    qualityScore: 0.88,
    createdAtMs: 0,
    updatedAtMs: 0,
    versions: const KnowledgeVersionSet(
      schemaVersion: 1,
      normalizationVersion: 1,
      segmentationVersion: 1,
      embeddingPolicyVersion: 1,
      retrievalPolicyVersion: 1,
    ),
    anchors: const KnowledgeAnchorSet(
      attachmentSha256: 'sha-large-doc',
      pageIndex: 0,
      sourceFilename: 'large.pdf',
    ),
    title: 'Large PDF',
    summary: 'Paged PDF summary.',
    rawText: longText,
    normalizedText: longText.toLowerCase(),
    memoryFeedback: const KnowledgeMemoryFeedback(
      useForAskAi: true,
      isDeleted: false,
      markedInaccurate: false,
    ),
  );

  late final KnowledgeViewerDocument _viewerDocument = KnowledgeViewerDocument(
    document: _document,
    totalUnits: 4,
    sectionCount: 1,
    chunkCount: 4,
  );

  late final List<KnowledgeUnit> _units = List<KnowledgeUnit>.generate(
    4,
    (index) => KnowledgeUnit(
      unitId: 'pdf-chunk-${index + 1}',
      documentId: _documentId,
      parentUnitId: 'pdf-section-1',
      unitKind: KnowledgeUnitKind.chunk,
      sourceKind: KnowledgeSourceKind.extractedText,
      role: KnowledgeRole.evidence,
      ordinal: index,
      tokenCount: 120,
      rawText: 'Section ${index + 1} content',
      normalizedText: 'section ${index + 1} content',
      anchors: KnowledgeAnchorSet(
        attachmentSha256: 'sha-large-doc',
        pageIndex: index,
        sectionLabel: 'Page ${index + 1}',
      ),
      prevUnitId: index == 0 ? null : 'pdf-chunk-$index',
      nextUnitId: index == 3 ? null : 'pdf-chunk-${index + 2}',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  );

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != _documentId) {
      throw StateError('unexpected document id: $documentId');
    }
    return _viewerDocument;
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
      total: _units.length,
      units: _units.skip(offset).take(limit).toList(growable: false),
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async {
    return const <KnowledgeSearchResult>[];
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async {
    return const <KnowledgeSearchResult>[];
  }

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async {
    return _units;
  }
}

final class _LargeMessageBackend extends TestAppBackend
    implements KnowledgeViewerBackend {
  _LargeMessageBackend()
      : super(
          initialMessages: <Message>[
            Message(
              id: 'msg-large',
              conversationId: 'loop_home',
              role: 'user',
              content: longText,
              createdAtMs: 0,
              isMemory: true,
            ),
          ],
        );

  static final String longText = List<String>.generate(
    220,
    (index) => 'Paragraph ${index + 1}: budget freeze note body',
  ).join('\n\n');

  static const String _documentId = 'message:msg-large';

  late final KnowledgeViewerDocument _viewerDocument = KnowledgeViewerDocument(
    document: ContentKnowledgeDocument(
      documentId: _documentId,
      originType: KnowledgeOriginType.message,
      sourceKind: KnowledgeSourceKind.rawText,
      role: KnowledgeRole.body,
      language: 'en',
      qualityScore: 0.84,
      createdAtMs: 0,
      updatedAtMs: 0,
      versions: const KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
      anchors: const KnowledgeAnchorSet(
        messageId: 'msg-large',
        conversationId: 'loop_home',
      ),
      title: 'Large message',
      summary: 'Message body stored in the knowledge index.',
      rawText: longText,
      normalizedText: longText.toLowerCase(),
      memoryFeedback: const KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    ),
    totalUnits: 3,
    sectionCount: 1,
    chunkCount: 3,
  );

  late final List<KnowledgeUnit> _units = List<KnowledgeUnit>.generate(
    3,
    (index) => KnowledgeUnit(
      unitId: 'message:msg-large:chunk:${index + 1}',
      documentId: _documentId,
      parentUnitId: null,
      unitKind: KnowledgeUnitKind.chunk,
      sourceKind: KnowledgeSourceKind.rawText,
      role: KnowledgeRole.body,
      ordinal: index,
      tokenCount: 96,
      rawText: 'Paragraph ${index + 1}: budget freeze note body',
      normalizedText: 'paragraph ${index + 1}: budget freeze note body',
      anchors: const KnowledgeAnchorSet(
        messageId: 'msg-large',
        conversationId: 'loop_home',
      ),
      prevUnitId: index == 0 ? null : 'message:msg-large:chunk:$index',
      nextUnitId: index == 2 ? null : 'message:msg-large:chunk:${index + 2}',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  );

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != _documentId) {
      throw StateError('unexpected document id: $documentId');
    }
    return _viewerDocument;
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
      total: _units.length,
      units: _units.skip(offset).take(limit).toList(growable: false),
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      _units;
}

final class _LargeAudioTranscriptBackend extends TestAppBackend
    implements KnowledgeViewerBackend {
  static final String longTranscript = List<String>.generate(
    220,
    (index) => 'Turn ${index + 1}: action items and notes',
  ).join('\n');

  static const String _documentId =
      'attachment:sha-audio-transcript:transcript';

  late final KnowledgeViewerDocument _viewerDocument = KnowledgeViewerDocument(
    document: ContentKnowledgeDocument(
      documentId: _documentId,
      originType: KnowledgeOriginType.attachment,
      sourceKind: KnowledgeSourceKind.transcript,
      role: KnowledgeRole.evidence,
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
      anchors: const KnowledgeAnchorSet(
        attachmentSha256: 'sha-audio-transcript',
        sourceFilename: 'meeting.m4a',
      ),
      title: 'Meeting transcript',
      summary: 'Transcript stored in the knowledge index.',
      rawText: longTranscript,
      normalizedText: longTranscript.toLowerCase(),
      memoryFeedback: const KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    ),
    totalUnits: 3,
    sectionCount: 1,
    chunkCount: 3,
  );

  late final List<KnowledgeUnit> _units = List<KnowledgeUnit>.generate(
    3,
    (index) => KnowledgeUnit(
      unitId: 'audio-chunk-${index + 1}',
      documentId: _documentId,
      parentUnitId: 'audio-section-1',
      unitKind: KnowledgeUnitKind.chunk,
      sourceKind: KnowledgeSourceKind.transcript,
      role: KnowledgeRole.evidence,
      ordinal: index,
      tokenCount: 120,
      rawText: 'Chunk ${index + 1} transcript text',
      normalizedText: 'chunk ${index + 1} transcript text',
      anchors: KnowledgeAnchorSet(
        attachmentSha256: 'sha-audio-transcript',
        startMs: index * 15000,
        endMs: (index + 1) * 15000,
        speaker: index == 0 ? 'Alice' : 'Dana',
        sectionLabel: 'Transcript',
      ),
      prevUnitId: index == 0 ? null : 'audio-chunk-$index',
      nextUnitId: index == 2 ? null : 'audio-chunk-${index + 2}',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  );

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
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != _documentId) {
      throw StateError('unexpected document id: $documentId');
    }
    return _viewerDocument;
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
      total: _units.length,
      units: _units.skip(offset).take(limit).toList(growable: false),
    );
  }

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      _units;
}
