part of 'chat_page.dart';

extension _ChatPageStateMethodsPAttachmentLinks on _ChatPageState {
  Future<bool> _openAttachmentFromDeepLink(String href) async {
    final parsed = parseAttachmentDeepLink(href);
    if (parsed == null) return false;

    final appBackend = AppBackendScope.of(context);
    if (appBackend is! AttachmentsBackend) {
      return true;
    }
    final attachmentsBackend = appBackend as AttachmentsBackend;

    final sessionKey = SessionScope.of(context).sessionKey;
    final attachment = await findAttachmentBySha(
      attachmentsBackend,
      sessionKey,
      sha256: parsed.sha256,
    );
    if (!mounted) return true;

    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.t.errors.loadFailed(error: 'attachment_not_found')),
          duration: const Duration(seconds: 2),
        ),
      );
      return true;
    }

    await _openAttachmentDetail(attachment);
    return true;
  }

  Future<void> _handleMessageMarkdownTapLink(String? href) async {
    await handleChatMarkdownTapLink(
      href,
      handleInApp: _openAttachmentFromDeepLink,
    );
  }
}
