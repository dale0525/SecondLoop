import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/attachments/non_image_attachment_view.dart';
import 'package:secondloop/features/chat/message_viewer_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('large message viewer falls back to markdown rendering',
      (tester) async {
    final content = List<String>.generate(
      220,
      (index) => 'Paragraph ${index + 1}: budget freeze note body',
    ).join('\n\n');

    await tester.pumpWidget(
      wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: MessageViewerPage(
              content: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: MessageViewerPage(content: content, messageId: 'msg-large'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('message_viewer_markdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_knowledge_viewer')),
        findsNothing);
  });

  testWidgets('large attachment viewer renders markdown editor card directly',
      (tester) async {
    String? clipboardText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final content = List<String>.generate(
      240,
      (index) => '## Section ${index + 1}\nLine ${index + 1} for the PDF body',
    ).join('\n\n');
    const attachment = Attachment(
      sha256: 'sha-large-doc',
      mimeType: 'application/pdf',
      path: '/tmp/large.pdf',
      byteLen: 4096,
      createdAtMs: 0,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: Scaffold(
            body: NonImageAttachmentView(
              attachment: attachment,
              bytes: Uint8List(0),
              displayTitle: 'Large PDF',
              initialAnnotationPayload: <String, Object?>{
                'mime_type': 'application/pdf',
                'page_count': 4,
                'extracted_text_full': content,
              },
              onSaveFull: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('attachment_text_full_markdown_deferred')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('attachment_text_full_copy')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_text_full_edit')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('attachment_knowledge_viewer')),
        findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('attachment_text_full_copy')),
    );
    await tester.tap(find.byKey(const ValueKey('attachment_text_full_copy')));
    await tester.pumpAndSettle();

    expect(clipboardText, contains('Section 1'));
  });
}
