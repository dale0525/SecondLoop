import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'chat_markdown_editor_page.dart';

typedef ChatMarkdownEditorRoutePusher = Future<ChatMarkdownEditorResult?>
    Function(
  Route<ChatMarkdownEditorResult> route,
);

Future<ChatMarkdownEditorResult?> openChatMarkdownEditor(
  BuildContext context, {
  required String initialText,
  String? title,
  String? saveLabel,
  Key inputFieldKey = const ValueKey('chat_markdown_editor_input'),
  Key saveButtonKey = const ValueKey('chat_markdown_editor_save'),
  bool allowPlainMode = false,
  ChatEditorMode initialMode = ChatEditorMode.markdown,
  ChatMarkdownEditorRoutePusher? routePusher,
}) {
  final route = MaterialPageRoute<ChatMarkdownEditorResult>(
    builder: (context) => ChatMarkdownEditorPage(
      initialText: initialText,
      title: title ?? context.t.chat.markdownEditor.title,
      saveLabel: saveLabel ?? context.t.common.actions.save,
      inputFieldKey: inputFieldKey,
      saveButtonKey: saveButtonKey,
      allowPlainMode: allowPlainMode,
      initialMode: initialMode,
    ),
  );

  if (routePusher != null) {
    return routePusher(route);
  }

  return Navigator.of(context).push(route);
}
