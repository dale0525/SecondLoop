import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_editor_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
    'Markdown editor opens without scrollbar position errors',
    (tester) async {
      tester.view
        ..physicalSize = const Size(780, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialText = List<String>.filled(
        10,
        'SCROLLBAR_REGRESSION line for markdown preview',
      ).join('\n');

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: ChatMarkdownEditorPage(
              initialText: initialText,
              allowPlainMode: true,
              initialMode: ChatEditorMode.markdown,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final horizontalScrollables = find.byWidgetPredicate((widget) {
        if (widget is! Scrollable) return false;
        return widget.axisDirection == AxisDirection.left ||
            widget.axisDirection == AxisDirection.right;
      });

      expect(find.byKey(const ValueKey('chat_markdown_editor_page')),
          findsOneWidget);
      expect(find.byTooltip('Simple input'), findsOneWidget);
      expect(horizontalScrollables, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );
}
