import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_editor_page.dart';
import 'package:secondloop/features/chat/chat_markdown_rich_rendering.dart';

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
      expect(
        find.byKey(const ValueKey('chat_markdown_editor_quick_actions')),
        findsOneWidget,
      );
      expect(horizontalScrollables, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Markdown editor exposes quick formatting toolbar and theme selector',
    (tester) async {
      await pumpEditor(tester, size: const Size(1024, 700));

      expect(
        find.byKey(const ValueKey('chat_markdown_editor_quick_actions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_markdown_editor_theme_selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat_markdown_editor_action_bold')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('chat_markdown_editor_export_menu')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Export as PNG'), findsOneWidget);
      expect(find.text('Export as PDF'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Bold action reflects active selection state and toggles markdown off',
    (tester) async {
      await pumpEditor(tester, size: const Size(1024, 700));

      const editorInputKey = ValueKey('chat_markdown_editor_input');
      final inputFinder = find.byKey(editorInputKey);
      final input = tester.widget<TextField>(inputFinder);
      input.controller!.value = const TextEditingValue(
        text: 'hello **world**',
        selection: TextSelection(baseOffset: 8, extentOffset: 13),
      );
      await tester.pumpAndSettle();

      final boldFinder =
          find.byKey(const ValueKey('chat_markdown_editor_action_bold'));
      expect(tester.widget(boldFinder), isA<FilledButton>());

      await tester.tap(boldFinder);
      await tester.pumpAndSettle();

      expect(input.controller!.text, 'hello world');
      expect(tester.widget(boldFinder), isA<OutlinedButton>());
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Bold and italic actions are both active for triple wrapped selection',
    (tester) async {
      await pumpEditor(tester, size: const Size(1024, 700));

      const editorInputKey = ValueKey('chat_markdown_editor_input');
      final inputFinder = find.byKey(editorInputKey);
      final input = tester.widget<TextField>(inputFinder);
      input.controller!.value = const TextEditingValue(
        text: 'hello ***world***',
        selection: TextSelection(baseOffset: 9, extentOffset: 14),
      );
      await tester.pumpAndSettle();

      final boldFinder =
          find.byKey(const ValueKey('chat_markdown_editor_action_bold'));
      final italicFinder =
          find.byKey(const ValueKey('chat_markdown_editor_action_italic'));

      expect(tester.widget(boldFinder), isA<FilledButton>());
      expect(tester.widget(italicFinder), isA<FilledButton>());

      await tester.tap(italicFinder);
      await tester.pumpAndSettle();

      expect(input.controller!.text, 'hello **world**');
      expect(tester.widget(boldFinder), isA<FilledButton>());
      expect(tester.widget(italicFinder), isA<OutlinedButton>());
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Tab and shift-tab adjust list indentation instead of changing focus',
    (tester) async {
      await pumpEditor(tester, size: const Size(1024, 700));

      const editorInputKey = ValueKey('chat_markdown_editor_input');
      final inputFinder = find.byKey(editorInputKey);
      final input = tester.widget<TextField>(inputFinder);
      input.controller!.value = const TextEditingValue(
        text: '- item',
        selection: TextSelection.collapsed(offset: 6),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(input.controller!.text, '  - item');
      expect(input.controller!.selection,
          const TextSelection.collapsed(offset: 8));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(input.controller!.text, '- item');
      expect(input.controller!.selection,
          const TextSelection.collapsed(offset: 6));
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Mobile app bar keeps markdown title fully visible',
    (tester) async {
      await pumpEditor(tester, size: const Size(430, 932));

      final titleFinder = find.text('Markdown editor');
      expect(titleFinder, findsOneWidget);

      final titleRenderParagraph =
          tester.renderObject<RenderParagraph>(titleFinder);

      expect(titleRenderParagraph.size.width, greaterThan(120));
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.android},
    ),
  );

  testWidgets(
    'Preview renders LaTeX formulas with dedicated widgets',
    (tester) async {
      await pumpEditor(
        tester,
        size: const Size(1024, 700),
        initialText: r'''Euler identity: $e^{i\pi}+1=0$

$$\int_0^1 x^2 \mathrm{d}x$$''',
      );

      expect(
        find.byType(ChatMarkdownLatexInline),
        findsOneWidget,
      );
      expect(
        find.byType(ChatMarkdownLatexBlock),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Preview renders markmap fenced blocks as diagrams',
    (tester) async {
      await pumpEditor(
        tester,
        size: const Size(1024, 700),
        initialText:
            '```markmap\n# Product\n## Mobile\n### Chat\n## Desktop\n```',
      );

      expect(
        find.byType(ChatMarkdownMarkmap),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Preview renders multiline LaTeX matrix blocks with inline delimiters',
    (tester) async {
      await pumpEditor(
        tester,
        size: const Size(1024, 700),
        initialText: r'''$$\mathbf{T}(t)=\begin{bmatrix}

1 & 0 & 0 & t_x\\

0 & 1 & 0 & t_y\\

0 & 0 & 1 & t_z\\

0 & 0 & 0 & 1

\end{bmatrix}$$''',
      );

      expect(
        find.byType(ChatMarkdownLatexBlock),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );

  testWidgets(
    'Preview accepts Hexo note tags without custom rendering',
    (tester) async {
      await pumpEditor(
        tester,
        size: const Size(1024, 700),
        initialText: r'''{% note default %}
这是说明块
{% endnote %}''',
      );

      expect(
        find.byKey(const ValueKey('chat_markdown_editor_preview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant(
      <TargetPlatform>{TargetPlatform.macOS},
    ),
  );
}
