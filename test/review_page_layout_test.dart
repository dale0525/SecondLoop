import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/review/review_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('ReviewPage shows approval queue and selected task detail',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: ReviewPage()),
      ),
    );

    expect(find.text('Needs your OK queue'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Task change detail'), findsOneWidget);
    expect(find.byKey(const ValueKey('review_diff_due_time')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_diff_status')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_diff_notes')), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('ReviewPage mobile opens selected review detail as bottom sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(home: ReviewPage()),
      ),
    );

    expect(find.text('Needs your OK queue'), findsOneWidget);
    expect(find.text('Task change detail'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('review_queue_item_task_due')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('review_detail_sheet')), findsOneWidget);
    expect(find.text('Task change detail'), findsOneWidget);
    expect(find.byKey(const ValueKey('review_diff_due_time')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_diff_status')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_diff_notes')), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });
}
