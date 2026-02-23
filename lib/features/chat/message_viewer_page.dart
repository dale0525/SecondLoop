import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/session/session_scope.dart';
import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_viewer_page.dart';
import '../../i18n/strings.g.dart';
import 'chat_markdown_link_handler.dart';
import 'chat_markdown_preview.dart';

class MessageViewerPage extends StatelessWidget {
  const MessageViewerPage({required this.content, super.key});

  final String content;

  Future<bool> _openAttachmentDeepLink(
      BuildContext context, String href) async {
    final parsed = parseAttachmentDeepLink(href);
    if (parsed == null) return false;

    final appBackend = AppBackendScope.of(context);
    if (appBackend is! AttachmentsBackend) return true;
    final attachmentsBackend = appBackend as AttachmentsBackend;

    final sessionKey = SessionScope.of(context).sessionKey;
    final attachment = await findAttachmentBySha(
      attachmentsBackend,
      sessionKey,
      sha256: parsed.sha256,
    );

    if (!context.mounted) return true;
    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.errors.loadFailed(error: 'attachment_not_found'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return true;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AttachmentViewerPage(attachment: attachment),
      ),
    );
    return true;
  }

  Future<void> _handleTapLink(
    BuildContext context,
    String? href,
  ) async {
    await handleChatMarkdownTapLink(
      href,
      handleInApp: (target) => _openAttachmentDeepLink(context, target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeChatMarkdownForPreview(content);
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: chatMarkdownPreviewCanvasColor(context),
        ),
        child: SafeArea(
          top: false,
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: ChatMarkdownPreviewPanel(
                child: buildChatMarkdownPreviewBody(
                  context,
                  text: normalized,
                  selectable: true,
                  onTapLink: (text, href, title) =>
                      unawaited(_handleTapLink(context, href)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
