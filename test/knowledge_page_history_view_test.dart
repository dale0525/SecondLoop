import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/knowledge_center/knowledge_page_history_view.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('KnowledgePageHistoryView renders change records',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: KnowledgePageHistoryView(
            pageTitle: 'Preferences',
            history: [
              KnowledgePageChangeRecord(
                changeId: 'change:1',
                pageId: 'page:preferences',
                changeType: KnowledgePageChangeType.corrected,
                actor: 'user',
                reason: 'Manual correction applied.',
                answerImpacted: true,
                createdAtMs: 1,
              ),
              KnowledgePageChangeRecord(
                changeId: 'change:2',
                pageId: 'page:preferences',
                changeType: KnowledgePageChangeType.updated,
                actor: 'system',
                reason: 'Compiled from recent evidence.',
                answerImpacted: true,
                createdAtMs: 2,
              ),
            ],
            versionSnapshots: [
              KnowledgePageVersionSnapshot(
                versionId: 'version:1',
                pageId: 'page:preferences',
                title: 'Reply Preferences',
                summary: 'Reply in Chinese by default.',
                body: 'Reply in Chinese by default.\nKeep answers concise.',
                state: KnowledgePageState.active,
                answerPolicy: KnowledgeAnswerPolicy(
                  defaultAllowed: true,
                  requiresTemporalFraming: false,
                ),
                confidenceLevel: 0.9,
                sourceCount: 2,
                conflictCount: 0,
                humanCorrected: true,
                actor: 'user',
                changeType: KnowledgePageChangeType.corrected,
                reason: 'Manual correction applied.',
                createdAtMs: 2,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Manual correction applied.'), findsWidgets);
    expect(find.text('Compiled from recent evidence.'), findsOneWidget);
    expect(find.text('Reply Preferences'), findsOneWidget);
  });
}
