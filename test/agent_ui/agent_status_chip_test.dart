import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/agent_ui/agent_status_chip.dart';

void main() {
  testWidgets('AgentStatusChip exposes stable status keys', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              AgentStatusChip.pending(label: 'Pending'),
              AgentStatusChip.high(label: 'High'),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent_status_chip_pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent_status_chip_high')),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
  });
}
