import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/attachment_draft_send_contract.dart';
import 'package:secondloop/features/chat/chat_markdown_clipboard_export.dart';
import 'package:secondloop/features/chat/chat_markdown_theme_presets.dart';

void main() {
  test('Clipboard HTML export keeps core markdown structure', () async {
    final theme = resolveChatMarkdownTheme(
      ChatMarkdownThemePreset.paper,
      ThemeData.light(),
    );

    final html = await buildChatMarkdownClipboardHtml(
      markdown: '# Title\n\n- **Bold** and `code`',
      theme: theme,
      emptyFallback: 'Preview will appear as you type.',
    );

    expect(html, contains('Title</h1>'));
    expect(html, contains('<strong>Bold</strong>'));
    expect(html, contains('<code>code</code>'));
  });

  test('Clipboard plain text export falls back when markdown is empty', () {
    final text = buildChatMarkdownClipboardPlainText(
      '   ',
      emptyFallback: 'Preview will appear as you type.',
    );

    expect(text, 'Preview will appear as you type.');
  });

  test(
      'Clipboard HTML export does not turn bare message deeplinks into anchors',
      () async {
    final theme = resolveChatMarkdownTheme(
      ChatMarkdownThemePreset.paper,
      ThemeData.light(),
    );

    final html = await buildChatMarkdownClipboardHtml(
      markdown: 'History: secondloop://message/history-1',
      theme: theme,
      emptyFallback: 'Preview will appear as you type.',
    );

    expect(html, contains('secondloop://message/history-1'));
    expect(
      html,
      isNot(contains('href="secondloop://message/history-1"')),
    );
  });

  test('Clipboard HTML export inlines draft attachment image refs', () async {
    final theme = resolveChatMarkdownTheme(
      ChatMarkdownThemePreset.paper,
      ThemeData.light(),
    );

    final html = await buildChatMarkdownClipboardHtml(
      markdown: '![draft](secondloop-draft://image/draft_1)',
      theme: theme,
      emptyFallback: 'Preview will appear as you type.',
      draftAttachments: <AttachmentDraftPayload>[
        AttachmentDraftPayload(
          localId: 'draft_1',
          filename: 'draft.png',
          mimeType: 'image/png',
          bytes: _pngBytes(),
        ),
      ],
    );

    expect(html, contains('src="data:image/png;base64,'));
    expect(html, isNot(contains('secondloop-draft://image/draft_1')));
  });
}

Uint8List _pngBytes() => Uint8List.fromList(const <int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0x00,
      0x00,
      0x00,
      0x0d,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1f,
      0x15,
      0xc4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0a,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9c,
      0x63,
      0xf8,
      0xcf,
      0xc0,
      0x00,
      0x00,
      0x03,
      0x01,
      0x01,
      0x00,
      0x18,
      0xdd,
      0x8d,
      0xb1,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4e,
      0x44,
      0xae,
      0x42,
      0x60,
      0x82,
    ]);
