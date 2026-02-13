import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_focus_ring.dart';
import '../../ui/sl_icon_button.dart';
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
  final ScrollController _horizontalScrollController = ScrollController();
  late ChatEditorMode _mode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _mode =
        widget.allowPlainMode ? widget.initialMode : ChatEditorMode.markdown;
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
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _save() {
    Navigator.of(context).pop(_controller.text);
  }

  void _switchToMarkdownMode() {
    if (_mode == ChatEditorMode.markdown) return;
    setState(() => _mode = ChatEditorMode.markdown);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocusNode.requestFocus();
    });
  }

  void _switchToPlainMode() {
    if (!widget.allowPlainMode || _mode == ChatEditorMode.plain) return;
    setState(() => _mode = ChatEditorMode.plain);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocusNode.requestFocus();
    });
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
          if (widget.allowPlainMode && _mode == ChatEditorMode.markdown)
            IconButton(
              key: const ValueKey('chat_markdown_editor_switch_plain'),
              tooltip: context.t.chat.switchToKeyboardInput,
              onPressed: _switchToPlainMode,
              icon: const Icon(Icons.keyboard_rounded),
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
      body: _mode == ChatEditorMode.markdown
          ? _buildMarkdownEditorBody(context)
          : _buildPlainEditorBody(context),
    );
  }

  Widget _buildPlainEditorBody(BuildContext context) {
    final tokens = SlTokens.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.04),
            tokens.background,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SlFocusRing(
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                child: SlSurface(
                  color: tokens.surface2,
                  borderColor: tokens.borderSubtle,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: widget.inputFieldKey,
                          controller: _controller,
                          focusNode: _editorFocusNode,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: context.t.common.fields.message,
                            border: InputBorder.none,
                            filled: false,
                            isDense: true,
                          ),
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: 1,
                          maxLines: 6,
                        ),
                      ),
                      if (widget.allowPlainMode) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: context.t.chat.markdownEditor.openButton,
                          child: SlIconButton(
                            key: const ValueKey(
                                'chat_markdown_editor_switch_markdown'),
                            icon: Icons.open_in_full_rounded,
                            size: 40,
                            iconSize: 20,
                            tooltip: context.t.chat.markdownEditor.openButton,
                            onPressed: _switchToMarkdownMode,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        const minCanvasWidth = 900.0;
        final viewportWidth = constraints.maxWidth;
        final canvasWidth = math.max(viewportWidth, minCanvasWidth);

        final content = SizedBox(
          width: canvasWidth,
          child: Row(
            children: [
              Expanded(
                child: _buildPane(
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
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: tokens.borderSubtle,
              ),
              Expanded(
                child: _buildPane(
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
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
                                MarkdownStyleSheet.fromTheme(Theme.of(context))
                                    .copyWith(
                              p: Theme.of(context).textTheme.bodyMedium,
                              codeblockPadding: const EdgeInsets.all(10),
                              blockquotePadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );

        if (viewportWidth >= minCanvasWidth) {
          return content;
        }

        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        );
      },
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
