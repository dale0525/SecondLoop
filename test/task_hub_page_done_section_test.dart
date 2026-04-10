import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/src/rust/db.dart';

import 'task_hub_page_test_helpers.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 50),
  int maxPumps = 120,
}) =>
    pumpUntilFound(
      tester,
      finder,
      step: step,
      maxPumps: maxPumps,
    );

Future<void> _pumpUntilTaskHubReady(WidgetTester tester) =>
    pumpUntilTaskHubReady(tester);

Widget _wrap(AppBackend backend) => wrapTaskHubTestApp(backend);

typedef _TaskHubBackend = TaskHubTestBackend;

void main() {
  setUp(() {
    clearTaskHubSharedAiCacheForTest();
  });

  testWidgets('task hub collapses done section by default', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'done',
          title: 'Shipped',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 40,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('task_hub_page_section_done')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('task_hub_page_section_done_toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('task_hub_page_item_done')), findsNothing);
  });

  testWidgets('task hub expands done section on demand', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'done',
          title: 'Shipped',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 40,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_section_done_toggle')),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('task_hub_page_item_done')), findsOneWidget);
  });

  testWidgets('done more menu keeps delete separated and last', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'done',
          title: 'Shipped',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 40,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_section_done_toggle')),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_more')));
    await _pumpUntilFound(tester, find.text('Delete'));

    expect(find.text('Do again'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);

    final redoTopLeft = tester.getTopLeft(find.text('Do again'));
    final deleteTopLeft = tester.getTopLeft(find.text('Delete'));
    expect(redoTopLeft.dy, lessThan(deleteTopLeft.dy));
  });

  testWidgets('done more menu marks redo as secondary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'done',
          title: 'Shipped',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 40,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_section_done_toggle')),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_more')));
    await _pumpUntilFound(tester, find.text('Do again'));

    final redoContext = tester.element(find.text('Do again'));
    final expectedColor = Theme.of(redoContext).colorScheme.onSurfaceVariant;
    final redoText = tester.widget<Text>(find.text('Do again'));
    final redoIcon = tester.widget<Icon>(find.byIcon(Icons.replay_rounded));

    expect(redoText.style?.color, expectedColor);
    expect(redoIcon.color, expectedColor);
  });

  testWidgets('done more menu marks delete as destructive', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: const <Todo>[
        Todo(
          id: 'focus',
          title: 'Fix prod issue',
          dueAtMs: null,
          status: 'in_progress',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 10,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
        Todo(
          id: 'done',
          title: 'Shipped',
          dueAtMs: null,
          status: 'done',
          sourceEntryId: null,
          createdAtMs: 0,
          updatedAtMs: 40,
          reviewStage: null,
          nextReviewAtMs: null,
          lastReviewAtMs: null,
        ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await _pumpUntilTaskHubReady(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_section_done_toggle')),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_quick_done_more')));
    await tester.pumpAndSettle();

    final deleteContext = tester.element(find.text('Delete'));
    final expectedColor = Theme.of(deleteContext).colorScheme.error;
    final deleteText = tester.widget<Text>(find.text('Delete'));
    final deleteIcon =
        tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded));

    expect(deleteText.style?.color, expectedColor);
    expect(deleteIcon.color, expectedColor);
  });

  testWidgets('task hub loads done todos in batches on demand', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _TaskHubBackend(
      todos: <Todo>[
        for (var i = 0; i < 25; i++)
          Todo(
            id: 'done-$i',
            title: 'Done $i',
            dueAtMs: null,
            status: 'done',
            sourceEntryId: null,
            createdAtMs: i,
            updatedAtMs: i,
            reviewStage: null,
            nextReviewAtMs: null,
            lastReviewAtMs: null,
          ),
      ],
    );

    await tester.pumpWidget(_wrap(backend));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
      findsNothing,
    );
    expect(
        find.byKey(const ValueKey('task_hub_page_item_done-0')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_section_done')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('task_hub_page_section_done_toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('task_hub_page_done_load_more')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('task_hub_page_done_load_more')));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('task_hub_page_item_done-0')),
    );

    expect(find.byKey(const ValueKey('task_hub_page_item_done-0')),
        findsOneWidget);
  });
}
