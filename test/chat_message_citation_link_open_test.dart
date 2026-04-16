import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/attachments_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_markdown_preview.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/chat/message_deeplink.dart';
import 'package:secondloop/features/knowledge_viewer/knowledge_document_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  test(
      'normalizeChatMarkdownForPreview linkifies bare secondloop message links',
      () {
    final normalized = normalizeChatMarkdownForPreview(
      'Relevant note: secondloop://message/history-1',
    );

    expect(
      normalized,
      contains(
        '[secondloop://message/history-1](secondloop://message/history-1)',
      ),
    );
  });

  test('parseMessageDeepLink parses secondloop message deeplinks', () {
    final parsed = parseMessageDeepLink(
      'secondloop://message/history-1?ignored=true',
    );

    expect(parsed, isNotNull);
    expect(parsed!.messageId, 'history-1');
  });

  test(
      'normalizeChatMarkdownForPreview does not relink bare secondloop links inside brackets',
      () {
    const original = '[secondloop://message/history-1]';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  test(
      'normalizeChatMarkdownForPreview does not relink deep links inside markdown link labels',
      () {
    const original =
        '[text secondloop://message/history-1 more text](https://example.com)';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  test(
      'normalizeChatMarkdownForPreview does not relink deep links inside markdown link labels when inline code contains closing bracket',
      () {
    const original =
        '[note `]` secondloop://message/history-1](https://example.com)';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  test(
      'normalizeChatMarkdownForPreview does not relink deep links in label interior when inline code contains closing bracket',
      () {
    const original =
        '[note `]` secondloop://message/history-1 more](https://example.com)';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  test(
      'normalizeChatMarkdownForPreview does not relink deep links in label interior after nested bracketed segment',
      () {
    const original =
        '[intro [inner](dest) secondloop://message/history-1 more](https://example.com)';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  test(
      'normalizeChatMarkdownForPreview still linkifies bare deep links after orphaned opening bracket on earlier line',
      () {
    const original =
        "Here's what I found: [\n- Project kickoff secondloop://message/history-1";

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(
      normalized,
      contains(
        '[secondloop://message/history-1](secondloop://message/history-1)',
      ),
    );
  });

  test(
      'normalizeChatMarkdownForPreview does not relink deep links inside inline code spans',
      () {
    const original =
        'Use `secondloop://message/history-1` as a literal example.';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  test(
      'normalizeChatMarkdownForPreview still linkifies bare deep links after bracket inside inline code span',
      () {
    const original = '`code [` secondloop://message/history-1';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(
      normalized,
      contains(
        '[secondloop://message/history-1](secondloop://message/history-1)',
      ),
    );
  });

  test(
      'normalizeChatMarkdownForPreview still linkifies bare deep links after blank line breaks inline code span',
      () {
    const original = '''`code

secondloop://message/history-1

`''';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(
      normalized,
      contains(
        '[secondloop://message/history-1](secondloop://message/history-1)',
      ),
    );
  });

  test(
      'normalizeChatMarkdownForPreview does not relink deep links inside tilde fenced code blocks',
      () {
    const original = '~~~\nsecondloop://message/history-1\n~~~';

    final normalized = normalizeChatMarkdownForPreview(original);

    expect(normalized, original);
  });

  testWidgets('chat citation secondloop message link opens message viewer',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'history-1',
          conversationId: 'loop_home',
          role: 'user',
          content: 'Project kickoff moved to Friday afternoon.',
          createdAtMs: 1,
          isMemory: true,
        ),
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'assistant',
          content: 'See [Project kickoff note](secondloop://message/history-1)',
          createdAtMs: 2,
          isMemory: false,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(
      find.textContaining('Project kickoff note', findRichText: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('message_viewer_page')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('message_viewer_page')),
        matching: find.text(
          'Project kickoff moved to Friday afternoon.',
          findRichText: true,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('chat deeplink preserves knowledge document unit targeting',
      (tester) async {
    final backend = _Backend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'loop_home',
          role: 'assistant',
          content:
              'Open [budget note](secondloop://knowledge-document/external%3Adoc-1?chunk=7&unit=external%3Adoc-1%3Achunk%3A0007)',
          createdAtMs: 2,
          isMemory: false,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('budget note', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final page = tester.widget<KnowledgeDocumentViewerPage>(
      find.byType(KnowledgeDocumentViewerPage),
    );
    expect(page.documentId, 'external:doc-1');
    expect(page.initialHighlightedUnitId, 'external:doc-1:chunk:0007');
  });
}

final class _Backend extends TestAppBackend
    implements AttachmentsBackend, KnowledgeViewerBackend {
  _Backend({required List<Message> initialMessages})
      : super(initialMessages: initialMessages);

  final KnowledgeViewerDocument _viewerDocument = const KnowledgeViewerDocument(
    document: ContentKnowledgeDocument(
      documentId: 'external:doc-1',
      originType: KnowledgeOriginType.importedExternal,
      sourceKind: KnowledgeSourceKind.readableText,
      role: KnowledgeRole.evidence,
      language: 'en',
      qualityScore: 0.9,
      createdAtMs: 1,
      updatedAtMs: 1,
      versions: KnowledgeVersionSet(
        schemaVersion: 1,
        normalizationVersion: 1,
        segmentationVersion: 1,
        embeddingPolicyVersion: 1,
        retrievalPolicyVersion: 1,
      ),
      anchors: KnowledgeAnchorSet(),
      title: 'Budget note',
      summary: 'Budget summary',
      rawText: 'Budget note body',
      normalizedText: 'budget note body',
      memoryFeedback: KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    ),
    totalUnits: 1,
    sectionCount: 0,
    chunkCount: 1,
  );

  final KnowledgeUnit _viewerUnit = const KnowledgeUnit(
    unitId: 'external:doc-1:chunk:0007',
    documentId: 'external:doc-1',
    parentUnitId: null,
    unitKind: KnowledgeUnitKind.chunk,
    sourceKind: KnowledgeSourceKind.readableText,
    role: KnowledgeRole.evidence,
    ordinal: 7,
    tokenCount: 4,
    rawText: 'Budget note body',
    normalizedText: 'budget note body',
    anchors: KnowledgeAnchorSet(),
    prevUnitId: null,
    nextUnitId: null,
    createdAtMs: 1,
    updatedAtMs: 1,
  );

  @override
  Future<Attachment?> readAttachmentBySha256(String attachmentSha256) async =>
      null;

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
      const <Attachment>[];

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

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != _viewerDocument.document.documentId) {
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
      documentId: 'external:doc-1',
      unitKind: KnowledgeUnitKind.chunk,
      offset: 0,
      limit: 100,
      total: 1,
      units: <KnowledgeUnit>[
        _viewerUnit,
      ],
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
      <KnowledgeUnit>[_viewerUnit];

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
