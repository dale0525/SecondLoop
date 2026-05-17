import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'note_editor_controller.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    required this.controller,
    super.key,
  });

  final NoteEditorController controller;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.controller.title);
    _bodyController = TextEditingController(text: widget.controller.body);
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(NoteEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _StatusChip(status: controller.status),
                  const Spacer(),
                  FilledButton.icon(
                    key: const ValueKey('note_editor_save_button'),
                    onPressed: controller.status == NoteEditorStatus.saving
                        ? null
                        : () => controller.save(
                              title: _titleController.text,
                              body: _bodyController.text,
                            ),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(context.t.common.actions.save),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('note_editor_title_field'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.t.notes.fields.title,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              if (controller.status == NoteEditorStatus.conflict) ...[
                _ConflictPanel(controller: controller),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: TextField(
                  key: const ValueKey('note_editor_body_field'),
                  controller: _bodyController,
                  decoration: InputDecoration(
                    labelText: context.t.notes.fields.body,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _syncFromController() {
    _setTextIfChanged(_titleController, widget.controller.title);
    _setTextIfChanged(_bodyController, widget.controller.body);
  }

  void _setTextIfChanged(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final NoteEditorStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(_label(context)));
  }

  String _label(BuildContext context) {
    return switch (status) {
      NoteEditorStatus.clean => context.t.notes.status.saved,
      NoteEditorStatus.pending => context.t.notes.status.pending,
      NoteEditorStatus.saving => context.t.notes.status.saving,
      NoteEditorStatus.conflict => context.t.notes.status.conflict,
      NoteEditorStatus.failed => context.t.notes.status.failed,
    };
  }
}

class _ConflictPanel extends StatelessWidget {
  const _ConflictPanel({required this.controller});

  final NoteEditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('note_editor_conflict_panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Scrollbar(
          child: SingleChildScrollView(
            key: const ValueKey('note_editor_conflict_scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.notes.labels.local,
                  style: theme.textTheme.labelLarge,
                ),
                Text(controller.body),
                const SizedBox(height: 8),
                Text(
                  context.t.notes.labels.remote,
                  style: theme.textTheme.labelLarge,
                ),
                Text(controller.conflictRemoteBody ?? ''),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
