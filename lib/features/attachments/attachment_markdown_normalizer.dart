import '../chat/chat_markdown_sanitizer.dart';

final RegExp _escapedNewlinePattern = RegExp(r'(?<!\\)\\n');
final RegExp _escapedCarriageNewlinePattern = RegExp(r'(?<!\\)\\r\\n');
final RegExp _escapedCarriageReturnPattern = RegExp(r'(?<!\\)\\r');

String normalizeAttachmentMarkdown(String raw) {
  var normalized = raw.replaceAll('\r\n', '\n').trim();

  if (!normalized.contains('\n') &&
      _escapedNewlinePattern.hasMatch(normalized)) {
    normalized = normalized
        .replaceAll(_escapedCarriageNewlinePattern, '\n')
        .replaceAll(_escapedNewlinePattern, '\n')
        .replaceAll(_escapedCarriageReturnPattern, '\r');
  }

  return sanitizeChatMarkdown(normalized);
}
