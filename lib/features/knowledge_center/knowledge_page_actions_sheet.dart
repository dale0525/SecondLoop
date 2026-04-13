import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';

enum KnowledgePageOverflowAction {
  viewEvidence,
  viewHistory,
  viewReview,
  archive,
  remove,
}

Future<KnowledgePageOverflowAction?> showKnowledgePageActionsSheet(
  BuildContext context, {
  bool includeArchive = true,
  bool includeRemove = true,
}) {
  return showModalBottomSheet<KnowledgePageOverflowAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.t.memory.actions.viewEvidence),
              onTap: () => Navigator.of(context)
                  .pop(KnowledgePageOverflowAction.viewEvidence),
            ),
            ListTile(
              title: Text(context.t.memory.actions.viewHistory),
              onTap: () => Navigator.of(context)
                  .pop(KnowledgePageOverflowAction.viewHistory),
            ),
            ListTile(
              title: Text(context.t.memory.actions.reviewSignals),
              onTap: () => Navigator.of(context)
                  .pop(KnowledgePageOverflowAction.viewReview),
            ),
            if (includeArchive)
              ListTile(
                title: Text(context.t.memory.actions.archivePage),
                onTap: () => Navigator.of(context)
                    .pop(KnowledgePageOverflowAction.archive),
              ),
            if (includeRemove)
              ListTile(
                title: Text(context.t.memory.actions.permanentlyRemove),
                onTap: () => Navigator.of(context)
                    .pop(KnowledgePageOverflowAction.remove),
              ),
          ],
        ),
      ),
    ),
  );
}
