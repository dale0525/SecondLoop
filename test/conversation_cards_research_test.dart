import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/conversation_cards/research_brief_card.dart';
import 'package:secondloop/features/conversation_cards/research_models.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('ResearchBudgetConfirmationCard shows cost and scope actions',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ResearchBudgetConfirmationCard(
              estimate: ResearchBudgetEstimate.demo(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('High-cost research confirmation'), findsOneWidget);
    expect(find.text('42 pages'), findsOneWidget);
    expect(find.text('36k tokens'), findsOneWidget);
    expect(find.text(r'$2.40 estimated'), findsOneWidget);
    expect(find.text('Start research'), findsOneWidget);
    expect(find.text('Reduce scope'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('ResearchResultCard switches isolated generic result tabs',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ResearchResultCard(result: ResearchResult.demo()),
          ),
        ),
      ),
    );

    expect(find.text('Brief'), findsOneWidget);
    expect(find.text('Key points'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Draft note'), findsOneWidget);
    expect(
      find.text('Use this outline as a note after reviewing the citations.'),
      findsNothing,
    );
    expect(find.text('OpenAI Docs'), findsNothing);

    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI Docs'), findsOneWidget);
    expect(find.text('openai.com'), findsOneWidget);
    expect(find.text('Fetched May 13, 2026 09:20'), findsOneWidget);
    expect(find.text('[1]'), findsOneWidget);
    expect(
      find.text('Use this outline as a note after reviewing the citations.'),
      findsNothing,
    );

    await tester.tap(find.text('Draft note'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use this outline as a note after reviewing the citations.'),
      findsOneWidget,
    );
    expect(find.text('OpenAI Docs'), findsNothing);

    expect(find.text('Market size'), findsNothing);
    expect(find.text('Recommendation'), findsNothing);
    expect(find.text('Risk'), findsNothing);
    expect(find.text('Comparison table'), findsNothing);
  });
}
