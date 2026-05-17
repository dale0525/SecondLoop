import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/agent_ui/agent_task_summary.dart';
import 'package:secondloop/core/models/app_models.dart';
import 'package:secondloop/core/models/platform_int.dart';

void main() {
  testWidgets('task detail sheet records task focus without blocking open',
      (tester) async {
    final viewed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showAgentTaskDetailSheet(
                  context: context,
                  todo: _todo(id: 'task-1', title: '完成周报'),
                  onTaskViewed: (todo) async {
                    viewed.add(todo.id);
                  },
                );
              },
              child: const Text('Open task'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open task'));
    await tester.pumpAndSettle();

    expect(viewed, ['task-1']);
    expect(
        find.byKey(const ValueKey('agent_task_detail_sheet')), findsOneWidget);
  });
}

Todo _todo({
  required String id,
  required String title,
}) {
  return Todo(
    id: id,
    title: title,
    dueAtMs: null,
    status: 'open',
    sourceEntryId: null,
    createdAtMs: platformIntFromInt(1000),
    updatedAtMs: platformIntFromInt(1000),
    reviewStage: null,
    nextReviewAtMs: null,
    lastReviewAtMs: null,
    manualImportanceNudgeScore: platformIntFromInt(0),
    manualUrgencyNudgeScore: platformIntFromInt(0),
  );
}
