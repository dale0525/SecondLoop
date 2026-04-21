import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_answer_evidence_models.dart';
import 'package:secondloop/features/chat/chat_answer_evidence_sheet.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('ChatAnswerEvidencePanel keeps pure message evidence read-only',
      (tester) async {
    var openedDirectSource = '';

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
                  sourceTypeLabel: 'chat_message',
                  scopeLabel: 'this_thread',
                  confidenceLabel: 'high_relevance',
                  title: 'Kickoff notes',
                  snippet: 'Kickoff moved to Friday afternoon.',
                  highlightedText: 'Kickoff moved to Friday afternoon.',
                  createdAtMs: 1,
                  updatedAtMs: 2,
                  documentId: null,
                  unitId: null,
                ),
              ],
            ),
            onOpenDirectSource: (href) async {
              openedDirectSource = href;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Kickoff notes'), findsOneWidget);
    expect(find.text('Chat message'), findsOneWidget);
    expect(find.text('This thread'), findsOneWidget);
    expect(find.text('High relevance'), findsOneWidget);
    expect(find.text('View original'), findsNothing);

    await tester.pumpAndSettle();

    expect(openedDirectSource, isEmpty);
  });

  testWidgets(
      'ChatAnswerEvidencePanel keeps item and attachment evidence clickable',
      (tester) async {
    var openedDirectSource = '';

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: ChatAnswerEvidencePanel(
            evidence: const ChatAnswerEvidence(
              directSources: [
                ChatAnswerEvidenceDirectSource(
                  id: 'todo:budget-follow-up',
                  href: 'secondloop://todo/todo-budget-follow-up',
                  sourceType: 'item',
                  label: 'Item',
                  sourceTypeLabel: 'item',
                  scopeLabel: null,
                  confidenceLabel: 'relevant',
                  title: 'Prepare budget freeze follow-up',
                  snippet: 'TODO [open] Prepare budget freeze follow-up',
                  highlightedText: 'Prepare budget freeze follow-up',
                  createdAtMs: 1,
                  updatedAtMs: 2,
                  documentId: null,
                  unitId: null,
                ),
                ChatAnswerEvidenceDirectSource(
                  id: 'attachment:sha:readable_text_full:0',
                  href:
                      'secondloop://attachment/sha?kind=readable_text_full&chunk=0',
                  sourceType: 'attachment',
                  label: 'Attachment',
                  sourceTypeLabel: 'attachment_text',
                  scopeLabel: null,
                  confidenceLabel: null,
                  title: 'Meeting notes',
                  snippet: 'Budget freeze details from the attachment.',
                  highlightedText: 'Budget freeze details from the attachment.',
                  createdAtMs: 3,
                  updatedAtMs: 4,
                  documentId: null,
                  unitId: 'unit-1',
                ),
              ],
            ),
            onOpenDirectSource: (href) async {
              openedDirectSource = href;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Item'), findsOneWidget);
    expect(find.text('Attachment text'), findsOneWidget);
    expect(find.text('Relevant'), findsOneWidget);
    expect(find.text('View original'), findsNWidgets(2));

    await tester.tap(find.text('View original').first);
    await tester.pumpAndSettle();

    expect(openedDirectSource, 'secondloop://todo/todo-budget-follow-up');
  });

  testWidgets(
      'ChatAnswerEvidencePanel shows unsupported snackbar when direct source cannot open',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: ChatAnswerEvidencePanel(
            evidence: ChatAnswerEvidence(
              directSources: [
                ChatAnswerEvidenceDirectSource(
                  id: 'todo:missing-follow-up',
                  href: 'secondloop://todo/todo-missing-follow-up',
                  sourceType: 'item',
                  label: 'Item',
                  sourceTypeLabel: 'item',
                  scopeLabel: null,
                  confidenceLabel: 'relevant',
                  title: 'Missing follow-up',
                  snippet: 'TODO [open] Missing follow-up',
                  highlightedText: 'Missing follow-up',
                  createdAtMs: 1,
                  updatedAtMs: 2,
                  documentId: null,
                  unitId: null,
                ),
              ],
            ),
            onOpenDirectSource: _cannotOpenDirectSource,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('View original'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Load failed: unsupported_secondloop_link'), findsOne);
  });
}

Future<bool> _cannotOpenDirectSource(String href) async => false;
