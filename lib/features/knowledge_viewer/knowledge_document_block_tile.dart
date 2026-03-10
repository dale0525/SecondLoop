import 'package:flutter/material.dart';

import '../../src/rust/knowledge/models.dart';
import '../../ui/sl_tokens.dart';
import 'knowledge_document_anchor_helpers.dart';

class KnowledgeDocumentBlockTile extends StatelessWidget {
  const KnowledgeDocumentBlockTile({
    required this.unit,
    required this.highlighted,
    super.key,
  });

  final KnowledgeUnit unit;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final text = unit.rawText.trim().isNotEmpty
        ? unit.rawText.trim()
        : unit.normalizedText.trim();
    final anchorLabels = knowledgeAnchorLabels(unit.anchors);

    return Container(
      key: ValueKey('knowledge_viewer_unit_${unit.unitId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.secondaryContainer.withOpacity(0.7)
            : tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? scheme.secondary : tokens.borderSubtle,
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlighted)
            SizedBox.shrink(
              key: ValueKey('knowledge_viewer_unit_highlight_${unit.unitId}'),
            ),
          if (anchorLabels.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in anchorLabels) _AnchorPill(label: label),
              ],
            ),
            const SizedBox(height: 10),
          ],
          SelectableText(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _AnchorPill extends StatelessWidget {
  const _AnchorPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
