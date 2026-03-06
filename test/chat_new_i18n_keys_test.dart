import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('exposes chat i18n keys for tags and ask-scope-empty',
      (tester) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    Text(context.t.chat.tagFilter.tooltip),
                    Text(context.t.chat.tagFilter.clearFilter),
                    Text(context.t.chat.tagFilter.sheet.title),
                    Text(context.t.chat.tagPicker.title),
                    Text(context.t.chat.tagPicker.tagActionLabel),
                    Text(context.t.chat.tagPicker.mergeSuggestions),
                    Text(context.t.chat.tagPicker.mergeAction),
                    Text(context.t.chat.tagPicker.manualMergeAction),
                    Text(context.t.chat.tagPicker.hiddenMergeSuggestions),
                    Text(context.t.chat.tagPicker.hiddenMergeRestoreAction),
                    Text(
                      context.t.chat.tagPicker
                          .mergeSuggestionMessages(count: 3),
                    ),
                    Text(context.t.chat.askScopeEmpty.title),
                    Text(context.t.chat.askScopeEmpty.actions.expandTimeWindow),
                    Text(context.t.chat.recordingRecoveryDialog.title),
                    Text(
                      context.t.chat.recordingRecoveryDialog
                          .description(segmentCount: 3),
                    ),
                    Text(
                      context.t.chat.recordingRecoveryDialog.actions.discard,
                    ),
                    Text(
                      context.t.chat.recordingRecoveryDialog.actions
                          .recoverAndSend,
                    ),
                    Text(context.t.chat.recordingRecoveryRecoveredAndSent),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Tag filter'), findsOneWidget);
    expect(find.text('Clear tag filter'), findsOneWidget);
    expect(find.text('Filter by tags'), findsOneWidget);
    expect(find.text('Manage tags'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Merge suggestions'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    expect(find.text('Manual merge'), findsOneWidget);
    expect(find.text('Ignored merge suggestions'), findsOneWidget);
    expect(find.text('Show again'), findsOneWidget);
    expect(find.text('Affects 3 tagged messages'), findsOneWidget);
    expect(find.text('No results in current scope'), findsOneWidget);
    expect(find.text('Expand time window'), findsOneWidget);
    expect(find.text('Interrupted recording detected'), findsOneWidget);
    expect(
      find.text(
        'An interrupted recording was found (3 segments). You can recover and send it, or discard it.',
      ),
      findsOneWidget,
    );
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Recover & Send'), findsOneWidget);
    expect(
        find.text('Recovered and sent interrupted recording.'), findsOneWidget);
  });
}
