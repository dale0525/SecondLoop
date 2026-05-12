import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/agent_ui/agent_tab_bar.dart';

void main() {
  testWidgets('AgentTabBar exposes selected tab keys and selection callbacks',
      (tester) async {
    var selectedId = 'preferences';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AgentTabBar(
                tabs: const [
                  AgentTabItem(id: 'preferences', label: 'Preferences'),
                  AgentTabItem(id: 'activity', label: 'Activity'),
                ],
                selectedId: selectedId,
                onSelected: (id) => setState(() => selectedId = id),
              );
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent_tab_preferences_selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent_tab_activity_selected')),
      findsNothing,
    );

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(selectedId, 'activity');
    expect(
      find.byKey(const ValueKey('agent_tab_activity_selected')),
      findsOneWidget,
    );
  });
}
