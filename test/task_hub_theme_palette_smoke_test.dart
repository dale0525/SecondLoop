import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/theme.dart';
import 'package:secondloop/app/theme_palette_prefs.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_banner.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page_sections.dart';
import 'package:secondloop/features/actions/task_hub/task_priority_engine.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  Todo todo({
    required String id,
    required String title,
    required int updatedAtMs,
    int? dueAtMs,
    String status = 'open',
  }) {
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: null,
      createdAtMs: updatedAtMs,
      updatedAtMs: updatedAtMs,
      reviewStage: null,
      nextReviewAtMs: null,
      lastReviewAtMs: null,
    );
  }

  Text textWidget(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label).first);
  }

  testWidgets('task hub semantic colors follow active theme palettes',
      (tester) async {
    final now = DateTime(2026, 3, 13, 10, 0);
    final snapshot = buildTaskPrioritySnapshot(
      <Todo>[
        todo(
          id: 'focus',
          title: 'Prepare launch brief',
          updatedAtMs: 10,
          dueAtMs:
              now.add(const Duration(hours: 2)).toUtc().millisecondsSinceEpoch,
        ),
        todo(
          id: 'scheduled',
          title: 'Plan next review',
          updatedAtMs: 15,
          dueAtMs:
              now.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch,
        ),
        todo(id: 'backlog', title: 'Review notes', updatedAtMs: 20),
        todo(id: 'done', title: 'Ship update', updatedAtMs: 30, status: 'done'),
      ],
      nowLocal: now,
    );

    for (final palette in <AppThemePalette>[
      AppThemePalette.ocean,
      AppThemePalette.monochrome,
    ]) {
      final theme = AppTheme.light(palette: palette);

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            theme: theme,
            locale: const Locale('en'),
            home: Scaffold(
              body: ListView(
                children: [
                  TaskHubBanner(snapshot: snapshot, compact: true),
                  TaskHubPageSection(
                    title: 'Focus Tone',
                    sectionKey: const ValueKey('theme_palette_section_focus'),
                    entries: snapshot.focus,
                    checklistProgressByTodoId: const <String,
                        TodoChecklistProgress>{},
                    sectionKind: TaskHubPageSectionKind.focus,
                    onOpenTodo: (_) async {},
                    onQuickAction: (_, __) async {},
                  ),
                  TaskHubPageSection(
                    title: 'Next Tone',
                    sectionKey: const ValueKey('theme_palette_section_next_up'),
                    entries: snapshot.scheduled,
                    checklistProgressByTodoId: const <String,
                        TodoChecklistProgress>{},
                    sectionKind: TaskHubPageSectionKind.scheduled,
                    onOpenTodo: (_) async {},
                    onQuickAction: (_, __) async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        textWidget(tester, 'Focus Tone').style?.color,
        theme.colorScheme.primary,
      );
      expect(
        textWidget(tester, 'Next Tone').style?.color,
        theme.colorScheme.secondary,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
