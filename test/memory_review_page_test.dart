import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/secretary/secretary_models.dart';
import 'package:secondloop/features/secretary/memory_review_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('memory review groups pending and current memories',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: MemoryReviewPage(
            pending: [
              SecretaryMemoryProposal(
                id: 'p1',
                sourceMessageId: 'm1',
                kind: 'preference',
                title: 'Morning meetings',
                body: 'I prefer morning meetings.',
                confidence: 0.9,
                createdAtMs: 1,
              ),
            ],
            current: [
              SecretaryMemoryPage(
                id: 'mem1',
                title: 'Writing routine',
                body: 'Drafts are reviewed before noon.',
                state: SecretaryMemoryState.active,
                updatedAtMs: 2,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Long-term memory'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Morning meetings'), findsOneWidget);
    expect(find.text('Writing routine'), findsOneWidget);
  });
}
