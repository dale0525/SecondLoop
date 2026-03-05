import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../chat/chat_markdown_editor_launcher.dart';
import '../chat/chat_markdown_preview.dart';

const _kAttachmentMarkdownDeferredCharThreshold = 3200;
const _kAttachmentMarkdownDeferredLineThreshold = 120;
const _kAttachmentMarkdownDeferredPreviewCharLimit = 1200;
const _kAttachmentMarkdownDeferredPreviewLineLimit = 42;

@visibleForTesting
bool shouldDeferAttachmentMarkdownPreview(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.length >= _kAttachmentMarkdownDeferredCharThreshold) {
    return true;
  }
  final lineCount = '\n'.allMatches(trimmed).length + 1;
  return lineCount >= _kAttachmentMarkdownDeferredLineThreshold;
}

@visibleForTesting
String buildDeferredAttachmentMarkdownPreview(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final lines = trimmed.split('\n');
  final takeLineCount =
      lines.length > _kAttachmentMarkdownDeferredPreviewLineLimit
          ? _kAttachmentMarkdownDeferredPreviewLineLimit
          : lines.length;
  var preview = lines.take(takeLineCount).join('\n');
  var truncated = takeLineCount < lines.length;

  if (preview.length > _kAttachmentMarkdownDeferredPreviewCharLimit) {
    preview = preview
        .substring(0, _kAttachmentMarkdownDeferredPreviewCharLimit)
        .trimRight();
    truncated = true;
  }

  if (!truncated) return preview;
  if (preview.endsWith('…')) return preview;
  return '$preview\n…';
}

class AttachmentTextEditorCardAction {
  const AttachmentTextEditorCardAction({
    required this.id,
    required this.icon,
    required this.label,
    this.tooltip,
    this.buttonKey,
    this.onPressed,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? tooltip;
  final Key? buttonKey;
  final Future<void> Function()? onPressed;
}

enum _AttachmentTextEditorMenuAction {
  copy,
  edit,
  extra,
}

class AttachmentTextEditorCard extends StatefulWidget {
  const AttachmentTextEditorCard({
    required this.fieldKeyPrefix,
    required this.text,
    required this.emptyText,
    this.label,
    this.showLabel = true,
    this.onSave,
    this.markdown = false,
    this.extraAction,
    super.key,
  });

  final String fieldKeyPrefix;
  final String? label;
  final bool showLabel;
  final String text;
  final String emptyText;
  final Future<void> Function(String value)? onSave;
  final bool markdown;
  final AttachmentTextEditorCardAction? extraAction;

  @override
  State<AttachmentTextEditorCard> createState() =>
      _AttachmentTextEditorCardState();
}

class _AttachmentTextEditorCardState extends State<AttachmentTextEditorCard> {
  TextEditingController? _controller;
  bool _editing = false;
  bool _saving = false;
  bool _markdownPreviewExpanded = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AttachmentTextEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.markdown != widget.markdown) {
      _markdownPreviewExpanded = false;
    }
  }

  Future<void> _persistValue(String nextValue) async {
    if (_saving) return;
    final callback = widget.onSave;
    if (callback == null) return;

    setState(() => _saving = true);
    try {
      await callback(nextValue);
      if (!mounted) return;
      _controller?.dispose();
      _controller = null;
      setState(() {
        _editing = false;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$error')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _save() async {
    final controller = _controller;
    if (controller == null) return;
    await _persistValue(controller.text.trim());
  }

  void _beginEdit() {
    if (_saving) return;
    if (widget.markdown) {
      unawaited(_editMarkdownWithFullEditor());
      return;
    }

    _controller?.dispose();
    _controller = TextEditingController(text: widget.text);
    setState(() => _editing = true);
  }

  Future<void> _editMarkdownWithFullEditor() async {
    final result = await openChatMarkdownEditor(
      context,
      initialText: widget.text,
      title: (widget.label ?? '').trim().isNotEmpty
          ? widget.label!.trim()
          : context.t.chat.markdownEditor.title,
      saveLabel: context.t.common.actions.save,
      allowPlainMode: false,
    );
    if (result == null) return;
    await _persistValue(result.text.trim());
  }

  Future<void> _copyDisplayText() async {
    final text = widget.text.trim();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.actions.history.actions.copied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _runExtraAction() async {
    if (_saving) return;
    final callback = widget.extraAction?.onPressed;
    if (callback == null) return;
    await callback();
  }

  Widget _buildMenuItemLabel(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    );
  }

  Future<void> _showActionsMenuAt(Offset globalPosition) async {
    if (_editing) return;
    final overlay = Overlay.maybeOf(context);
    final overlayObject = overlay?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;

    final extraAction = widget.extraAction;
    final selected = await showMenu<_AttachmentTextEditorMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlayObject.size,
      ),
      items: [
        PopupMenuItem<_AttachmentTextEditorMenuAction>(
          key: ValueKey('${widget.fieldKeyPrefix}_menu_copy'),
          value: _AttachmentTextEditorMenuAction.copy,
          child: _buildMenuItemLabel(
            Icons.copy_all_rounded,
            context.t.common.actions.copy,
          ),
        ),
        if (extraAction != null)
          PopupMenuItem<_AttachmentTextEditorMenuAction>(
            key: ValueKey('${widget.fieldKeyPrefix}_menu_${extraAction.id}'),
            value: _AttachmentTextEditorMenuAction.extra,
            enabled: !_saving && extraAction.onPressed != null,
            child: _buildMenuItemLabel(
              extraAction.icon,
              extraAction.label,
            ),
          ),
        if (widget.onSave != null)
          PopupMenuItem<_AttachmentTextEditorMenuAction>(
            key: ValueKey('${widget.fieldKeyPrefix}_menu_edit'),
            value: _AttachmentTextEditorMenuAction.edit,
            enabled: !_saving,
            child: _buildMenuItemLabel(
              Icons.edit_outlined,
              context.t.common.actions.edit,
            ),
          ),
      ],
    );
    if (!mounted || selected == null) return;

    switch (selected) {
      case _AttachmentTextEditorMenuAction.copy:
        await _copyDisplayText();
        break;
      case _AttachmentTextEditorMenuAction.edit:
        _beginEdit();
        break;
      case _AttachmentTextEditorMenuAction.extra:
        await _runExtraAction();
        break;
    }
  }

  void _cancelEdit() {
    _controller?.dispose();
    _controller = null;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final deferredMarkdownPreview = widget.markdown &&
        !_editing &&
        text.isNotEmpty &&
        !_markdownPreviewExpanded &&
        shouldDeferAttachmentMarkdownPreview(text);
    final canEdit = widget.onSave != null;
    final resolvedLabel = (widget.label ?? '').trim();
    final hasLabel = widget.showLabel && resolvedLabel.isNotEmpty;
    final showHeader = hasLabel || !_editing;
    final extraAction = widget.extraAction;

    return GestureDetector(
      key: ValueKey('${widget.fieldKeyPrefix}_card'),
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: _editing
          ? null
          : (details) => unawaited(_showActionsMenuAt(details.globalPosition)),
      onLongPressStart: _editing
          ? null
          : (details) => unawaited(_showActionsMenuAt(details.globalPosition)),
      child: SlSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Row(
                children: [
                  if (hasLabel)
                    Expanded(
                      child: Text(
                        resolvedLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    )
                  else
                    const Spacer(),
                  if (!_editing)
                    IconButton(
                      key: ValueKey('${widget.fieldKeyPrefix}_copy'),
                      icon: const Icon(Icons.copy_all_rounded),
                      tooltip: context.t.common.actions.copy,
                      onPressed:
                          _saving ? null : () => unawaited(_copyDisplayText()),
                    ),
                  if (!_editing && extraAction != null)
                    IconButton(
                      key: extraAction.buttonKey ??
                          ValueKey(
                              '${widget.fieldKeyPrefix}_${extraAction.id}'),
                      icon: Icon(extraAction.icon),
                      tooltip: extraAction.tooltip ?? extraAction.label,
                      onPressed: _saving || extraAction.onPressed == null
                          ? null
                          : () => unawaited(_runExtraAction()),
                    ),
                  if (!_editing && canEdit)
                    IconButton(
                      key: ValueKey('${widget.fieldKeyPrefix}_edit'),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: context.t.common.actions.edit,
                      onPressed: _saving ? null : _beginEdit,
                    ),
                ],
              ),
            if (showHeader) const SizedBox(height: 6),
            if (!_editing)
              if (text.isEmpty)
                Text(
                  widget.emptyText,
                  key: ValueKey('${widget.fieldKeyPrefix}_empty'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                )
              else if (widget.markdown)
                deferredMarkdownPreview
                    ? Column(
                        key: ValueKey(
                            '${widget.fieldKeyPrefix}_markdown_deferred'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            buildDeferredAttachmentMarkdownPreview(text),
                            key: ValueKey(
                              '${widget.fieldKeyPrefix}_markdown_deferred_text',
                            ),
                            maxLines: 14,
                            overflow: TextOverflow.fade,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: ValueKey(
                                '${widget.fieldKeyPrefix}_markdown_expand',
                              ),
                              onPressed: () {
                                setState(() => _markdownPreviewExpanded = true);
                              },
                              icon: const Icon(Icons.visibility_rounded),
                              label: Text(context.t.chat.viewFull),
                            ),
                          ),
                        ],
                      )
                    : ChatMarkdownPreviewPanel(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                        child: buildChatMarkdownPreviewBody(
                          context,
                          key: ValueKey(
                              '${widget.fieldKeyPrefix}_markdown_display'),
                          text: text,
                          selectable: true,
                          restoreEscapedNewlines: true,
                          bodyStyle: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
              else
                SelectableText(
                  text,
                  key: ValueKey('${widget.fieldKeyPrefix}_display'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            if (_editing) ...[
              TextField(
                key: ValueKey('${widget.fieldKeyPrefix}_field'),
                controller: _controller,
                enabled: !_saving,
                maxLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: ValueKey('${widget.fieldKeyPrefix}_cancel'),
                    onPressed: _saving ? null : _cancelEdit,
                    child: Text(context.t.common.actions.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: ValueKey('${widget.fieldKeyPrefix}_save'),
                    onPressed: _saving ? null : () => unawaited(_save()),
                    child: Text(context.t.common.actions.save),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
