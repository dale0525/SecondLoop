import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_editor_page.dart';

import 'test_i18n.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    required Size size,
    String? initialText,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final text = initialText ??
        List<String>.filled(
          10,
          'SCROLLBAR_REGRESSION line for markdown preview',
        ).join('\n');

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: ChatMarkdownEditorPage(
            initialText: text,
            allowPlainMode: true,
            initialMode: ChatEditorMode.markdown,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets(
    'Landscape window uses side-by-side layout when width is greater than height',
    (tester) async {
      await pumpEditor(tester, size: const Size(850, 700));

      expect(find.byKey(const ValueKey('chat_markdown_editor_layout_wide')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('chat_markdown_editor_layout_compact')),
          findsNothing);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Portrait window uses compact mode and can switch to preview pane',
    (tester) async {
      await pumpEditor(tester, size: const Size(780, 900));

      expect(find.byKey(const ValueKey('chat_markdown_editor_layout_wide')),
          findsNothing);
      expect(find.byKey(const ValueKey('chat_markdown_editor_layout_compact')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('chat_markdown_editor_preview')),
          findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('chat_markdown_editor_compact_show_preview')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat_markdown_editor_preview')),
          findsOneWidget);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Markdown editor opens without scrollbar position errors',
    (tester) async {
      await pumpEditor(tester, size: const Size(780, 900));

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
