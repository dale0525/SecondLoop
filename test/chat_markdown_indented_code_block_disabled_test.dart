import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Chat bubble markdown ignores indented code blocks',
      (tester) async {
    final backend = TestAppBackend(
      initialMessages: const [
        Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'assistant',
          content: '## 鲤鱼说英语\n服务号：鲤鱼说英语\n\n    视频号：鲤鱼说英语',
          createdAtMs: 0,
          isMemory: true,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: InkRipple.splashFactory,
          ),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'main_stream',
                  title: 'Main Stream',
                  createdAtMs: 0,
                  updatedAtMs: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final richTextWidgets = tester.widgetList<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('视频号：鲤鱼说英语'),
      ),
    );
    expect(richTextWidgets, isNotEmpty);

    final span = richTextWidgets.first.text;
    expect(_containsFontFamily(span, 'monospace'), isFalse);
  });
}

bool _containsFontFamily(InlineSpan span, String fontFamily) {
  if (span is TextSpan) {
    final style = span.style;
    if (style != null && style.fontFamily == fontFamily) return true;
    final children = span.children;
    if (children == null) return false;
    for (final child in children) {
      if (_containsFontFamily(child, fontFamily)) return true;
    }
  }
  return false;
}
