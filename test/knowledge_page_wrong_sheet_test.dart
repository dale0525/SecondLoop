import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/knowledge_center/knowledge_page_wrong_sheet.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('KnowledgePageWrongSheet returns the selected reason',
      (tester) async {
    KnowledgeWrongReason? selectedReason;

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    selectedReason = await showKnowledgePageWrongSheet(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This page is incomplete'));
    await tester.pumpAndSettle();

    expect(selectedReason, KnowledgeWrongReason.incomplete);
  });
}
