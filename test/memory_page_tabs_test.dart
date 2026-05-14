import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/memory/memory_models.dart';
import 'package:secondloop/features/memory/memory_page.dart';

import 'test_i18n.dart';

void main() {
  Future<void> pumpMemoryPage(
    WidgetTester tester, {
    MemoryDemoData? data,
  }) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(home: MemoryPage(data: data)),
      ),
    );
  }

  testWidgets('default MemoryPage does not show demo memories', (tester) async {
    await pumpMemoryPage(tester);

    expect(find.text('No knowledge pages yet.'), findsOneWidget);
    expect(find.text('Morning meeting guardrail'), findsNothing);
    expect(find.text('Alex Chen'), findsNothing);
    expect(find.text('Project Atlas'), findsNothing);
    expect(find.text('passport-scan.pdf'), findsNothing);
  });

  testWidgets('Preferences tab shows preferences and one candidate only',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    expect(find.byKey(const ValueKey('memory_side_tab_list')), findsNothing);
    expect(find.text('Morning meeting guardrail'), findsOneWidget);
    expect(find.text('Candidate memory'), findsOneWidget);
    expect(find.text('Alex Chen'), findsNothing);
    expect(find.text('Project Atlas'), findsNothing);
  });

  testWidgets('People tab shows person list and selected person detail',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('memory_side_tab_list')), findsNothing);
    expect(find.text('Alex Chen'), findsOneWidget);
    expect(find.text('Selected person detail'), findsOneWidget);
    expect(find.text('Morning meeting guardrail'), findsNothing);
    expect(find.text('Project Atlas'), findsNothing);
  });

  testWidgets('Projects tab shows project list and selected project detail',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    expect(find.text('Project Atlas'), findsOneWidget);
    expect(find.text('Selected project detail'), findsOneWidget);
    expect(find.text('Alex Chen'), findsNothing);
    expect(find.text('Source snippets'), findsNothing);
  });

  testWidgets('Sources tab shows source list and snippets only',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();

    expect(find.text('passport-scan.pdf'), findsOneWidget);
    expect(find.text('Source snippets'), findsOneWidget);
    expect(find.text('Project Atlas'), findsNothing);
    expect(find.text('Grouped candidates'), findsNothing);
  });

  testWidgets('Suggestions tab shows grouped candidates and actions',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('Suggestions'));
    await tester.pumpAndSettle();

    expect(find.text('Grouped candidates'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    expect(find.text('passport-scan.pdf'), findsNothing);
  });
}
