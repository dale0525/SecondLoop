import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_rich_rendering.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('Message viewer renders latex blocks and inline formulas',
      (tester) async {
    const content = r'''完整的投影变换可以表示为：

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
      wrapWithI18n(
        const MaterialApp(
          home: MessageViewerPage(content: content),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ChatMarkdownLatexBlock), findsOneWidget);
    expect(find.byType(ChatMarkdownLatexInline), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
