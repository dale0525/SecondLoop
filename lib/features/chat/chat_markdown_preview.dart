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

bool _isInsideMarkdownLabel(
  String input,
  int start,
  List<_MarkdownCodeRange> codeRanges,
) {
  if (start <= 0) {
    return false;
  }

  final lastOpenBracket = input.lastIndexOf('[', start - 1);
  if (lastOpenBracket == -1) {
    return false;
  }

  final bracketInsideCode =
      codeRanges.any((range) => range.contains(lastOpenBracket));
  if (bracketInsideCode) {
    return false;
  }

  final lastCloseBracket = input.lastIndexOf(']', start - 1);
  if (lastOpenBracket <= lastCloseBracket) {
    return false;
  }

  final textBetween = input.substring(lastOpenBracket + 1, start);
  return !textBetween.contains('\n');
}

class _MarkdownCodeRange {
  const _MarkdownCodeRange(this.start, this.end);

  final int start;
  final int end;

  bool contains(int offset) => offset >= start && offset < end;
}

List<_MarkdownCodeRange> _collectMarkdownCodeRanges(String input) {
  final ranges = <_MarkdownCodeRange>[];
  var index = 0;
  var lineStart = true;
  int? inlineDelimiter;
  int? inlineStart;
  int? fencedDelimiter;
  String? fencedMarker;
  int? fencedStart;

  while (index < input.length) {
    if (lineStart) {
      final currentLineStart = index;
      final lineEndIndex = input.indexOf('\n', currentLineStart);
      final lineEnd = lineEndIndex == -1 ? input.length : lineEndIndex;

      var contentStart = currentLineStart;
      var leadingSpaces = 0;
      while (contentStart < lineEnd &&
          leadingSpaces < 4 &&
          input[contentStart] == ' ') {
        contentStart += 1;
        leadingSpaces += 1;
      }

      final lineContent = input.substring(contentStart, lineEnd);
      final lineIsBlank = lineContent.trim().isEmpty;
      final nextIndex = lineEndIndex == -1 ? input.length : lineEndIndex + 1;

      if (fencedDelimiter != null) {
        if (leadingSpaces <= 3 &&
            contentStart < lineEnd &&
            input[contentStart] == fencedMarker) {
          var cursor = contentStart;
          while (cursor < lineEnd && input[cursor] == fencedMarker) {
            cursor += 1;
          }

          final runLength = cursor - contentStart;
          if (runLength >= fencedDelimiter &&
              input.substring(cursor, lineEnd).trim().isEmpty) {
            ranges.add(_MarkdownCodeRange(fencedStart!, lineEnd));
            fencedDelimiter = null;
            fencedMarker = null;
            fencedStart = null;
          }
        }

        index = nextIndex;
        lineStart = true;
        continue;
      }

      if (leadingSpaces <= 3 && contentStart < lineEnd) {
        final marker = input[contentStart];
        if (marker == '`' || marker == '~') {
          var cursor = contentStart;
          while (cursor < lineEnd && input[cursor] == marker) {
            cursor += 1;
          }

          final runLength = cursor - contentStart;
          if (runLength >= 3) {
            fencedDelimiter = runLength;
            fencedMarker = marker;
            fencedStart = currentLineStart;
            index = nextIndex;
            lineStart = true;
            continue;
          }
        }
      }

      if (lineIsBlank) {
        inlineDelimiter = null;
        inlineStart = null;
        index = nextIndex;
        lineStart = true;
        continue;
      }

      lineStart = false;
    }

    if (input[index] == '\n') {
      lineStart = true;
      index += 1;
      continue;
    }

    if (input[index] == '`') {
      var cursor = index;
      while (cursor < input.length && input[cursor] == '`') {
        cursor += 1;
      }

      final runLength = cursor - index;
      if (inlineDelimiter == null) {
        inlineDelimiter = runLength;
        inlineStart = index;
      } else if (runLength == inlineDelimiter) {
        ranges.add(_MarkdownCodeRange(inlineStart!, cursor));
        inlineDelimiter = null;
        inlineStart = null;
      }

      index = cursor;
      continue;
    }

    index += 1;
  }

  if (fencedStart != null) {
    ranges.add(_MarkdownCodeRange(fencedStart, input.length));
  }

  return ranges;
}

String _linkifyBareSecondLoopDeepLinks(String input) {
  final codeRanges = _collectMarkdownCodeRanges(input);
  var codeRangeIndex = 0;

  bool insideMarkdownCode(int offset) {
    while (codeRangeIndex < codeRanges.length &&
        codeRanges[codeRangeIndex].end <= offset) {
      codeRangeIndex += 1;
    }
    return codeRangeIndex < codeRanges.length &&
        codeRanges[codeRangeIndex].contains(offset);
  }

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
    final insideCode = insideMarkdownCode(start);
    final insideMarkdownLabel =
        _isInsideMarkdownLabel(input, start, codeRanges);
    final followedByMarkdownLabel =
        end + 2 <= input.length && input.substring(end, end + 2) == '](';
    if (precededByMarkdownDestination ||
        precededByOpeningBracket ||
        insideCode ||
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
