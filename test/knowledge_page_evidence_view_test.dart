import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/knowledge_center/knowledge_page_evidence_view.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('KnowledgePageEvidenceView renders classified evidence timeline',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: KnowledgePageEvidenceView(
            pageTitle: 'Preferences',
            entries: [
              KnowledgePageEvidenceEntry(
                evidenceId: 'evidence:1',
                kind: KnowledgePageEvidenceKind.support,
                summary: 'Reply in Chinese by default.',
                sourceRefIds: ['generated:preference:response-language'],
                createdAtMs: 1,
              ),
              KnowledgePageEvidenceEntry(
                evidenceId: 'evidence:2',
                kind: KnowledgePageEvidenceKind.conflict,
                summary: 'Another source suggested English replies.',
                sourceRefIds: ['generated:preference:response-style'],
                createdAtMs: 2,
              ),
              KnowledgePageEvidenceEntry(
                evidenceId: 'evidence:3',
                kind: KnowledgePageEvidenceKind.supplement,
                summary: 'Older formatting preference still exists as context.',
                sourceRefIds: ['generated:preference:response-format'],
                createdAtMs: 3,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Reply in Chinese by default.'), findsWidgets);
    expect(
        find.text('Another source suggested English replies.'), findsOneWidget);
    expect(find.text('Older formatting preference still exists as context.'),
        findsOneWidget);
  });
}
