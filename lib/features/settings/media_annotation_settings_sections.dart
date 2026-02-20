import 'package:flutter/material.dart';

import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

Widget mediaAnnotationSectionTitle(BuildContext context, String title) {
  return Text(
    title,
    style: Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.w600),
  );
}

Widget mediaAnnotationSectionCard(List<Widget> children) {
  return SlSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i != 0) const Divider(height: 1),
          children[i],
        ],
      ],
    ),
  );
}

Widget mediaAnnotationCapabilityCard({
  required BuildContext context,
  required String title,
  required String description,
  required String statusLabel,
  required List<Widget> actions,
  Key? key,
  GlobalKey? anchorKey,
}) {
  final tokens = SlTokens.of(context);
  final colorScheme = Theme.of(context).colorScheme;

  final card = Container(
    key: key,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: tokens.borderSubtle),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SlSurface(
        padding: EdgeInsets.zero,
        child: ColoredBox(
          color: colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(description),
                    const SizedBox(height: 8),
                    Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) const Divider(height: 1),
              for (var i = 0; i < actions.length; i++) ...[
                if (i != 0) const Divider(height: 1),
                actions[i],
              ],
            ],
          ),
        ),
      ),
    ),
  );
  if (anchorKey == null) return card;
  return KeyedSubtree(key: anchorKey, child: card);
}

Widget mediaAnnotationRoutingGuideCard({
  required BuildContext context,
  required String title,
  required String pro,
  required String byok,
}) {
  Widget bullet(String text) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 6, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }

  return SlSurface(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        bullet(pro),
        const SizedBox(height: 6),
        bullet(byok),
      ],
    ),
  );
}
