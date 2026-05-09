import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/secretary/secretary_models.dart';
import 'package:secondloop/features/secretary/chat_secretary_cards.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('runtime planning card exposes actions without digest text',
      (tester) async {
    var viewed = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryPlanningCard(
              plan: const SecretaryPlan(
                id: 'runtime-plan-1',
                title: 'Runtime daily plan',
                generatedAtMs: 1700000000000,
                route: 'cloud_runtime',
                generatedBy: 'cloud_runtime',
                sections: SecretaryPlanSections(
                  focus: [
                    SecretaryPlanItem(
                      id: 'runtime-item-1',
                      todoId: 'task-1',
                      title: 'Submit review',
                      reason: 'open',
                      requiresConfirmation: true,
                    ),
                  ],
                  dueSoon: [],
                  needsDecision: [],
                  missingNextAction: [],
                ),
              ),
              onViewPlan: () => viewed = true,
              onRemindLater: () {},
              onIgnore: () {},
            ),
          ),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('secretary_planning_card')), findsOneWidget);
    expect(find.text('1 suggestion, 1 needs confirmation'), findsOneWidget);
    expect(find.textContaining('digest', findRichText: true), findsNothing);

    await tester.tap(find.byKey(const ValueKey('secretary_plan_view')));

    expect(viewed, isTrue);
  });
}
