import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/attachment_text_editor_card.dart';

void main() {
  testWidgets(
      'AttachmentTextEditorCard markdown display enables soft line breaks and normalizes escaped newlines',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AttachmentTextEditorCard(
            fieldKeyPrefix: 'attachment_text_full',
            text: r'# Title\nLine 2',
            emptyText: 'None',
            markdown: true,
            showLabel: false,
          ),
        ),
      ),
    );

    final markdown = tester.widget<MarkdownBody>(
      find.byKey(const ValueKey('attachment_text_full_markdown_display')),
    );

    expect(markdown.softLineBreak, isTrue);
    expect(markdown.data, '# Title\nLine 2');
  });

  testWidgets(
      'AttachmentTextEditorCard markdown display uses high contrast quote/code styling in dark mode',
      (tester) async {
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: const Scaffold(
          body: AttachmentTextEditorCard(
            fieldKeyPrefix: 'attachment_text_full',
            text: '> quote\n\n`inline`\n\n```dart\nprint("ok");\n```',
            emptyText: 'None',
            markdown: true,
            showLabel: false,
          ),
        ),
      ),
    );

    final markdown = tester.widget<MarkdownBody>(
      find.byKey(const ValueKey('attachment_text_full_markdown_display')),
    );
    final styleSheet = markdown.styleSheet;
    expect(styleSheet, isNotNull);

    final blockquoteDecoration =
        styleSheet!.blockquoteDecoration as BoxDecoration?;
    expect(blockquoteDecoration, isNotNull);
    expect(blockquoteDecoration!.color, isNotNull);

    final blockquoteText = styleSheet.blockquote;
    expect(blockquoteText, isNotNull);
    expect(blockquoteText!.color, isNotNull);
    final quoteContrast = (blockquoteText.color!.computeLuminance() -
            blockquoteDecoration.color!.computeLuminance())
        .abs();
    expect(quoteContrast, greaterThan(0.25));

    final inlineCode = styleSheet.code;
    expect(inlineCode, isNotNull);
    expect(inlineCode!.backgroundColor, isNotNull);
    expect(inlineCode.color, isNotNull);
    final inlineContrast = (inlineCode.color!.computeLuminance() -
            inlineCode.backgroundColor!.computeLuminance())
        .abs();
    expect(inlineContrast, greaterThan(0.25));

    final codeblockDecoration =
        styleSheet.codeblockDecoration as BoxDecoration?;
    expect(codeblockDecoration, isNotNull);
    expect(codeblockDecoration!.color, isNotNull);
    expect(codeblockDecoration.color,
        isNot(equals(darkTheme.colorScheme.surface)));
  });
}
