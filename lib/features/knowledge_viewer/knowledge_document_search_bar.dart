import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'knowledge_document_models.dart';

class KnowledgeDocumentSearchBar extends StatelessWidget {
  const KnowledgeDocumentSearchBar({
    required this.queryController,
    required this.searching,
    required this.onSearch,
    required this.onCopy,
    this.onEdit,
    this.extraActions = const <KnowledgeDocumentViewerAction>[],
    super.key,
  });

  final TextEditingController queryController;
  final bool searching;
  final Future<void> Function() onSearch;
  final VoidCallback onCopy;
  final Future<void> Function()? onEdit;
  final List<KnowledgeDocumentViewerAction> extraActions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('knowledge_viewer_search_field'),
            controller: queryController,
            onSubmitted: (_) => unawaited(onSearch()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: context.t.common.actions.search,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('knowledge_viewer_search_submit'),
          onPressed: searching ? null : () => unawaited(onSearch()),
          tooltip: context.t.common.actions.search,
          icon: searching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded),
        ),
        IconButton(
          key: const ValueKey('attachment_knowledge_viewer_copy'),
          onPressed: onCopy,
          tooltip: context.t.common.actions.copy,
          icon: const Icon(Icons.copy_all_outlined),
        ),
        if (onEdit != null)
          IconButton(
            key: const ValueKey('attachment_knowledge_viewer_edit'),
            onPressed: () => unawaited(onEdit!()),
            tooltip: context.t.common.actions.edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        for (final action in extraActions)
          IconButton(
            key: action.buttonKey ??
                ValueKey('attachment_knowledge_viewer_extra_${action.id}'),
            onPressed: action.onPressed == null
                ? null
                : () => unawaited(action.onPressed!()),
            tooltip: action.tooltip ?? action.label,
            icon: Icon(action.icon),
          ),
      ],
    );
  }
}
