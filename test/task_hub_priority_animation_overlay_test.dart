import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_controller.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_priority_animation_overlay.dart';

void main() {
  testWidgets('overlay restarts from new begin rect when token changes',
      (tester) async {
    Widget buildSubject(TaskHubPriorityOverlayState animation) {
      return MaterialApp(
        home: Scaffold(
          body: TaskHubPriorityAnimationOverlay(
            animation: animation,
            onCompleted: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(
      buildSubject(
        const TaskHubPriorityOverlayState(
          todoId: 'a',
          title: 'Task A',
          token: 1,
          beginRect: Rect.fromLTWH(12, 24, 120, 48),
          endRect: Rect.fromLTWH(12, 260, 120, 48),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    await tester.pumpWidget(
      buildSubject(
        const TaskHubPriorityOverlayState(
          todoId: 'a',
          title: 'Task A',
          token: 2,
          beginRect: Rect.fromLTWH(210, 44, 120, 48),
          endRect: Rect.fromLTWH(210, 280, 120, 48),
        ),
      ),
    );
    await tester.pump();

    final overlayRect = tester.getRect(
      find.byKey(const ValueKey('task_hub_priority_animation_overlay')),
    );
    expect(overlayRect.left, closeTo(210, 8));
    expect(overlayRect.top, closeTo(44, 8));
  });
}
