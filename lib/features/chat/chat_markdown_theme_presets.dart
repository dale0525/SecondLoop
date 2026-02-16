import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

enum ChatMarkdownThemePreset {
  studio,
  paper,
  ocean,
  night,
}

const List<ChatMarkdownThemePreset> kChatMarkdownThemePresets =
    <ChatMarkdownThemePreset>[
  ChatMarkdownThemePreset.studio,
  ChatMarkdownThemePreset.paper,
  ChatMarkdownThemePreset.ocean,
  ChatMarkdownThemePreset.night,
];

class ChatMarkdownPreviewTheme {
  const ChatMarkdownPreviewTheme({
    required this.id,
    required this.canvasColor,
    required this.panelColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.linkColor,
    required this.inlineCodeBackground,
    required this.inlineCodeForeground,
    required this.codeBlockBackground,
    required this.quoteBackground,
    required this.quoteBorder,
    required this.dividerColor,
  });

  final String id;
  final Color canvasColor;
  final Color panelColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedTextColor;
  final Color linkColor;
  final Color inlineCodeBackground;
  final Color inlineCodeForeground;
  final Color codeBlockBackground;
  final Color quoteBackground;
  final Color quoteBorder;
  final Color dividerColor;

  MarkdownStyleSheet buildStyleSheet(ThemeData baseTheme) {
    return _buildStyleSheet(baseTheme, compactLayout: false);
  }

  MarkdownStyleSheet buildExportStyleSheet(ThemeData baseTheme) {
    return _buildStyleSheet(baseTheme, compactLayout: true);
  }

  MarkdownStyleSheet _buildStyleSheet(
    ThemeData baseTheme, {
    required bool compactLayout,
  }) {
    final body = (baseTheme.textTheme.bodyMedium ??
            const TextStyle(fontSize: 14, height: 1.5))
        .copyWith(
      color: textColor,
      fontSize: compactLayout ? 13 : null,
      height: compactLayout ? 1.45 : 1.58,
    );

    final headingLarge = (baseTheme.textTheme.headlineSmall ??
            const TextStyle(fontSize: 25, fontWeight: FontWeight.w700))
        .copyWith(
      color: textColor,
      fontSize: compactLayout ? 21 : null,
      fontWeight: FontWeight.w700,
      height: compactLayout ? 1.3 : null,
    );

    final headingMedium = (baseTheme.textTheme.titleLarge ??
            const TextStyle(fontSize: 21, fontWeight: FontWeight.w700))
        .copyWith(
      color: textColor,
      fontSize: compactLayout ? 18 : null,
      fontWeight: FontWeight.w700,
    );

    final headingSmall = (baseTheme.textTheme.titleMedium ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))
        .copyWith(
      color: textColor,
      fontSize: compactLayout ? 16 : null,
      fontWeight: FontWeight.w600,
    );

    final codeBase = (baseTheme.textTheme.bodySmall ??
            const TextStyle(fontSize: 13, height: 1.5))
        .copyWith(
      color: inlineCodeForeground,
      fontSize: compactLayout ? 12 : null,
      fontFamilyFallback: const <String>[
        'Menlo',
        'Monaco',
        'Consolas',
        'Courier New',
        'monospace',
      ],
    );

    return MarkdownStyleSheet.fromTheme(baseTheme).copyWith(
      a: body.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
      ),
      p: body,
      h1: headingLarge,
      h2: headingMedium,
      h3: headingSmall,
      h4: body.copyWith(fontWeight: FontWeight.w700),
      h5: body.copyWith(fontWeight: FontWeight.w600),
      h6: body.copyWith(fontWeight: FontWeight.w600),
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      listBullet: body,
      tableBody: body,
      tableHead: body.copyWith(fontWeight: FontWeight.w700),
      tableBorder: TableBorder.all(color: borderColor.withOpacity(0.78)),
      blockquote: body.copyWith(color: mutedTextColor),
      blockquotePadding: compactLayout
          ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
          : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      blockquoteDecoration: BoxDecoration(
        color: quoteBackground,
        borderRadius: BorderRadius.circular(compactLayout ? 10 : 11),
        border: Border(
          left: BorderSide(color: quoteBorder, width: 3),
        ),
      ),
      code: codeBase.copyWith(
        backgroundColor: inlineCodeBackground,
      ),
      codeblockPadding:
          compactLayout ? const EdgeInsets.all(10) : const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBackground,
        borderRadius: BorderRadius.circular(compactLayout ? 10 : 12),
        border: Border.all(color: borderColor.withOpacity(0.9)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor, width: 1)),
      ),
    );
  }
}

ChatMarkdownPreviewTheme resolveChatMarkdownTheme(
  ChatMarkdownThemePreset preset,
  ThemeData baseTheme,
) {
  final scheme = baseTheme.colorScheme;
  switch (preset) {
    case ChatMarkdownThemePreset.studio:
      return ChatMarkdownPreviewTheme(
        id: 'studio',
        canvasColor:
            Color.alphaBlend(scheme.primary.withOpacity(0.04), scheme.surface),
        panelColor: Color.alphaBlend(
          scheme.surfaceTint.withOpacity(0.03),
          scheme.surface,
        ),
        borderColor: scheme.outlineVariant,
        textColor: scheme.onSurface,
        mutedTextColor: scheme.onSurfaceVariant,
        linkColor: scheme.primary,
        inlineCodeBackground: Color.alphaBlend(
          scheme.primary.withOpacity(0.16),
          scheme.surfaceVariant,
        ),
        inlineCodeForeground: scheme.onSurface,
        codeBlockBackground: Color.alphaBlend(
          scheme.primary.withOpacity(0.08),
          scheme.surfaceVariant,
        ),
        quoteBackground: Color.alphaBlend(
          scheme.secondary.withOpacity(0.13),
          scheme.surfaceVariant,
        ),
        quoteBorder: scheme.secondary.withOpacity(0.6),
        dividerColor: scheme.outlineVariant.withOpacity(0.78),
      );
    case ChatMarkdownThemePreset.paper:
      return const ChatMarkdownPreviewTheme(
        id: 'paper',
        canvasColor: Color(0xFFF8F3E8),
        panelColor: Color(0xFFFCF9F2),
        borderColor: Color(0xFFD8CDB4),
        textColor: Color(0xFF2B2620),
        mutedTextColor: Color(0xFF5A5247),
        linkColor: Color(0xFF2E5C9A),
        inlineCodeBackground: Color(0xFFE7DDC8),
        inlineCodeForeground: Color(0xFF2B2620),
        codeBlockBackground: Color(0xFFF1E8D6),
        quoteBackground: Color(0xFFEFE6D4),
        quoteBorder: Color(0xFFA07D4E),
        dividerColor: Color(0xFFC9BCA2),
      );
    case ChatMarkdownThemePreset.ocean:
      return const ChatMarkdownPreviewTheme(
        id: 'ocean',
        canvasColor: Color(0xFFE9F3FA),
        panelColor: Color(0xFFF4FAFF),
        borderColor: Color(0xFFB3CCE2),
        textColor: Color(0xFF12263A),
        mutedTextColor: Color(0xFF36566F),
        linkColor: Color(0xFF0067A3),
        inlineCodeBackground: Color(0xFFD5E6F5),
        inlineCodeForeground: Color(0xFF12263A),
        codeBlockBackground: Color(0xFFE1EDF8),
        quoteBackground: Color(0xFFDCEBFA),
        quoteBorder: Color(0xFF4D80A9),
        dividerColor: Color(0xFFB3CCE2),
      );
    case ChatMarkdownThemePreset.night:
      return const ChatMarkdownPreviewTheme(
        id: 'night',
        canvasColor: Color(0xFF121923),
        panelColor: Color(0xFF1A2433),
        borderColor: Color(0xFF2E3D54),
        textColor: Color(0xFFEAF2FF),
        mutedTextColor: Color(0xFFB4C6DE),
        linkColor: Color(0xFF6CC3FF),
        inlineCodeBackground: Color(0xFF2E3E56),
        inlineCodeForeground: Color(0xFFEAF2FF),
        codeBlockBackground: Color(0xFF243247),
        quoteBackground: Color(0xFF1E3047),
        quoteBorder: Color(0xFF5CA7D8),
        dividerColor: Color(0xFF3A4C66),
      );
  }
}
