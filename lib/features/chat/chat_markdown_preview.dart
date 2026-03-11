import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'chat_markdown_sanitizer.dart';
import 'chat_markdown_theme_presets.dart';

enum ChatMarkdownPreviewDensity {
  regular,
  compact,
}

final RegExp _escapedNewlinePattern = RegExp(r'(?<!\\)\\n');
final RegExp _escapedCarriageNewlinePattern = RegExp(r'(?<!\\)\\r\\n');
final RegExp _escapedCarriageReturnPattern = RegExp(r'(?<!\\)\\r');

final RegExp _bareSecondLoopDeepLinkPattern =
    RegExp(r'secondloop://(?:attachment|message)/[^\s<>()\]]+');
final RegExp _secondLoopTrailingPunctuationPattern = RegExp(r'[.,;:!?]+$');

bool _isInsideMarkdownLabel(String input, int start) {
  if (start <= 0) {
    return false;
  }

  final lastOpenBracket = input.lastIndexOf('[', start - 1);
  if (lastOpenBracket == -1) {
    return false;
  }

  final lastCloseBracket = input.lastIndexOf(']', start - 1);
  if (lastOpenBracket <= lastCloseBracket) {
    return false;
  }

  final textBetween = input.substring(lastOpenBracket + 1, start);
  return !textBetween.contains('\n');
}

bool _isInsideMarkdownCode(String input, int start) {
  if (start <= 0) {
    return false;
  }

  var index = 0;
  var lineStart = true;
  int? inlineDelimiter;
  int? fencedDelimiter;

  while (index < start) {
    if (input[index] == '\n') {
      lineStart = true;
      index += 1;
      continue;
    }

    if (fencedDelimiter != null) {
      if (lineStart) {
        var cursor = index;
        var leadingSpaces = 0;
        while (cursor < start && leadingSpaces < 4 && input[cursor] == ' ') {
          cursor += 1;
          leadingSpaces += 1;
        }

        final tickStart = cursor;
        while (cursor < start && input[cursor] == '`') {
          cursor += 1;
        }

        final runLength = cursor - tickStart;
        if (runLength >= fencedDelimiter) {
          final lineEnd = input.indexOf('\n', cursor);
          final end = lineEnd == -1 || lineEnd > start ? start : lineEnd;
          if (input.substring(cursor, end).trim().isEmpty) {
            fencedDelimiter = null;
            lineStart = false;
            index = cursor;
            continue;
          }
        }
      }

      lineStart = false;
      index += 1;
      continue;
    }

    if (lineStart) {
      var cursor = index;
      var leadingSpaces = 0;
      while (cursor < start && leadingSpaces < 4 && input[cursor] == ' ') {
        cursor += 1;
        leadingSpaces += 1;
      }

      final tickStart = cursor;
      while (cursor < start && input[cursor] == '`') {
        cursor += 1;
      }

      final runLength = cursor - tickStart;
      if (runLength >= 3) {
        fencedDelimiter = runLength;
        lineStart = false;
        index = cursor;
        continue;
      }
    }

    if (input[index] == '`') {
      var cursor = index;
      while (cursor < start && input[cursor] == '`') {
        cursor += 1;
      }

      final runLength = cursor - index;
      if (inlineDelimiter == null) {
        inlineDelimiter = runLength;
      } else if (runLength == inlineDelimiter) {
        inlineDelimiter = null;
      }

      lineStart = false;
      index = cursor;
      continue;
    }

    lineStart = false;
    index += 1;
  }

  return fencedDelimiter != null || inlineDelimiter != null;
}

String _linkifyBareSecondLoopDeepLinks(String input) {
  return input.replaceAllMapped(_bareSecondLoopDeepLinkPattern, (match) {
    final raw = match.group(0) ?? '';
    if (raw.isEmpty) {
      return raw;
    }

    final start = match.start;
    final end = match.end;
    final precededByMarkdownDestination =
        start >= 2 && input.substring(start - 2, start) == '](';
    final precededByOpeningBracket =
        start >= 1 && input.substring(start - 1, start) == '[';
    final insideMarkdownCode = _isInsideMarkdownCode(input, start);
    final insideMarkdownLabel = _isInsideMarkdownLabel(input, start);
    final followedByMarkdownLabel =
        end + 2 <= input.length && input.substring(end, end + 2) == '](';
    if (precededByMarkdownDestination ||
        precededByOpeningBracket ||
        insideMarkdownCode ||
        insideMarkdownLabel ||
        followedByMarkdownLabel) {
      return raw;
    }

    final href = raw.replaceFirst(_secondLoopTrailingPunctuationPattern, '');
    if (href.isEmpty) {
      return raw;
    }

    final trailing = raw.substring(href.length);
    return '[$href]($href)$trailing';
  });
}

String normalizeChatMarkdownForPreview(
  String raw, {
  bool restoreEscapedNewlines = false,
}) {
  var normalized = raw.replaceAll('\r\n', '\n').trim();

  if (restoreEscapedNewlines &&
      !normalized.contains('\n') &&
      _escapedNewlinePattern.hasMatch(normalized)) {
    normalized = normalized
        .replaceAll(_escapedCarriageNewlinePattern, '\n')
        .replaceAll(_escapedNewlinePattern, '\n')
        .replaceAll(_escapedCarriageReturnPattern, '\r');
  }

  return _linkifyBareSecondLoopDeepLinks(sanitizeChatMarkdown(normalized));
}

MarkdownStyleSheet chatMarkdownPreviewStyleSheet(
  BuildContext context, {
  ChatMarkdownThemePreset preset = ChatMarkdownThemePreset.studio,
  ChatMarkdownPreviewDensity density = ChatMarkdownPreviewDensity.regular,
  TextStyle? bodyStyle,
}) {
  final theme = Theme.of(context);
  final previewTheme = resolveChatMarkdownTheme(preset, theme);

  var styleSheet = density == ChatMarkdownPreviewDensity.compact
      ? previewTheme.buildExportStyleSheet(theme)
      : previewTheme.buildStyleSheet(theme);

  final effectiveBodyStyle = bodyStyle;
  if (effectiveBodyStyle == null) {
    return styleSheet;
  }

  styleSheet = styleSheet.copyWith(
    p: effectiveBodyStyle,
    listBullet: effectiveBodyStyle,
    tableBody: effectiveBodyStyle,
    blockquote: effectiveBodyStyle.copyWith(
      color: styleSheet.blockquote?.color,
      height: styleSheet.blockquote?.height,
      fontWeight: styleSheet.blockquote?.fontWeight,
      fontStyle: styleSheet.blockquote?.fontStyle,
    ),
  );

  return styleSheet;
}

Color chatMarkdownPreviewCanvasColor(
  BuildContext context, {
  ChatMarkdownThemePreset preset = ChatMarkdownThemePreset.studio,
}) {
  final theme = Theme.of(context);
  return resolveChatMarkdownTheme(preset, theme).canvasColor;
}

class ChatMarkdownPreviewPanel extends StatelessWidget {
  const ChatMarkdownPreviewPanel({
    required this.child,
    this.preset = ChatMarkdownThemePreset.studio,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 18),
    this.borderRadius = 14,
    super.key,
  });

  final Widget child;
  final ChatMarkdownThemePreset preset;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewTheme = resolveChatMarkdownTheme(preset, theme);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: previewTheme.panelColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: previewTheme.borderColor),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

MarkdownBody buildChatMarkdownPreviewBody(
  BuildContext context, {
  Key? key,
  required String text,
  bool selectable = false,
  bool softLineBreak = true,
  bool restoreEscapedNewlines = false,
  ChatMarkdownThemePreset preset = ChatMarkdownThemePreset.studio,
  ChatMarkdownPreviewDensity density = ChatMarkdownPreviewDensity.regular,
  TextStyle? bodyStyle,
  MarkdownTapLinkCallback? onTapLink,
}) {
  final normalized = normalizeChatMarkdownForPreview(
    text,
    restoreEscapedNewlines: restoreEscapedNewlines,
  );
  return MarkdownBody(
    key: key,
    data: normalized,
    selectable: selectable,
    softLineBreak: softLineBreak,
    styleSheet: chatMarkdownPreviewStyleSheet(
      context,
      preset: preset,
      density: density,
      bodyStyle: bodyStyle,
    ),
    onTapLink: onTapLink,
  );
}
