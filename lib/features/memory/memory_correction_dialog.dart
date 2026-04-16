import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';

class MemoryCorrectionDraft {
  const MemoryCorrectionDraft({
    required this.title,
    required this.summary,
    this.body,
  });

  final String title;
  final String summary;
  final String? body;
}

Future<MemoryCorrectionDraft?> showMemoryCorrectionDialog(
  BuildContext context, {
  required String initialTitle,
  required String initialSummary,
  String? initialBody,
}) async {
  final titleController = TextEditingController(text: initialTitle);
  final summaryController = TextEditingController(text: initialSummary);
  final bodyController =
      initialBody == null ? null : TextEditingController(text: initialBody);

  final shouldSave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t.memory.actions.editMemory),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('memory_correction_title_field'),
              controller: titleController,
              decoration: InputDecoration(
                labelText: context.t.memory.actions.fields.title,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('memory_correction_summary_field'),
              controller: summaryController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: context.t.memory.actions.fields.summary,
              ),
            ),
            if (bodyController != null) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('memory_correction_body_field'),
                controller: bodyController,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: context.t.memory.actions.fields.body,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t.common.actions.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t.common.actions.save),
        ),
      ],
    ),
  );

  if (shouldSave != true) return null;
  return MemoryCorrectionDraft(
    title: titleController.text.trim(),
    summary: summaryController.text.trim(),
    body: bodyController?.text.trim(),
  );
}
