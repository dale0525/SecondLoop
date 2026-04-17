part of 'chat_page.dart';

extension _ChatPageStateMessageBubbleDetail on _ChatPageState {
  Future<bool> _openMessageBubblePrimaryDetail({
    required Message message,
    required _TodoMessageBadgeMeta? todoBadgeMeta,
    required AttachmentsBackend? attachmentsBackend,
    required Uint8List sessionKey,
  }) async {
    if (todoBadgeMeta != null) {
      final openedTodo = await _openTodoFromBadge(todoBadgeMeta);
      if (openedTodo) return true;
    }

    if (attachmentsBackend == null) return false;

    final attachments = await _loadMessageAttachmentsForUi(
      messageId: message.id,
      attachmentsBackend: attachmentsBackend,
      sessionKey: sessionKey,
    );
    if (!mounted || attachments.isEmpty) return false;

    await _openAttachmentDetail(attachments.first);
    return true;
  }

  Future<void> _openAttachmentDetail(Attachment attachment) async {
    await _pushRouteFromChat(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          AttachmentViewerPage(attachment: attachment),
        ),
      ),
    );
  }

  Future<bool> _handleMarkdownInAppLink(String href) async {
    final todoLink = parseTodoDeepLink(href);
    if (todoLink != null) {
      await _openTodoById(todoLink.todoId);
      return true;
    }

    final attachmentLink = parseAttachmentDeepLink(href);
    if (attachmentLink != null) {
      await AttachmentViewerPage.openBySha(
        context,
        attachmentSha256: attachmentLink.attachmentSha256,
        initialContentKind: attachmentLink.kind,
        initialChunkIndex: attachmentLink.chunk,
      );
      return true;
    }

    final messageLink = parseMessageDeepLink(href);
    if (messageLink == null) {
      return false;
    }

    await MessageViewerPage.openById(
      context,
      messageId: messageLink.messageId,
    );
    return true;
  }
}
