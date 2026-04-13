import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/pages.dart';

Future<KnowledgeWrongReason?> showKnowledgePageWrongSheet(
  BuildContext context,
) {
  return showModalBottomSheet<KnowledgeWrongReason>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(context.t.memory.wrongReasons.statementWrong),
            onTap: () =>
                Navigator.of(context).pop(KnowledgeWrongReason.statementWrong),
          ),
          ListTile(
            title: Text(context.t.memory.wrongReasons.outdated),
            onTap: () =>
                Navigator.of(context).pop(KnowledgeWrongReason.outdated),
          ),
          ListTile(
            title: Text(context.t.memory.wrongReasons.incomplete),
            onTap: () =>
                Navigator.of(context).pop(KnowledgeWrongReason.incomplete),
          ),
          ListTile(
            title: Text(context.t.memory.wrongReasons.shouldNotRemember),
            onTap: () => Navigator.of(context)
                .pop(KnowledgeWrongReason.shouldNotRemember),
          ),
        ],
      ),
    ),
  );
}
