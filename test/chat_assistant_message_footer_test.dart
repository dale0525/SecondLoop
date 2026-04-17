import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/suggestions_parser.dart';
import 'package:secondloop/features/chat/chat_answer_evidence_models.dart';
import 'package:secondloop/features/chat/chat_assistant_message_footer.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('footer places evidence actions above next-step suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatAssistantMessageFooter(
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
              ),
              onOpenSources: () {},
              onOpenEvidence: () {},
              actionSuggestions: const [
                ActionSuggestion(type: 'todo', title: 'Draft outline'),
              ],
              onTapActionSuggestion: (_, __) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final evidenceRect = tester.getRect(
      find.byKey(const ValueKey('assistant_message_footer_evidence')),
    );
    final suggestionRect = tester.getRect(
      find.byKey(const ValueKey('assistant_message_footer_suggestions')),
    );

    expect(evidenceRect.bottom, lessThanOrEqualTo(suggestionRect.top));
    expect(find.text('Open evidence'), findsOneWidget);
    expect(find.text('Draft outline'), findsOneWidget);
  });
}
