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
}
