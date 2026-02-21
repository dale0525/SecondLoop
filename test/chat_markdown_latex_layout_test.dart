import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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

  testWidgets('Latex inline uses finite width constraints in horizontal scroll',
      (tester) async {
    final previewTheme =
        resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, ThemeData());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: ChatMarkdownLatexInline(
                expression:
                    r'\frac{a_1}{b_1}+\frac{a_2}{b_2}+\frac{a_3}{b_3}+\frac{a_4}{b_4}',
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
        of: find.byType(ChatMarkdownLatexInline),
        matching: find.byType(SingleChildScrollView),
      ),
    );

    expect(scroll.child, isA<ConstrainedBox>());
    final constrained = scroll.child! as ConstrainedBox;
    expect(constrained.constraints.maxWidth.isFinite, isTrue);
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

  testWidgets(
    'Markdown preview renders projection-matrix latex without layout exceptions',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown = r'''完整的投影变换可以表示为：

$$\mathbf{P}_o=\mathbf{S}(\mathbf{s})\mathbf{T}(\mathbf{t})\\
=\begin{bmatrix}
\frac{2}{r-l} & 0 & 0 & 0\\
0 & \frac{2}{t-b} & 0 & 0\\
0 & 0 & \frac{2}{f-n} & 0\\
0 & 0 & 0 & 1
\end{bmatrix}\begin{bmatrix}
1 & 0 & 0 & -\frac{r+l}{2}\\
0 & 1 & 0 & -\frac{t+b}{2}\\
0 & 0 & 1 & -\frac{f+n}{2}\\
0 & 0 & 0 & 1
\end{bmatrix}\\
=\begin{bmatrix}
\frac{2}{r-l} & 0 & 0 & -\frac{r+l}{r-l}\\
0 & \frac{2}{t-b} & 0 & -\frac{t+b}{t-b}\\
0 & 0 & \frac{2}{f-n} & -\frac{f+n}{f-n}\\
0 & 0 & 0 & 1
\end{bmatrix}$$

其中，$\mathbf{s}=(2/(r-l),2/(t-b),2/(f-n)),\mathbf{t}=(-(r+l)/2,-(t+b)/2,-(f+n)/2)$。$\mathbf{P}_o$是可逆的，$\mathbf{P}_o^{-1}=\mathbf{T}(-t)\mathbf{S}((r-l)/2,(t-b)/2,(f-n)/2)$。''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: MarkdownBody(
                    data: markdown,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: previewTheme.buildStyleSheet(theme),
                    blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                    inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                    builders: buildChatMarkdownElementBuilders(
                      previewTheme: previewTheme,
                      exportRenderMode: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChatMarkdownLatexBlock), findsOneWidget);
      expect(find.byType(ChatMarkdownLatexInline), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown preview keeps long inline fractions stable in narrow layout',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown =
          r'Long inline formula: $\frac{a_1}{b_1}+\frac{a_2}{b_2}+\frac{a_3}{b_3}+\frac{a_4}{b_4}+\frac{a_5}{b_5}+\frac{a_6}{b_6}+\frac{a_7}{b_7}+\frac{a_8}{b_8}$ end.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: MarkdownBody(
                  data: markdown,
                  selectable: true,
                  softLineBreak: true,
                  styleSheet: previewTheme.buildStyleSheet(theme),
                  blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                  inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                  builders: buildChatMarkdownElementBuilders(
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

      expect(find.byType(ChatMarkdownLatexInline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown preview keeps inline fractions stable at large accessibility scale',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown =
          r'Accessibility formula: $\frac{a_1x+b_1}{c_1x+d_1}+\frac{a_2x+b_2}{c_2x+d_2}+\frac{a_3x+b_3}{c_3x+d_3}$ end.';

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: MarkdownBody(
                    data: markdown,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: previewTheme.buildStyleSheet(theme),
                    blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                    inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                    builders: buildChatMarkdownElementBuilders(
                      previewTheme: previewTheme,
                      exportRenderMode: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChatMarkdownLatexInline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Export-mode markdown keeps inline fractions stable',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown =
          r'Export formula: $\frac{a_1x+b_1}{c_1x+d_1}+\frac{a_2x+b_2}{c_2x+d_2}+\frac{a_3x+b_3}{c_3x+d_3}$ end.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MarkdownBody(
                  data: markdown,
                  selectable: false,
                  softLineBreak: true,
                  styleSheet: previewTheme.buildExportStyleSheet(theme),
                  blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                  inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                  builders: buildChatMarkdownElementBuilders(
                    previewTheme: previewTheme,
                    exportRenderMode: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChatMarkdownLatexInline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown preview renders long rotation-matrix latex block',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown = r'''有：

$$\mathbf{u}=\begin{bmatrix}
r\cos(\theta + \phi )\\ 
r\sin(\theta + \phi )
\end{bmatrix}=\begin{bmatrix}
r(\cos\theta \cos\phi -\sin\theta \sin\phi)\\ 
r(\sin\theta \cos\phi -\cos\theta \sin\phi)
\end{bmatrix}\\
=\underbrace{\begin{bmatrix}
\cos\phi& -\sin\phi\\ 
\sin\phi & \cos\phi
\end{bmatrix}}_{\mathbf{R}(\phi)}\underbrace{\begin{bmatrix}
r\cos\theta\\ 
r\sin\theta
\end{bmatrix}}_{\mathbf{v}}=\mathbf{R}(\phi)\mathbf{v}$$''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: MarkdownBody(
                    data: markdown,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: previewTheme.buildStyleSheet(theme),
                    blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                    inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                    builders: buildChatMarkdownElementBuilders(
                      previewTheme: previewTheme,
                      exportRenderMode: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChatMarkdownLatexBlock), findsOneWidget);
      expect(find.textContaining('\\underbrace'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown preview renders tiny rotation matrix block',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown = r'''$$\tiny{
\mathbf{R}=\\
\begin{bmatrix}
\cos \phi+(1-\cos \phi)r_x^2 & (1-\cos \phi)r_xr_y-r_z\sin \phi & (1-\cos \phi)r_xr_z+r_y\sin \phi\\
(1-\cos \phi)r_xr_y+r_z\sin \phi & \cos \phi+(1-\cos \phi)r_y^2 & (1-\cos \phi)r_yr_z-r_x\sin \phi\\
(1-\cos \phi)r_xr_z-r_y\sin \phi & (1-\cos \phi)r_yr_z+r_x\sin \phi & \cos \phi+(1-\cos \phi)r_z^2
\end{bmatrix}
}$$''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: MarkdownBody(
                    data: markdown,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: previewTheme.buildStyleSheet(theme),
                    blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                    inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                    builders: buildChatMarkdownElementBuilders(
                      previewTheme: previewTheme,
                      exportRenderMode: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(ChatMarkdownLatexBlock), findsOneWidget);
      expect(find.textContaining('\\tiny{'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown preview keeps inline matrix determinants stable',
    (tester) async {
      final theme = ThemeData(
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14)),
      );
      final previewTheme =
          resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

      const markdown =
          r'则$x=\frac{det(\begin{bmatrix}1 & b\\ 2 & d\end{bmatrix})}{det(\mathbf{A})},y=\frac{det(\begin{bmatrix}a & 1\\ c & 2\end{bmatrix})}{det(\mathbf{A})}$';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: MarkdownBody(
                  data: markdown,
                  selectable: true,
                  softLineBreak: true,
                  styleSheet: previewTheme.buildStyleSheet(theme),
                  blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
                  inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
                  builders: buildChatMarkdownElementBuilders(
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

      expect(find.byType(ChatMarkdownLatexInline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
