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
    expect(follow.dueAtLocal, isNull);
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

  test('followup can extract due update without forcing a status change', () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      '把报销改到年初一之后第一个工作日',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );

    expect(decision, isA<MessageActionFollowUpDecision>());
    final follow = decision as MessageActionFollowUpDecision;
    expect(follow.todoId, 'todo:1');
    expect(follow.newStatus, isNull);
    expect(follow.dueAtLocal, isNotNull);
  });

  test('followup can combine explicit status and due update in one decision',
      () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      '把报销完成并改到明天',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );

    expect(decision, isA<MessageActionFollowUpDecision>());
    final follow = decision as MessageActionFollowUpDecision;
    expect(follow.todoId, 'todo:1');
    expect(follow.newStatus, 'done');
    expect(follow.dueAtLocal, DateTime(2026, 2, 5, 21, 0));
  });

  test(
      'holiday due phrases keep the task title instead of stripping the whole message',
      () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      '节后第一个工作日处理报销',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, '处理报销');
    expect(create.dueAtLocal, DateTime(2026, 2, 24, 21, 0));
  });

  test('localized followup reschedule cues do not regress to create', () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final cases = <({String text, Locale locale, DateTime expectedDueAt})>[
      (
        text: 'déplacer remboursement à mardi',
        locale: const Locale('fr'),
        expectedDueAt: DateTime(2026, 2, 10, 21, 0),
      ),
      (
        text: 'verschieben erstattung auf freitag',
        locale: const Locale('de'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
      (
        text: '経費精算を金曜日に変更',
        locale: const Locale('ja'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
      (
        text: '환급을 금요일로 변경',
        locale: const Locale('ko'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
    ];

    for (final c in cases) {
      final decision = MessageActionResolver.resolve(
        c.text,
        locale: c.locale,
        nowLocal: now,
        dayEndMinutes: 21 * 60,
        openTodoTargets: const <TodoLinkTarget>[
          TodoLinkTarget(id: 'todo:1', title: 'remboursement', status: 'open'),
          TodoLinkTarget(id: 'todo:2', title: 'erstattung', status: 'open'),
          TodoLinkTarget(id: 'todo:3', title: '経費精算', status: 'open'),
          TodoLinkTarget(id: 'todo:4', title: '환급', status: 'open'),
        ],
      );

      expect(
        decision,
        isA<MessageActionFollowUpDecision>(),
        reason: 'locale=${c.locale} text=${c.text}',
      );
      final follow = decision as MessageActionFollowUpDecision;
      expect(follow.newStatus, isNull,
          reason: 'locale=${c.locale} text=${c.text}');
      expect(follow.dueAtLocal, c.expectedDueAt,
          reason: 'locale=${c.locale} text=${c.text}');
    }
  });

  test('time plus matching title does not force followup without edit cue', () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      '周五报销',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
      ],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, '报销');
    expect(create.dueAtLocal, DateTime(2026, 2, 6, 21, 0));
  });

  test(
      'deictic followup edit does not create todo when no candidate is available',
      () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      'move this to tomorrow',
      locale: const Locale('en', 'US'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionNoneDecision>());
  });

  test(
      'generic english change phrasing still allows create when no todo matches',
      () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      'change travel booking to Friday',
      locale: const Locale('en', 'US'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: 'expense report', status: 'open'),
        TodoLinkTarget(id: 'todo:2', title: 'call Alice', status: 'open'),
      ],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, 'change travel booking');
    expect(create.dueAtLocal, DateTime(2026, 2, 6, 21, 0));
  });

  test('create titles keep leading action verbs when no todo matches', () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final decision = MessageActionResolver.resolve(
      'change oil tomorrow',
      locale: const Locale('en', 'US'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[
        TodoLinkTarget(id: 'todo:1', title: 'expense report', status: 'open'),
      ],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, 'change oil');
    expect(create.dueAtLocal, DateTime(2026, 2, 5, 21, 0));
  });

  test('next-week weekday create keeps correct due date and clean title', () {
    final now = DateTime(2026, 2, 2, 10, 0); // Monday
    final decision = MessageActionResolver.resolve(
      '下周二报销',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionCreateDecision>());
    final create = decision as MessageActionCreateDecision;
    expect(create.title, '报销');
    expect(create.dueAtLocal, DateTime(2026, 2, 10, 21, 0));
  });

  test(
      'followup keeps day-after-tomorrow semantics for localized relative days',
      () {
    final now = DateTime(2026, 2, 4, 10, 0);
    final cases = <({String text, Locale locale, DateTime expectedDueAt})>[
      (
        text: '把报销改到übermorgen',
        locale: const Locale('de'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
      (
        text: '把报销改到après-demain',
        locale: const Locale('fr'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
      (
        text: '把报销改到明後日',
        locale: const Locale('ja'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
      (
        text: '把报销改到모레',
        locale: const Locale('ko'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
      (
        text: '把报销改到mardi',
        locale: const Locale('fr'),
        expectedDueAt: DateTime(2026, 2, 10, 21, 0),
      ),
      (
        text: '把报销改到금요일',
        locale: const Locale('ko'),
        expectedDueAt: DateTime(2026, 2, 6, 21, 0),
      ),
    ];

    for (final c in cases) {
      final decision = MessageActionResolver.resolve(
        c.text,
        locale: c.locale,
        nowLocal: now,
        dayEndMinutes: 21 * 60,
        openTodoTargets: const <TodoLinkTarget>[
          TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
        ],
      );

      expect(
        decision,
        isA<MessageActionFollowUpDecision>(),
        reason: 'locale=${c.locale} text=${c.text}',
      );
      final follow = decision as MessageActionFollowUpDecision;
      expect(follow.todoId, 'todo:1',
          reason: 'locale=${c.locale} text=${c.text}');
      expect(follow.newStatus, isNull,
          reason: 'locale=${c.locale} text=${c.text}');
      expect(follow.dueAtLocal, c.expectedDueAt,
          reason: 'locale=${c.locale} text=${c.text}');
    }
  });

  test('does not create todo from long-form note with schedule text', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      '明天 3pm 提交材料\n补充：先确认报价，再整理附件后再发送。',
      locale: const Locale('zh', 'CN'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionNoneDecision>());
  });

  test('does not create todo from long single-line note over threshold', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final decision = MessageActionResolver.resolve(
      'tomorrow 3pm submit report with budget details, invoice checklist, stakeholders updates, and audit notes for weekly review',
      locale: const Locale('en'),
      nowLocal: now,
      dayEndMinutes: 21 * 60,
      openTodoTargets: const <TodoLinkTarget>[],
    );

    expect(decision, isA<MessageActionNoneDecision>());
  });

  test('long-form note can still map to followup for existing todo', () {
    final now = DateTime(2026, 1, 24, 12, 0);
    final targets = <TodoLinkTarget>[
      const TodoLinkTarget(id: 'todo:1', title: '报销', status: 'inbox'),
    ];

    final decision = MessageActionResolver.resolve(
      '今天把报销搞定了。\n明细已经和发票归档，明天继续跟进。',
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
