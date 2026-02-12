import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/semantic_parse.dart';

import 'package:secondloop/features/actions/todo/message_action_resolver.dart';

void main() {
  test('parses followup decision JSON', () {
    final now = DateTime(2026, 2, 3, 12, 0);
    final parsed = AiSemanticParse.tryParseMessageAction(
      '{"kind":"followup","confidence":0.92,"todo_id":"todo:1","new_status":"done"}',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(parsed, isNotNull);
    expect(parsed!.confidence, closeTo(0.92, 1e-9));
    expect(parsed.decision, isA<MessageActionFollowUpDecision>());
    final follow = parsed.decision as MessageActionFollowUpDecision;
    expect(follow.todoId, 'todo:1');
    expect(follow.newStatus, 'done');
  });

  test('parses create decision JSON (with due)', () {
    final now = DateTime(2026, 2, 3, 12, 0);
    final parsed = AiSemanticParse.tryParseMessageAction(
      '{"kind":"create","confidence":0.88,"title":"提交材料","status":"open","due_local_iso":"2026-02-04T15:00:00"}',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(parsed, isNotNull);
    expect(parsed!.confidence, closeTo(0.88, 1e-9));
    expect(parsed.decision, isA<MessageActionCreateDecision>());
    final create = parsed.decision as MessageActionCreateDecision;
    expect(create.title, '提交材料');
    expect(create.status, 'open');
    expect(create.dueAtLocal, DateTime(2026, 2, 4, 15, 0));
  });

  test('parses create recurrence decision JSON', () {
    final now = DateTime(2026, 2, 3, 12, 0);
    final parsed = AiSemanticParse.tryParseMessageAction(
      '{"kind":"create","confidence":0.93,"title":"提交周报","status":"open","due_local_iso":"2026-02-04T09:00:00","recurrence":{"freq":"weekly","interval":1}}',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(parsed, isNotNull);
    final create = parsed!.decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.recurrenceRule!.freq, 'weekly');
    expect(create.recurrenceRule!.interval, 1);
  });

  test('fills fallback due and open status for recurrence without due', () {
    final now = DateTime(2026, 2, 3, 22, 0);
    final parsed = AiSemanticParse.tryParseMessageAction(
      '{"kind":"create","confidence":0.93,"title":"提交周报","status":"inbox","due_local_iso":null,"recurrence":{"freq":"weekly","interval":1}}',
      nowLocal: now,
      locale: const Locale('zh', 'CN'),
      dayEndMinutes: 21 * 60,
    );

    expect(parsed, isNotNull);
    final create = parsed!.decision as MessageActionCreateDecision;
    expect(create.recurrenceRule, isNotNull);
    expect(create.status, 'open');
    expect(create.dueAtLocal, DateTime(2026, 2, 4, 21, 0));
  });
  test('parses JSON wrapped in markdown code fences', () {
    final now = DateTime(2026, 2, 3, 12, 0);
    final parsed = AiSemanticParse.tryParseMessageAction(
      'Sure!\\n```json\\n{"kind":"followup","confidence":0.9,"todo_id":"t","new_status":"in_progress"}\\n```\\n',
      nowLocal: now,
      locale: const Locale('en'),
      dayEndMinutes: 21 * 60,
    );

    expect(parsed, isNotNull);
    expect(parsed!.decision, isA<MessageActionFollowUpDecision>());
  });

  test('parses ask-ai time window JSON', () {
    final now = DateTime(2026, 2, 4, 12, 0);
    final parsed = AiSemanticParse.tryParseAskAiTimeWindow(
      '{"kind":"past","confidence":0.9,"start_local_iso":"2026-01-26T00:00:00","end_local_iso":"2026-02-02T00:00:00"}',
      nowLocal: now,
      locale: const Locale('en'),
      firstDayOfWeekIndex: 1,
    );

    expect(parsed, isNotNull);
    expect(parsed!.confidence, closeTo(0.9, 1e-9));
    expect(parsed.kind, 'past');
    expect(parsed.startLocal, DateTime(2026, 1, 26));
    expect(parsed.endLocal, DateTime(2026, 2, 2));
  });
}
