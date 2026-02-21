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

  testWidgets('Latex block remains stable under large text scale',
      (tester) async {
    final previewTheme =
        resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, ThemeData());

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ChatMarkdownLatexBlock(
                  expression:
                      r'\begin{aligned}\frac{a_1x+b_1}{c_1x+d_1} + \frac{a_2x+b_2}{c_2x+d_2} + \frac{a_3x+b_3}{c_3x+d_3}\\\sum_{i=1}^{n}\frac{p_i}{q_i+r_i}\end{aligned}',
                  previewTheme: previewTheme,
                  exportRenderMode: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
  testWidgets('Latex inline remains stable under large text scale',
      (tester) async {
    final previewTheme =
        resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, ThemeData());

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: ChatMarkdownLatexInline(
                  expression: r'\frac{a_1x+b_1}{c_1x+d_1}',
                  previewTheme: previewTheme,
                  exportRenderMode: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
