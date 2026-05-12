import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/conversation_cards/approval_preview_card.dart';
import 'package:secondloop/features/conversation_context/conversation_context_rail.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('desktop conversation context rail shows expected sections',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ConversationContextRail(
              snapshot: ConversationContextSnapshot.demo(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Today at a glance'), findsOneWidget);
    expect(find.text('Long-term memory'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Recent files'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('Privacy note'), findsOneWidget);
  });

  testWidgets('mobile context button opens the same context as a sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ConversationContextSheetButton(
                  snapshot: ConversationContextSnapshot.demo(),
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.text('Privacy note'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('conversation_context_open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('conversation_context_sheet')),
      findsOneWidget,
    );
    expect(find.text('Today at a glance'), findsOneWidget);
    expect(find.text('Long-term memory'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Recent files'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('Privacy note'), findsOneWidget);
  });

  testWidgets('approval preview card shows diff and approval actions',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: ApprovalPreviewCard(
              change: ApprovalPreviewChange.demo(),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        "Move the passport renewal task to today at 20:00, but don't mark it done.",
      ),
      findsOneWidget,
    );
    expect(find.text('Due time'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('Today 20:00'), findsOneWidget);
    expect(find.text('Status unchanged'), findsOneWidget);
    expect(find.text('Review & Approve'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });
}
