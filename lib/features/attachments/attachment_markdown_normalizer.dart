import '../chat/chat_markdown_preview.dart';

String normalizeAttachmentMarkdown(String raw) {
  return normalizeChatMarkdownForPreview(
    raw,
    restoreEscapedNewlines: true,
  );
}
