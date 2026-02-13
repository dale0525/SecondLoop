import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'chat_markdown_sanitizer.dart';

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

class ChatMarkdownEditorResult {
  const ChatMarkdownEditorResult._({
    required this.text,
    required this.action,
  });

  const ChatMarkdownEditorResult.save(String text)
      : this._(text: text, action: ChatMarkdownEditorAction.save);

  const ChatMarkdownEditorResult.switchToSimpleInput(String text)
      : this._(
            text: text, action: ChatMarkdownEditorAction.switchToSimpleInput);

  final String text;
  final ChatMarkdownEditorAction action;

  bool get shouldSwitchToSimpleInput =>
      action == ChatMarkdownEditorAction.switchToSimpleInput;
}

class ChatMarkdownEditorPage extends StatefulWidget {
  const ChatMarkdownEditorPage({
    required this.initialText,
    this.title,
    this.saveLabel,
    this.inputFieldKey = const ValueKey('chat_markdown_editor_input'),
    this.saveButtonKey = const ValueKey('chat_markdown_editor_save'),
    this.allowPlainMode = false,
    this.initialMode = ChatEditorMode.markdown,
    super.key,
  });

  final String initialText;
  final String? title;
  final String? saveLabel;
  final Key inputFieldKey;
  final Key saveButtonKey;
  final bool allowPlainMode;
  final ChatEditorMode initialMode;

  @override
  State<ChatMarkdownEditorPage> createState() => _ChatMarkdownEditorPageState();
}

class _ChatMarkdownEditorPageState extends State<ChatMarkdownEditorPage> {
  late final TextEditingController _controller;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _previewScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _save() {
    Navigator.of(context).pop(ChatMarkdownEditorResult.save(_controller.text));
  }

  void _switchToPlainMode() {
    if (!widget.allowPlainMode) return;
    Navigator.of(context)
        .pop(ChatMarkdownEditorResult.switchToSimpleInput(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? context.t.chat.markdownEditor.title;
    final saveLabel = widget.saveLabel ?? context.t.common.actions.save;

    return Scaffold(
      key: const ValueKey('chat_markdown_editor_page'),
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.allowPlainMode)
            IconButton(
              key: const ValueKey('chat_markdown_editor_switch_plain'),
              tooltip: context.t.chat.markdownEditor.simpleInput,
              onPressed: _switchToPlainMode,
              icon: const Icon(Icons.notes_rounded),
            ),
          TextButton(
            onPressed: _cancel,
            child: Text(context.t.common.actions.cancel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: widget.saveButtonKey,
            onPressed: _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(saveLabel),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _buildMarkdownEditorBody(context),
    );
  }

  Widget _buildMarkdownEditorBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = SlTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primary.withOpacity(0.08),
            tokens.background,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SlSurface(
                color: tokens.surface.withOpacity(0.78),
                borderColor: tokens.border,
                borderRadius: BorderRadius.circular(tokens.radiusLg + 6),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 12),
                    Expanded(child: _buildSplitEditor(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SlSurface(
      color: colorScheme.secondaryContainer.withOpacity(0.32),
      borderColor: colorScheme.secondary.withOpacity(0.18),
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, child) {
          final text = value.text;
          final lines = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
          final characters = text.runes.length;

          return Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t.chat.markdownEditor.previewLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                ),
              ),
              Text(
                context.t.chat.markdownEditor.stats(
                  lines: lines,
                  characters: characters,
                ),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSplitEditor(BuildContext context) {
    final tokens = SlTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 980;
        final editorPane = _buildEditorPane(context);
        final previewPane = _buildPreviewPane(context);

        if (isWideLayout) {
          return Row(
            children: [
              Expanded(child: editorPane),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: tokens.borderSubtle,
              ),
              Expanded(child: previewPane),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: editorPane),
            const SizedBox(height: 12),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: 12),
            Expanded(child: previewPane),
          ],
        );
      },
    );
  }

  Widget _buildEditorPane(BuildContext context) {
    return _buildPane(
      context,
      title: context.t.chat.markdownEditor.editorLabel,
      icon: Icons.edit_note_rounded,
      child: TextField(
        key: widget.inputFieldKey,
        controller: _controller,
        focusNode: _editorFocusNode,
        expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: context.t.common.fields.message,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        ),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.5,
          fontFamilyFallback: const [
            'Menlo',
            'Monaco',
            'Consolas',
            'monospace',
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPane(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildPane(
      context,
      key: const ValueKey('chat_markdown_editor_preview'),
      title: context.t.chat.markdownEditor.previewLabel,
      icon: Icons.visibility_outlined,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, child) {
          final text = value.text.trim();
          if (text.isEmpty) {
            return Center(
              child: Text(
                context.t.chat.markdownEditor.emptyPreview,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            );
          }

          return Scrollbar(
            controller: _previewScrollController,
            child: SingleChildScrollView(
              controller: _previewScrollController,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              child: MarkdownBody(
                data: sanitizeChatMarkdown(value.text),
                selectable: true,
                softLineBreak: true,
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyMedium,
                  codeblockPadding: const EdgeInsets.all(10),
                  blockquotePadding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPane(
    BuildContext context, {
    Key? key,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SlSurface(
      key: key,
      color: tokens.surface2.withOpacity(0.86),
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: tokens.borderSubtle,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
