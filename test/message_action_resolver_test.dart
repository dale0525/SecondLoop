import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/todo/message_action_resolver.dart';
import 'package:secondloop/features/actions/todo/todo_linking.dart';

void main() {
  test('followup: zh done keyword + todo match wins over create', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final targets = <TodoLinkTarget>[
      const TodoLinkTarget(id: 'todo:1', title: '报销', status: 'inbox'),
    ];

    final decision = MessageActionResolver.resolve(
      '今天把报销搞定了',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: targets,
    );

    expect(decision, isA<MessageActionFollowUpDecision>());
    final follow = decision as MessageActionFollowUpDecision;
    expect(follow.todoId, 'todo:1');
    expect(follow.newStatus, 'done');
  });

  test('does not treat "今天把 X 做完了" as create just because of today', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      '今天把 X 做完了',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision is MessageActionCreateDecision, isFalse);
  });

  test('creates inbox for structured TODO with no time', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      'TODO: renew passport',
      locale: const Locale('en'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, 'renew passport');
    expect(create.dueAtLocal, isNull);
    expect(create.status, 'inbox');
  });

  test('creates open + dueAtLocal for unambiguous time', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      '明天 3pm 提交材料',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, '提交材料');
    expect(create.status, 'open');
    expect(create.dueAtLocal, DateTime(2026, 1, 25, 15, 0));
  });

  test('smoke: multilingual time create', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final cases = <({Locale locale, String text})>[
      (locale: const Locale('ja'), text: '明日 3pm 書類提出'),
      (locale: const Locale('ko'), text: '내일 3pm 서류 제출'),
      (locale: const Locale('es'), text: 'mañana 3pm enviar documentos'),
      (locale: const Locale('fr'), text: 'demain 3pm soumettre documents'),
      (locale: const Locale('de'), text: 'morgen 3pm dokumente einreichen'),
    ];

    for (final c in cases) {
      final decision = MessageActionResolver.resolve(
        c.text,
        locale: c.locale,
        nowLocal: now,
        dayEndMinutes: 21 * 60,
        openTodoTargets: const <TodoLinkTarget>[],
      );
      expect(
        decision,
        isA<MessageActionCreateDecision>(),
        reason: 'locale=${c.locale} text=${c.text}',
      );
    }
  });

  test('recurring zh weekly phrase strips weekday/time from title cleanly', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      '每周三下午3点提交周报',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      morningMinutes: 9 * 60,
      firstDayOfWeekIndex: 1,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.recurrenceRule!.freq, 'weekly');
    expect(create.title, '提交周报');
  });

  test('recurring yearly sentence keeps natural title text', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      '老婆的生日是 8 月 8 号，每年的这个时候提醒我买礼物',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      morningMinutes: 9 * 60,
      firstDayOfWeekIndex: 1,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.recurrenceRule!.freq, 'yearly');
    expect(create.title, '老婆的生日提醒我买礼物');
  });

  test(
      'recurring weekly without explicit datetime uses next period start morning',
      () {
    final now = DateTime(2026, 1, 28, 19, 30); // Wednesday
    final decision = MessageActionResolver.resolve(
      '每周复盘',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      morningMinutes: 8 * 60 + 30,
      firstDayOfWeekIndex: 1,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.dueAtLocal, DateTime(2026, 2, 2, 8, 30));
  });

  test(
      'recurring monthly without explicit datetime uses next period first day morning',
      () {
    final now = DateTime(2026, 1, 28, 19, 30);
    final decision = MessageActionResolver.resolve(
      '每月整理账单',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      morningMinutes: 7 * 60,
      firstDayOfWeekIndex: 1,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.dueAtLocal, DateTime(2026, 2, 1, 7, 0));
  });
  test('creates recurring todo for zh daily phrase', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      '每天 9:00 记账',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.recurrenceRule!.freq, 'daily');
    expect(create.status, 'open');
  });

  test('creates recurring todo for es yearly phrase with accents', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      'cada año revisar seguro',
      locale: const Locale('es'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.recurrenceRule!.freq, 'yearly');
    expect(create.title, 'revisar seguro');
  });
  test('creates recurring todo for en weekly phrase', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      'every week send project update',
      locale: const Locale('en'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.recurrenceRule!.freq, 'weekly');
    expect(create.dueAtLocal, isNotNull);
  });
}
