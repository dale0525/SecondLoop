import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

final class ChatAttachmentSendFailureChip extends StatelessWidget {
  const ChatAttachmentSendFailureChip({
    required this.failedCount,
    required this.onRetry,
    super.key,
  });

  final int failedCount;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = SlTokens.of(context);
    final countText = '$failedCount';
    return SlSurface(
      color: colorScheme.errorContainer.withOpacity(0.35),
      borderColor: colorScheme.error.withOpacity(0.35),
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: colorScheme.error,
          ),
          const SizedBox(width: 6),
          Text(
            countText,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          SlButton(
            buttonKey: const ValueKey('chat_retry_failed_attachments'),
            variant: SlButtonVariant.outline,
            onPressed: onRetry,
            child: Text(context.t.common.actions.retry),
          ),
        ],
      ),
    );
  }
}
