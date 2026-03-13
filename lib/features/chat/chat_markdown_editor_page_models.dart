part of 'chat_markdown_editor_page.dart';

const _kDefaultMarkdownModeRuneThreshold = 240;
const _kDefaultMarkdownModeLineThreshold = 6;

bool shouldUseMarkdownEditorByDefault(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.runes.length >= _kDefaultMarkdownModeRuneThreshold) {
    return true;
  }

  final lineCount = '\n'.allMatches(trimmed).length + 1;
  return lineCount >= _kDefaultMarkdownModeLineThreshold;
}

enum ChatEditorMode {
  plain,
  markdown,
}

enum ChatMarkdownEditorAction {
  save,
  switchToSimpleInput,
}

enum ChatMarkdownCompactPane {
  editor,
  preview,
}

enum _MarkdownExportFormat {
  png,
  pdf,
}

enum _MarkdownExportAction {
  png,
  pdf,
  markdownBundle,
  copyToClipboard,
}

class ChatMarkdownEditorResult {
  const ChatMarkdownEditorResult._({
    required this.text,
    required this.action,
    required this.draftAttachments,
  });

  const ChatMarkdownEditorResult.save(String text)
      : this._(
          text: text,
          action: ChatMarkdownEditorAction.save,
          draftAttachments: const <AttachmentDraftPayload>[],
        );

  const ChatMarkdownEditorResult.saveWithAttachments(
    String text,
    List<AttachmentDraftPayload> draftAttachments,
  ) : this._(
          text: text,
          action: ChatMarkdownEditorAction.save,
          draftAttachments: draftAttachments,
        );

  const ChatMarkdownEditorResult.switchToSimpleInput(String text)
      : this._(
          text: text,
          action: ChatMarkdownEditorAction.switchToSimpleInput,
          draftAttachments: const <AttachmentDraftPayload>[],
        );

  final String text;
  final ChatMarkdownEditorAction action;
  final List<AttachmentDraftPayload> draftAttachments;

  bool get shouldSwitchToSimpleInput =>
      action == ChatMarkdownEditorAction.switchToSimpleInput;
}

final class ChatMarkdownPastedImageData {
  const ChatMarkdownPastedImageData({
    required this.bytes,
    required this.mimeType,
    this.filename,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? filename;
}
