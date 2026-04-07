import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/task_hub/task_hub_card_anchor.dart';

void main() {
  testWidgets('anchor does not schedule a duplicate measurement on rebuild',
      (tester) async {
    final registry = _CountingTaskHubCardAnchorRegistry();
    final rebuildTick = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: rebuildTick,
          builder: (context, _, __) {
            return Center(
              child: TaskHubCardAnchor(
                todoId: 'todo-1',
                registry: registry,
                child: const SizedBox(width: 120, height: 48),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(registry.updateCount, 1);

    rebuildTick.value += 1;
    await tester.pump();
    await tester.pump();

    expect(registry.updateCount, 1);
  });

  testWidgets('measurement returns null after anchor is unmounted',
      (tester) async {
    final registry = _CapturingTaskHubCardAnchorRegistry();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TaskHubCardAnchor(
            todoId: 'todo-1',
            registry: registry,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      ),
    );
    await tester.pump();

    final measure = registry.lastMeasurement;
    expect(measure, isNotNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(measure!.call, returnsNormally);
    expect(measure(), isNull);
  });
}

class _CountingTaskHubCardAnchorRegistry extends TaskHubCardAnchorRegistry {
  int updateCount = 0;

  @override
  void update(String todoId, Rect rect) {
    updateCount += 1;
    super.update(todoId, rect);
  }
}

class _CapturingTaskHubCardAnchorRegistry extends TaskHubCardAnchorRegistry {
  TaskHubCardAnchorMeasurement? lastMeasurement;

  @override
  void attach(String todoId, TaskHubCardAnchorMeasurement measure) {
    lastMeasurement = measure;
    super.attach(todoId, measure);
  }
}
