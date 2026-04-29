import 'package:flutter/material.dart';

import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

class SecretaryReviewSection extends StatelessWidget {
  const SecretaryReviewSection({
    required this.title,
    required this.count,
    required this.children,
    super.key,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SlSurface(
      color: tokens.surface2,
      borderColor: tokens.borderSubtle,
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (count > 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(
              'Nothing to review.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}
