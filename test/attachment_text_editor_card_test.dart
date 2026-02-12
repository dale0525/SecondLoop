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
}
