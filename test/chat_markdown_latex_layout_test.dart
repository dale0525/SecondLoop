import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_rich_rendering.dart';
import 'package:secondloop/features/chat/chat_markdown_theme_presets.dart';

void main() {
  testWidgets('Latex block uses finite width constraints in horizontal scroll',
      (tester) async {
    final previewTheme =
        resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, ThemeData());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ChatMarkdownLatexBlock(
                expression:
                    r'\begin{aligned}a_1x_1 + a_2x_2 + a_3x_3 + a_4x_4\\b_1x_1 + b_2x_2 + b_3x_3 + b_4x_4\end{aligned}',
                previewTheme: previewTheme,
                exportRenderMode: false,
              ),
            ),
          ),
        ),
      ),
    );

    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(ChatMarkdownLatexBlock),
        matching: find.byType(SingleChildScrollView),
      ),
    );

    expect(scroll.child, isA<ConstrainedBox>());
    final constrained = scroll.child! as ConstrainedBox;
    expect(constrained.constraints.maxWidth.isFinite, isTrue);
  });
}
