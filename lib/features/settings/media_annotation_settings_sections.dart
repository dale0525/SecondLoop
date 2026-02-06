import 'package:flutter/material.dart';

import '../../ui/sl_surface.dart';

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
