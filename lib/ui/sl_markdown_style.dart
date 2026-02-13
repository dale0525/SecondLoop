import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'sl_tokens.dart';

MarkdownStyleSheet slMarkdownStyleSheet(
  BuildContext context, {
  TextStyle? bodyStyle,
}) {
  final theme = Theme.of(context);
  final tokens = SlTokens.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;

  final body = bodyStyle ?? theme.textTheme.bodyMedium;
  final inlineBackground = isDark
      ? Color.alphaBlend(
          colorScheme.primary.withOpacity(0.34),
          tokens.surface2,
        )
      : colorScheme.primaryContainer.withOpacity(0.72);
  final inlineForeground =
      isDark ? colorScheme.onSurface : colorScheme.onPrimaryContainer;

  final quoteBackground = isDark
      ? Color.alphaBlend(
          colorScheme.secondary.withOpacity(0.14),
          tokens.surface2,
        )
      : colorScheme.secondaryContainer.withOpacity(0.52);
  final quoteBorder = isDark
      ? colorScheme.secondary.withOpacity(0.56)
      : colorScheme.secondary.withOpacity(0.32);
  final quoteTextColor =
      isDark ? colorScheme.onSurface.withOpacity(0.94) : colorScheme.onSurface;

  final codeBlockBackground = isDark
      ? Color.alphaBlend(
          colorScheme.primary.withOpacity(0.16),
          colorScheme.surfaceVariant,
        )
      : Color.alphaBlend(
          colorScheme.primary.withOpacity(0.07),
          colorScheme.surfaceVariant,
        );
  final codeBlockBorder = isDark
      ? colorScheme.primary.withOpacity(0.4)
      : colorScheme.primary.withOpacity(0.24);

  final codeBase = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 13);

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    listBullet: body,
    blockquote: (body ?? theme.textTheme.bodyMedium)?.copyWith(
      color: quoteTextColor,
      height: 1.5,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    blockquoteDecoration: BoxDecoration(
      color: quoteBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border(
        left: BorderSide(color: quoteBorder, width: 3),
      ),
    ),
    code: codeBase.copyWith(
      color: inlineForeground,
      backgroundColor: inlineBackground,
      fontFamilyFallback: const <String>[
        'Menlo',
        'Monaco',
        'Consolas',
        'Courier New',
        'monospace',
      ],
    ),
    codeblockPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    codeblockDecoration: BoxDecoration(
      color: codeBlockBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: codeBlockBorder),
    ),
  );
}
