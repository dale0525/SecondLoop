import 'package:flutter/material.dart';

import 'settings_ui.dart';

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
  return SettingsSection(children: children);
}

Widget mediaAnnotationCapabilityCard({
  required BuildContext context,
  required String title,
  required String description,
  required String statusLabel,
  required List<Widget> actions,
  Key? key,
  GlobalKey? anchorKey,
  bool highlighted = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
      WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  final card = AnimatedContainer(
    key: key,
    duration:
        disableAnimations ? Duration.zero : const Duration(milliseconds: 300),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.all(highlighted ? 2 : 0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: highlighted ? Border.all(color: colorScheme.primary) : null,
      boxShadow: highlighted
          ? [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.18),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    ),
    child: SettingsSection(
      title: title,
      subtitle: description,
      trailing: SettingsStatusBadge(label: statusLabel),
      children: actions,
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

  return SettingsSection(
    title: title,
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bullet(pro),
            const SizedBox(height: 6),
            bullet(byok),
          ],
        ),
      ),
    ],
  );
}
