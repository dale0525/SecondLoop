import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_answer_evidence_models.dart';
import 'package:secondloop/features/chat/chat_answer_evidence_sheet.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('ChatAnswerEvidencePanel renders both tabs and actions',
      (tester) async {
    var openedDirectSource = '';
    var openedMemoryDocument = '';
    var correctedMemoryDocument = '';
    var correctedTitle = '';
    var correctedSummary = '';
    var disabledMemoryDocument = '';
    var deletedMemoryDocument = '';

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: ChatAnswerEvidencePanel(
            evidence: const ChatAnswerEvidence(
              directSources: [
                ChatAnswerEvidenceDirectSource(
                  id: 'message:history-1',
                  href: 'secondloop://message/history-1',
                  sourceType: 'message',
                  label: 'History',
                  sourceTypeLabel: 'Chat message',
                  scopeLabel: 'This thread',
                  confidenceLabel: 'High relevance',
                  title: 'Kickoff notes',
                  snippet: 'Kickoff moved to Friday afternoon.',
                  highlightedText: 'Kickoff moved to Friday afternoon.',
                  createdAtMs: 1,
                  updatedAtMs: 2,
                  documentId: null,
                  unitId: null,
                ),
              ],
              memoryCards: [
                ChatAnswerEvidenceMemoryCard(
                  documentId: 'generated:preference:response-language',
                  title: 'Response language',
                  summary: 'User prefers Chinese.',
                  sourceKind: 'summary',
                  role: 'summary',
                  createdAtMs: 3,
                  updatedAtMs: 4,
                  status: 'confirmed',
                  sourceCount: 2,
                  whyUsed: 'The user asked in Chinese.',
                ),
              ],
            ),
            initialTab: ChatAnswerEvidenceTab.directSources,
            onOpenDirectSource: (href) async => openedDirectSource = href,
            onOpenMemoryCard: (documentId) async =>
                openedMemoryDocument = documentId,
            onCorrectMemoryCard: (card, title, summary) async {
              correctedMemoryDocument = card.documentId;
              correctedTitle = title;
              correctedSummary = summary;
              return card.copyWith(
                title: title,
                summary: summary,
                status: 'confirmed',
              );
            },
            onDisableMemoryCard: (documentId) async =>
                disabledMemoryDocument = documentId,
            onDeleteMemoryCard: (documentId) async =>
                deletedMemoryDocument = documentId,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kickoff notes'), findsOneWidget);
    expect(find.text('Chat message'), findsOneWidget);
    expect(find.text('This thread'), findsOneWidget);
    expect(find.text('High relevance'), findsOneWidget);
    await tester.tap(find.text('View original'));
    await tester.pumpAndSettle();
    expect(openedDirectSource, 'secondloop://message/history-1');

    await tester.tap(find.textContaining('Memory cards'));
    await tester.pumpAndSettle();
    expect(find.text('Response language'), findsOneWidget);
    await tester.tap(find.text('Inspect memory'));
    await tester.pumpAndSettle();
    expect(openedMemoryDocument, 'generated:preference:response-language');
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_title_field')),
      'Preferred reply language',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Always reply in Chinese unless another language is requested.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(correctedMemoryDocument, 'generated:preference:response-language');
    expect(correctedTitle, 'Preferred reply language');
    expect(
      correctedSummary,
      'Always reply in Chinese unless another language is requested.',
    );
    expect(find.text('Preferred reply language'), findsOneWidget);
    expect(
      find.text(
        'Always reply in Chinese unless another language is requested.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirmed'), findsOneWidget);
    await tester.tap(find.text('Don\'t use'));
    await tester.pumpAndSettle();
    expect(disabledMemoryDocument, 'generated:preference:response-language');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deletedMemoryDocument, 'generated:preference:response-language');
  });

  testWidgets('showChatAnswerEvidenceSheet uses right drawer on wide layouts',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showChatAnswerEvidenceSheet(
                      context,
                      evidence: const ChatAnswerEvidence(
                        directSources: [
                          ChatAnswerEvidenceDirectSource(
                            id: 'message:history-1',
                            href: 'secondloop://message/history-1',
                            sourceType: 'message',
                            label: 'History',
                            sourceTypeLabel: 'Chat message',
                            scopeLabel: 'This thread',
                            confidenceLabel: 'High relevance',
                            title: 'Kickoff notes',
                            snippet: 'Kickoff moved to Friday afternoon.',
                            highlightedText:
                                'Kickoff moved to Friday afternoon.',
                            createdAtMs: 1,
                            updatedAtMs: 2,
                            documentId: null,
                            unitId: null,
                          ),
                        ],
                        memoryCards: [],
                      ),
                      onOpenDirectSource: (_) async {},
                      onOpenMemoryCard: (_) async {},
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('answer_evidence_desktop_drawer')),
        findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
