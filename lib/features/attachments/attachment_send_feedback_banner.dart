import 'package:flutter/material.dart';

import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

class AttachmentSendFeedbackBanner extends StatelessWidget {
  const AttachmentSendFeedbackBanner({
    required this.text,
    this.liveRegion = true,
    super.key,
  });

  final String text;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: liveRegion,
      label: text,
      child: SlSurface(
        color: colorScheme.secondaryContainer.withOpacity(0.42),
        borderColor: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.1,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
