import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/src/rust/db.dart';

import 'task_hub_page_test_helpers.dart';

void main() {
  testWidgets('task hub renders remaining unfinished tasks in one list',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 4, 13, 10, 0);
    final backend = TaskHubTestBackend(
      todos: <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs:
              now.add(const Duration(hours: 1)).toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'scheduled',
          title: 'Draft roadmap',
          dueAtMs:
              now.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 20,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        const Todo(
          id: 'open',
          title: 'Plan later',
          dueAtMs: null,
          status: 'open',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 30,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(wrapTaskHubTestApp(backend));
    await pumpUntilTaskHubReady(tester);

    expect(find.byKey(const ValueKey('task_hub_page_section_focus')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_open')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('task_hub_page_section_upcoming')),
        findsNothing);
    expect(find.byKey(const ValueKey('task_hub_page_section_backlog')),
        findsNothing);

    final openSection =
        find.byKey(const ValueKey('task_hub_page_section_open'));
    expect(
      find.descendant(
        of: openSection,
        matching: find.byKey(const ValueKey('task_hub_page_item_scheduled')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openSection,
        matching: find.byKey(const ValueKey('task_hub_page_item_open')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: openSection,
        matching: find.byKey(const ValueKey('task_hub_page_item_focus')),
      ),
      findsNothing,
    );
  });
}
