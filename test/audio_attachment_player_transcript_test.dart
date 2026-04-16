import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/theme.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/attachments/audio_attachment_player.dart';
import 'package:secondloop/features/knowledge_viewer/knowledge_document_viewer.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'AudioAttachmentPlayerView renders full text, retry, and edit actions',
      (tester) async {
    final attachment = Attachment(
      sha256: 'audio-transcript-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-transcript-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    var retryInvoked = 0;
    String? savedFull;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              displayTitle: 'Audio attachment',
              initialAnnotationPayload: const <String, Object?>{
                'duration_ms': 42000,
                'transcript_excerpt': 'hello transcript excerpt',
                'transcript_full':
                    'hello transcript excerpt with more details for full text',
              },
              onRetryRecognition: () async {
                retryInvoked += 1;
              },
              onSaveFull: (value) async {
                savedFull = value;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('attachment_text_summary_display')),
        findsNothing);
    expect(find.byKey(const ValueKey('attachment_text_full_markdown_display')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_text_full_regenerate')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('attachment_metadata_format')), findsNothing);

    expect(find.byKey(const ValueKey('attachment_text_summary_edit')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('attachment_text_full_edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
        findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat_markdown_editor_input')),
      '# Edited Full',
    );
    await tester.tap(find.byKey(const ValueKey('chat_markdown_editor_save')));
    await tester.pumpAndSettle();

    expect(savedFull, '# Edited Full');
    expect(find.text('Full text'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('attachment_text_full_regenerate')));
    await tester.pump();
    expect(retryInvoked, 1);
  });

  testWidgets(
      'AudioAttachmentPlayerView keeps player width aligned with transcript and styles seek slider',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final attachment = Attachment(
      sha256: 'audio-layout-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-layout-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              displayTitle: 'Audio attachment',
              initialAnnotationPayload: const <String, Object?>{
                'transcript_full': 'A full transcript shown in the detail page',
                'duration_ms': 42000,
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    final playerCardFinder =
        find.byKey(const ValueKey('audio_attachment_player_card'));
    final transcriptCardFinder =
        find.byKey(const ValueKey('attachment_text_full_card'));

    expect(find.byKey(const ValueKey('attachment_detail_workspace')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_header_bar')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_detail_inspector')),
        findsOneWidget);
    expect(find.text('Audio attachment'), findsOneWidget);
    expect(find.text('audio/mp4'), findsWidgets);
    expect(find.text('00:42'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(playerCardFinder, findsOneWidget);
    expect(transcriptCardFinder, findsOneWidget);

    final playerSize = tester.getSize(playerCardFinder);
    final transcriptSize = tester.getSize(transcriptCardFinder);
    expect(transcriptSize.width, lessThanOrEqualTo(playerSize.width));

    final sliderFinder =
        find.byKey(const ValueKey('audio_attachment_seek_slider'));
    expect(sliderFinder, findsOneWidget);

    final sliderThemeFinder = find.ancestor(
      of: sliderFinder,
      matching: find.byType(SliderTheme),
    );
    expect(sliderThemeFinder, findsOneWidget);

    final sliderTheme = tester.widget<SliderTheme>(sliderThemeFinder);
    final sliderThemeData = sliderTheme.data;
    expect(sliderThemeData.activeTrackColor, isNotNull);
    expect(sliderThemeData.thumbColor, isNotNull);
    expect(
      sliderThemeData.activeTrackColor,
      isNot(equals(sliderThemeData.inactiveTrackColor)),
    );

    await tester
        .tap(find.byKey(const ValueKey('attachment_detail_tab_metadata')));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('16 B'), findsOneWidget);
  });

  testWidgets('AudioAttachmentPlayerView keeps transcript_full for detail text',
      (
    tester,
  ) async {
    final attachment = Attachment(
      sha256: 'audio-turn-view-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-turn-view-sha.bin',
      byteLen: _tinyM4a.length,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: AudioAttachmentPlayerView(
              attachment: attachment,
              bytes: _tinyM4a,
              displayTitle: 'Audio attachment',
              initialAnnotationPayload: const <String, Object?>{
                'duration_ms': 42000,
                'transcript_excerpt': 'raw excerpt',
                'transcript_full': 'raw transcript body',
                'transcript_turns_v1': {
                  'builder_version': 'turns_v1',
                  'status': 'ok',
                  'turns': [
                    {
                      'start_ms': 12000,
                      'end_ms': 18000,
                      'text': 'Hello everyone.',
                      'segment_count': 1,
                      'source_segment_start_index': 0,
                      'source_segment_end_index': 0,
                    },
                  ],
                },
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('raw transcript body'), findsOneWidget);
    expect(
      find.textContaining('[00:12–00:18] Hello everyone.'),
      findsNothing,
    );
  });

  testWidgets(
      'AudioAttachmentPlayerView falls back when knowledge viewer transcript is less readable',
      (tester) async {
    final backend = _AudioTranscriptKnowledgeBackend();
    final rawTranscript = List<String>.generate(
      130,
      (index) =>
          'Speaker line ${index + 1}. Another sentence for transcript readability.',
    ).join('\n');
    final formattedTranscript = rawTranscript.replaceAll('\n', '\n\n');
    final attachment = Attachment(
      sha256: 'audio-knowledge-sha',
      mimeType: 'audio/mp4',
      path: 'attachments/audio-knowledge-sha.bin',
      byteLen: _tinyM4a.length,
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
              child: Scaffold(
                body: AudioAttachmentPlayerView(
                  attachment: attachment,
                  bytes: _tinyM4a,
                  displayTitle: 'Audio attachment',
                  initialAnnotationPayload: <String, Object?>{
                    'transcript_full': rawTranscript,
                    'duration_ms': 42000,
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attachment_text_full_card')),
        findsOneWidget);
    expect(find.textContaining(formattedTranscript.split('\n\n').first),
        findsOneWidget);
    expect(find.byType(KnowledgeDocumentViewer), findsNothing);
  });
}

final Uint8List _tinyM4a = Uint8List.fromList(const <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x4D,
  0x34,
  0x41,
  0x20,
  0x69,
  0x73,
  0x6F,
  0x6D,
]);

final class _AudioTranscriptKnowledgeBackend extends TestAppBackend
    implements KnowledgeViewerBackend {
  static const String _documentId = 'attachment:audio-knowledge-sha:transcript';

  late final KnowledgeViewerDocument viewerDocument = KnowledgeViewerDocument(
    document: ContentKnowledgeDocument(
      documentId: _documentId,
      originType: KnowledgeOriginType.attachment,
      sourceKind: KnowledgeSourceKind.transcript,
      role: KnowledgeRole.evidence,
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
        attachmentSha256: 'audio-knowledge-sha',
        sourceFilename: 'call.m4a',
      ),
      title: 'Call transcript',
      summary: 'Call transcript',
      rawText: List<String>.generate(
        130,
        (index) =>
            'Speaker line ${index + 1}. Another sentence for transcript readability.',
      ).join('\n'),
      normalizedText: 'call transcript normalized',
      memoryFeedback: const KnowledgeMemoryFeedback(
        useForAskAi: true,
        isDeleted: false,
        markedInaccurate: false,
      ),
    ),
    totalUnits: 4,
    sectionCount: 1,
    chunkCount: 4,
  );

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async {
    if (documentId != _documentId) {
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
    return const KnowledgeViewerPage(
      documentId: _documentId,
      unitKind: null,
      offset: 0,
      limit: 0,
      total: 0,
      units: <KnowledgeUnit>[],
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
      const <KnowledgeUnit>[];

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
