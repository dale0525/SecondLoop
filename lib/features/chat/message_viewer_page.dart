import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_markdown_style.dart';
import 'chat_markdown_rich_rendering.dart';
import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

class MessageViewerPage extends StatelessWidget {
  const MessageViewerPage({required this.content, super.key});

  final String content;

  @override
  Widget build(BuildContext context) {
    final normalized = sanitizeChatMarkdown(content);
    final theme = Theme.of(context);
    final previewTheme =
        resolveChatMarkdownTheme(ChatMarkdownThemePreset.studio, theme);

    return Scaffold(
      key: const ValueKey('message_viewer_page'),
      appBar: AppBar(
        title: Text(context.t.chat.messageViewer.title),
        actions: [
          IconButton(
            key: const ValueKey('message_viewer_copy'),
            tooltip: context.t.common.actions.copy,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: normalized.trim()));
              } catch (_) {
                return;
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.t.actions.history.actions.copied),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
      body: Markdown(
        data: normalized,
        selectable: true,
        softLineBreak: true,
        styleSheet: slMarkdownStyleSheet(context),
        blockSyntaxes: buildChatMarkdownBlockSyntaxes(),
        inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
        builders: buildChatMarkdownElementBuilders(
          previewTheme: previewTheme,
          exportRenderMode: false,
        ),
      ),
    );
  }
}
