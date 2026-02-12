import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'attachment_markdown_normalizer.dart';

class AttachmentTextEditorCard extends StatefulWidget {
  const AttachmentTextEditorCard({
    required this.fieldKeyPrefix,
    required this.text,
    required this.emptyText,
    this.label,
    this.showLabel = true,
    this.onSave,
    this.markdown = false,
    this.trailing,
    super.key,
  });

  final String fieldKeyPrefix;
  final String? label;
  final bool showLabel;
  final String text;
  final String emptyText;
  final Future<void> Function(String value)? onSave;
  final bool markdown;
  final Widget? trailing;

  @override
  State<AttachmentTextEditorCard> createState() =>
      _AttachmentTextEditorCardState();
}

class _AttachmentTextEditorCardState extends State<AttachmentTextEditorCard> {
  TextEditingController? _controller;
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final callback = widget.onSave;
    final controller = _controller;
    if (callback == null || controller == null) return;

    final nextValue = controller.text.trim();
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

  void _beginEdit() {
    _controller?.dispose();
    _controller = TextEditingController(text: widget.text);
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _controller?.dispose();
    _controller = null;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final canEdit = widget.onSave != null;
    final resolvedLabel = (widget.label ?? '').trim();
    final hasLabel = widget.showLabel && resolvedLabel.isNotEmpty;
    final showHeader =
        hasLabel || (!_editing && (widget.trailing != null || canEdit));

    return SlSurface(
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
                if (!_editing && widget.trailing != null) widget.trailing!,
                if (!_editing && canEdit)
                  IconButton(
                    key: ValueKey('${widget.fieldKeyPrefix}_edit'),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: context.t.common.actions.edit,
                    onPressed: _beginEdit,
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
              MarkdownBody(
                key: ValueKey('${widget.fieldKeyPrefix}_markdown_display'),
                data: normalizeAttachmentMarkdown(text),
                selectable: true,
                softLineBreak: true,
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodySmall,
                  listBullet: Theme.of(context).textTheme.bodySmall,
                  code: Theme.of(context).textTheme.bodySmall,
                  codeblockPadding: const EdgeInsets.all(8),
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
    );
  }
}
