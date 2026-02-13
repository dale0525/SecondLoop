import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'chat_markdown_editing_utils.dart';
import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

part 'chat_markdown_editor_page_export.dart';

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

class _ChatMarkdownEditorPageState extends State<ChatMarkdownEditorPage>
    with _ChatMarkdownEditorExportMixin {
  late final TextEditingController _controller;
  @override
  final FocusNode _editorFocusNode = FocusNode();
  @override
  final ScrollController _previewScrollController = ScrollController();
  @override
  final GlobalKey _previewRepaintBoundaryKey = GlobalKey();

  @override
  ChatMarkdownCompactPane _compactPane = ChatMarkdownCompactPane.editor;
  @override
  ChatMarkdownThemePreset _themePreset = ChatMarkdownThemePreset.studio;
  @override
  bool _exporting = false;

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

  void _showCompactEditor() {
    if (_compactPane == ChatMarkdownCompactPane.editor) return;
    setState(() => _compactPane = ChatMarkdownCompactPane.editor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocusNode.requestFocus();
    });
  }

  void _showCompactPreview() {
    if (_compactPane == ChatMarkdownCompactPane.preview) return;
    setState(() => _compactPane = ChatMarkdownCompactPane.preview);
  }

  void _applyEditorChange(
    TextEditingValue Function(TextEditingValue value) transform,
  ) {
    final next = transform(_controller.value);
    _controller.value = next;
    _editorFocusNode.requestFocus();
  }

  void _insertHeading(int level) {
    _applyEditorChange(
      (value) => applyMarkdownHeading(value, level: level),
    );
  }

  void _toggleBold() {
    _applyEditorChange(
      (value) => applyMarkdownInlineWrap(value, prefix: '**'),
    );
  }

  void _toggleItalic() {
    _applyEditorChange(
      (value) => applyMarkdownInlineWrap(value, prefix: '*'),
    );
  }

  void _toggleStrike() {
    _applyEditorChange(
      (value) => applyMarkdownInlineWrap(value, prefix: '~~'),
    );
  }

  void _toggleInlineCode() {
    _applyEditorChange(
      (value) => applyMarkdownInlineWrap(value, prefix: '`'),
    );
  }

  void _insertLink() {
    _applyEditorChange(applyMarkdownLink);
  }

  void _toggleQuote() {
    _applyEditorChange(applyMarkdownBlockquote);
  }

  void _toggleBulletList() {
    _applyEditorChange(toggleMarkdownUnorderedList);
  }

  void _toggleOrderedList() {
    _applyEditorChange(toggleMarkdownOrderedList);
  }

  void _toggleTaskList() {
    _applyEditorChange(toggleMarkdownTaskList);
  }

  void _insertCodeBlock() {
    _applyEditorChange(applyMarkdownCodeBlock);
  }

  @override
  bool _isWideLayout(BuildContext context) {
    final windowSize = MediaQuery.sizeOf(context);
    return windowSize.width > windowSize.height;
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings() {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _toggleBold,
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          _toggleBold,
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true): _toggleItalic,
      const SingleActivator(LogicalKeyboardKey.keyI, control: true):
          _toggleItalic,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _insertLink,
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          _insertLink,
    };
  }

  String _themeLabel(BuildContext context, ChatMarkdownThemePreset preset) {
    switch (preset) {
      case ChatMarkdownThemePreset.studio:
        return context.t.chat.markdownEditor.themeStudio;
      case ChatMarkdownThemePreset.paper:
        return context.t.chat.markdownEditor.themePaper;
      case ChatMarkdownThemePreset.ocean:
        return context.t.chat.markdownEditor.themeOcean;
      case ChatMarkdownThemePreset.night:
        return context.t.chat.markdownEditor.themeNight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? context.t.chat.markdownEditor.title;
    final saveLabel = widget.saveLabel ?? context.t.common.actions.save;

    return CallbackShortcuts(
      bindings: _shortcutBindings(),
      child: Scaffold(
        key: const ValueKey('chat_markdown_editor_page'),
        appBar: AppBar(
          title: Text(title),
          actions: [
            PopupMenuButton<_MarkdownExportFormat>(
              key: const ValueKey('chat_markdown_editor_export_menu'),
              tooltip: context.t.chat.markdownEditor.exportMenu,
              enabled: !_exporting,
              onSelected: _export,
              itemBuilder: (context) => <PopupMenuEntry<_MarkdownExportFormat>>[
                PopupMenuItem<_MarkdownExportFormat>(
                  value: _MarkdownExportFormat.png,
                  child: Text(context.t.chat.markdownEditor.exportPng),
                ),
                PopupMenuItem<_MarkdownExportFormat>(
                  value: _MarkdownExportFormat.pdf,
                  child: Text(context.t.chat.markdownEditor.exportPdf),
                ),
              ],
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_rounded),
            ),
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
                    const SizedBox(height: 10),
                    _buildQuickActions(context),
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

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
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
                    _themeLabel(context, _themePreset),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.t.chat.markdownEditor.stats(
                      lines: lines,
                      characters: characters,
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  _HintTag(
                    icon: Icons.keyboard_command_key_rounded,
                    label: context.t.chat.markdownEditor.shortcutHint,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  _HintTag(
                    icon: Icons.format_list_bulleted_rounded,
                    label: context.t.chat.markdownEditor.listContinuationHint,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final tokens = SlTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return SlSurface(
      key: const ValueKey('chat_markdown_editor_quick_actions'),
      color: tokens.surface2.withOpacity(0.9),
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusMd + 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.chat.markdownEditor.quickActionsLabel,
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildThemeSelector(context),
                const SizedBox(width: 8),
                _buildHeadingSelector(context),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  key: const ValueKey('chat_markdown_editor_action_bold'),
                  icon: Icons.format_bold_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.bold,
                  onPressed: _toggleBold,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.format_italic_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.italic,
                  onPressed: _toggleItalic,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.format_strikethrough_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.strike,
                  onPressed: _toggleStrike,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.code_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.code,
                  onPressed: _toggleInlineCode,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.link_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.link,
                  onPressed: _insertLink,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.format_quote_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.blockquote,
                  onPressed: _toggleQuote,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.format_list_bulleted_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.bulletList,
                  onPressed: _toggleBulletList,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.format_list_numbered_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.orderedList,
                  onPressed: _toggleOrderedList,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.checklist_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.taskList,
                  onPressed: _toggleTaskList,
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  icon: Icons.data_object_rounded,
                  tooltip: context.t.chat.markdownEditor.actions.codeBlock,
                  onPressed: _insertCodeBlock,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<ChatMarkdownThemePreset>(
      key: const ValueKey('chat_markdown_editor_theme_selector'),
      tooltip: context.t.chat.markdownEditor.themeLabel,
      initialValue: _themePreset,
      onSelected: (preset) => setState(() => _themePreset = preset),
      itemBuilder: (context) {
        return kChatMarkdownThemePresets
            .map(
              (preset) => PopupMenuItem<ChatMarkdownThemePreset>(
                value: preset,
                child: Text(_themeLabel(context, preset)),
              ),
            )
            .toList();
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.palette_outlined, size: 16),
            const SizedBox(width: 6),
            Text(
              _themeLabel(context, _themePreset),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadingSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<int>(
      tooltip: context.t.chat.markdownEditor.actions.heading,
      onSelected: _insertHeading,
      itemBuilder: (context) {
        return List<PopupMenuEntry<int>>.generate(
          6,
          (index) {
            final level = index + 1;
            return PopupMenuItem<int>(
              value: level,
              child: Text(
                context.t.chat.markdownEditor.actions.headingLevel(
                  level: level,
                ),
              ),
            );
          },
        );
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.title_rounded, size: 16),
            const SizedBox(width: 6),
            Text(
              context.t.chat.markdownEditor.actions.heading,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(38, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _buildSplitEditor(BuildContext context) {
    final tokens = SlTokens.of(context);
    final isWideLayout = _isWideLayout(context);

    final editorPane = _buildEditorPane(context);
    final previewPane = _buildPreviewPane(context);

    if (isWideLayout) {
      return KeyedSubtree(
        key: const ValueKey('chat_markdown_editor_layout_wide'),
        child: Row(
          children: [
            Expanded(child: editorPane),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: tokens.borderSubtle,
            ),
            Expanded(child: previewPane),
          ],
        ),
      );
    }

    final compactPane = _compactPane == ChatMarkdownCompactPane.editor
        ? KeyedSubtree(
            key: const ValueKey('chat_markdown_editor_compact_editor_pane'),
            child: editorPane,
          )
        : KeyedSubtree(
            key: const ValueKey('chat_markdown_editor_compact_preview_pane'),
            child: previewPane,
          );

    return KeyedSubtree(
      key: const ValueKey('chat_markdown_editor_layout_compact'),
      child: Column(
        children: [
          _buildCompactPaneToggle(context),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: compactPane,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPaneToggle(BuildContext context) {
    final tokens = SlTokens.of(context);
    return SlSurface(
      color: tokens.surface2.withOpacity(0.86),
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildCompactPaneToggleButton(
              context,
              key: const ValueKey('chat_markdown_editor_compact_show_editor'),
              selected: _compactPane == ChatMarkdownCompactPane.editor,
              icon: Icons.edit_note_rounded,
              label: context.t.chat.markdownEditor.editorLabel,
              onPressed: _showCompactEditor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCompactPaneToggleButton(
              context,
              key: const ValueKey('chat_markdown_editor_compact_show_preview'),
              selected: _compactPane == ChatMarkdownCompactPane.preview,
              icon: Icons.visibility_outlined,
              label: context.t.chat.markdownEditor.previewLabel,
              onPressed: _showCompactPreview,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPaneToggleButton(
    BuildContext context, {
    required Key key,
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    const buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.fromHeight(38)),
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
    );

    if (selected) {
      return FilledButton.tonalIcon(
        key: key,
        onPressed: onPressed,
        style: buttonStyle,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      style: buttonStyle,
      icon: Icon(icon, size: 18),
      label: Text(label),
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
        inputFormatters: const <TextInputFormatter>[
          MarkdownSmartContinuationFormatter(),
        ],
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
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
    final theme = Theme.of(context);
    final previewTheme = resolveChatMarkdownTheme(_themePreset, theme);

    return _buildPane(
      context,
      key: const ValueKey('chat_markdown_editor_preview'),
      title: context.t.chat.markdownEditor.previewLabel,
      icon: Icons.visibility_outlined,
      child: RepaintBoundary(
        key: _previewRepaintBoundaryKey,
        child: DecoratedBox(
          decoration: BoxDecoration(color: previewTheme.canvasColor),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final text = value.text.trim();
              if (text.isEmpty) {
                return Center(
                  child: Text(
                    context.t.chat.markdownEditor.emptyPreview,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: previewTheme.mutedTextColor,
                    ),
                  ),
                );
              }

              return Scrollbar(
                controller: _previewScrollController,
                child: SingleChildScrollView(
                  controller: _previewScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: previewTheme.panelColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: previewTheme.borderColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                      child: MarkdownBody(
                        data: sanitizeChatMarkdown(value.text),
                        selectable: true,
                        softLineBreak: true,
                        styleSheet: previewTheme.buildStyleSheet(theme),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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

class _HintTag extends StatelessWidget {
  const _HintTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color.withOpacity(0.86)),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color.withOpacity(0.9),
              ),
        ),
      ],
    );
  }
}
