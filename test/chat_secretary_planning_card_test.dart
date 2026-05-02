import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/secretary/secretary_models.dart';
import 'package:secondloop/features/secretary/chat_secretary_cards.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('planning card stays compact and opens review', (tester) async {
    var viewed = false;
    var reminded = false;
    var ignored = false;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ChatSecretaryPlanningCard(
              plan: _plan(),
              onViewPlan: () => viewed = true,
              onRemindLater: () => reminded = true,
              onIgnore: () => ignored = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Daily plan generated'), findsOneWidget);
    expect(find.text('Complete app dictionary MVP'), findsNothing);
    expect(find.text('3 suggestions, 2 need confirmation'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('secretary_plan_view')));
    expect(viewed, isTrue);
    await tester.tap(find.byKey(const ValueKey('secretary_plan_remind_later')));
    expect(reminded, isTrue);
    await tester.tap(find.byKey(const ValueKey('secretary_plan_ignore')));
    expect(ignored, isTrue);
  });

  testWidgets('planning card localizes labels in zh-CN', (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: Scaffold(
            body: ChatSecretaryPlanningCard(
              plan: _plan(),
              onViewPlan: () {},
              onRemindLater: () {},
              onIgnore: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('已生成今日计划'), findsOneWidget);
    expect(find.text('3 条建议，2 条需要确认'), findsOneWidget);
    expect(find.text('基于当前事项和近期活动'), findsOneWidget);
    expect(find.text('查看计划'), findsOneWidget);
    expect(find.text('稍后提醒'), findsOneWidget);
    expect(find.text('忽略'), findsOneWidget);
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
      needsDecision: [
        SecretaryPlanItem(
          id: 'p3',
          todoId: 't3',
          title: 'Choose launch scope',
          reason: 'Stale',
          requiresConfirmation: true,
        ),
      ],
      missingNextAction: [],
    ),
  );
}
