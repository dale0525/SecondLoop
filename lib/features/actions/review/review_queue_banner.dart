import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../ui/sl_surface.dart';
import '../../../ui/sl_tokens.dart';

class ReviewQueueBanner extends StatelessWidget {
  const ReviewQueueBanner({
    required this.count,
    required this.onTap,
    super.key,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final tokens = SlTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SlSurface(
        color: tokens.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(
            children: [
              const Icon(Icons.inbox_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t.actions.reviewQueue.banner(count: count),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
