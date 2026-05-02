import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/secretary/secretary_models.dart';
import 'package:secondloop/features/secretary/planning_review_page.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('planning review shows sections and gated suggestion actions',
      (tester) async {
    final accepted = <String>[];
    final dismissed = <String>[];

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: PlanningReviewPage(
            plan: _plan(),
            onAcceptSuggestion: accepted.add,
            onDismissSuggestion: dismissed.add,
          ),
        ),
      ),
    );

    expect(find.text('Planning Review'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('Needs decision'), findsOneWidget);
    expect(
        find.text('Suggestions need confirmation before changes are written.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('secretary_plan_accept_p1')));
    await tester.pump();
    expect(accepted, ['p1']);
    expect(
        find.byKey(const ValueKey('secretary_plan_accept_p1')), findsNothing);
    expect(find.text('Suggestion accepted.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('secretary_plan_dismiss_p2')));
    await tester.pump();

    expect(accepted, ['p1']);
    expect(dismissed, ['p2']);
    expect(
        find.byKey(const ValueKey('secretary_plan_dismiss_p2')), findsNothing);
    expect(find.text('Suggestion ignored.'), findsOneWidget);
  });

  testWidgets('planning review localizes labels in zh-CN', (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: PlanningReviewPage(plan: _plan()),
        ),
      ),
    );

    expect(find.text('计划复核'), findsOneWidget);
    expect(find.text('聚焦'), findsOneWidget);
    expect(find.text('需要决策'), findsOneWidget);
    expect(find.text('建议需要确认后才会写入更改。'), findsOneWidget);
    expect(find.text('接受'), findsWidgets);
    expect(find.text('忽略'), findsWidgets);
  });
}

SecretaryPlan _plan() {
  return const SecretaryPlan(
    id: 'plan-local',
    title: 'Daily plan',
    generatedAtMs: 100,
    route: 'local_rules',
    sections: SecretaryPlanSections(
      focus: [
        SecretaryPlanItem(
          id: 'p1',
          todoId: 't1',
          title: 'Complete app dictionary MVP',
          reason: 'Due today',
          requiresConfirmation: true,
        ),
      ],
      dueSoon: [
        SecretaryPlanItem(
          id: 'p2',
          todoId: 't2',
          title: 'Review sync notes',
          reason: 'Due tomorrow',
        ),
      ],
      needsDecision: [],
      missingNextAction: [],
    ),
  );
}
