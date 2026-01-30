import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import 'chat_markdown_sanitizer.dart';

class MessageViewerPage extends StatelessWidget {
  const MessageViewerPage({required this.content, super.key});

  final String content;

  @override
  Widget build(BuildContext context) {
    final normalized = sanitizeChatMarkdown(content);
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
                    content: Text(context.t.actions.history.actions.copied)),
              );
            },
          ),
        ],
      ),
      body: Markdown(
        data: normalized,
        selectable: true,
      ),
    );
  }
}
