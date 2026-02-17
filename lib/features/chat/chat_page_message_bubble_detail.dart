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
        builder: (context) => AttachmentViewerPage(attachment: attachment),
      ),
    );
  }
}
