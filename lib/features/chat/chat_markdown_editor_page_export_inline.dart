part of 'chat_markdown_editor_page.dart';

List<_PdfMarkdownBlock> _parseMarkdownBlocks(String markdown) {
  final normalized =
      markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();

  if (normalized.isEmpty) {
    return const <_PdfMarkdownBlock>[];
  }

  final lines = normalized.split('\n');
  final blocks = <_PdfMarkdownBlock>[];
  var index = 0;

  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      index += 1;
      continue;
    }

    final headingMatch = _kPdfHeadingPattern.firstMatch(line);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length.clamp(1, 6);
      final headingText = _stripInlineMarkdownSyntax(
        headingMatch.group(2) ?? '',
        stripEmphasis: false,
      );
      if (headingText.isNotEmpty) {
        blocks.add(_PdfMarkdownBlock.heading(headingText, level: level));
      }
      index += 1;
      continue;
    }

    final fenceMatch = _kPdfFencedCodePattern.firstMatch(line);
    if (fenceMatch != null) {
      final consumed = _consumeFencedCodeBlock(
        lines,
        startIndex: index,
        openingFence: fenceMatch.group(1)!,
      );
      if (consumed.text.isNotEmpty) {
        blocks.add(_PdfMarkdownBlock.code(consumed.text));
      }
      index = consumed.nextIndex;
      continue;
    }

    if (_kPdfHorizontalRulePattern.hasMatch(line.trim())) {
      blocks.add(const _PdfMarkdownBlock.horizontalRule());
      index += 1;
      continue;
    }

    if (_kPdfQuotePattern.hasMatch(line)) {
      final consumed = _consumeQuoteBlock(lines, startIndex: index);
      if (consumed.text.isNotEmpty) {
        blocks.add(_PdfMarkdownBlock.quote(consumed.text));
      }
      index = consumed.nextIndex;
      continue;
    }

    if (_isListStarterLine(line)) {
      final consumed = _consumeListBlock(lines, startIndex: index);
      blocks.addAll(consumed.blocks);
      index = consumed.nextIndex;
      continue;
    }

    final consumed = _consumeParagraphBlock(lines, startIndex: index);
    if (consumed.text.isNotEmpty) {
      blocks.add(_PdfMarkdownBlock.paragraph(consumed.text));
    }
    index = consumed.nextIndex;
  }

  return blocks;
}

({int nextIndex, String text}) _consumeFencedCodeBlock(
  List<String> lines, {
  required int startIndex,
  required String openingFence,
}) {
  final collected = <String>[];
  var index = startIndex + 1;

  while (index < lines.length) {
    final line = lines[index];
    if (_isFencedCodeClosingLine(line, openingFence)) {
      index += 1;
      break;
    }
    collected.add(line);
    index += 1;
  }

  return (nextIndex: index, text: collected.join('\n').trimRight());
}

({int nextIndex, String text}) _consumeQuoteBlock(
  List<String> lines, {
  required int startIndex,
}) {
  final collected = <String>[];
  var index = startIndex;

  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      final hasMoreQuote = index + 1 < lines.length &&
          _kPdfQuotePattern.hasMatch(lines[index + 1]);
      if (!hasMoreQuote) break;
      collected.add('');
      index += 1;
      continue;
    }

    final match = _kPdfQuotePattern.firstMatch(line);
    if (match == null) break;
    collected.add(match.group(1) ?? '');
    index += 1;
  }

  final text = _stripInlineMarkdownSyntax(
    collected.join('\n'),
    collapseWhitespace: false,
    stripEmphasis: false,
  );
  return (nextIndex: index, text: text);
}

({int nextIndex, List<_PdfMarkdownBlock> blocks}) _consumeListBlock(
  List<String> lines, {
  required int startIndex,
}) {
  final blocks = <_PdfMarkdownBlock>[];
  var index = startIndex;

  while (index < lines.length) {
    final line = lines[index];

    if (line.trim().isEmpty) {
      final hasMoreList =
          index + 1 < lines.length && _isListStarterLine(lines[index + 1]);
      if (!hasMoreList) break;
      index += 1;
      continue;
    }

    final taskMatch = _kPdfTaskListPattern.firstMatch(line);
    if (taskMatch != null) {
      final content = _stripInlineMarkdownSyntax(
        taskMatch.group(4) ?? '',
        stripEmphasis: false,
      );
      blocks.add(
        _PdfMarkdownBlock.listItem(
          text: content,
          level: _indentLevelFromLeadingSpace(taskMatch.group(1) ?? ''),
          listKind: _PdfMarkdownListKind.task,
          checked: (taskMatch.group(3) ?? ' ').toLowerCase() == 'x',
        ),
      );
      index += 1;
      continue;
    }

    final orderedMatch = _kPdfOrderedListPattern.firstMatch(line);
    if (orderedMatch != null) {
      final content = _stripInlineMarkdownSyntax(
        orderedMatch.group(3) ?? '',
        stripEmphasis: false,
      );
      final order = int.tryParse(orderedMatch.group(2) ?? '1') ?? 1;
      blocks.add(
        _PdfMarkdownBlock.listItem(
          text: content,
          level: _indentLevelFromLeadingSpace(orderedMatch.group(1) ?? ''),
          listKind: _PdfMarkdownListKind.ordered,
          order: order,
        ),
      );
      index += 1;
      continue;
    }

    final unorderedMatch = _kPdfUnorderedListPattern.firstMatch(line);
    if (unorderedMatch != null) {
      final content = _stripInlineMarkdownSyntax(
        unorderedMatch.group(3) ?? '',
        stripEmphasis: false,
      );
      blocks.add(
        _PdfMarkdownBlock.listItem(
          text: content,
          level: _indentLevelFromLeadingSpace(unorderedMatch.group(1) ?? ''),
          listKind: _PdfMarkdownListKind.unordered,
        ),
      );
      index += 1;
      continue;
    }

    if (blocks.isNotEmpty && _kPdfListContinuationPattern.hasMatch(line)) {
      final continuation = _stripInlineMarkdownSyntax(
        line.trimLeft(),
        stripEmphasis: false,
      );
      if (continuation.isNotEmpty) {
        final previous = blocks.removeLast();
        blocks.add(previous.copyWith(text: '${previous.text}\n$continuation'));
      }
      index += 1;
      continue;
    }

    break;
  }

  return (nextIndex: index, blocks: blocks);
}

({int nextIndex, String text}) _consumeParagraphBlock(
  List<String> lines, {
  required int startIndex,
}) {
  final collected = <String>[];
  var index = startIndex;

  while (index < lines.length) {
    final line = lines[index];
    if (line.trim().isEmpty) break;

    final isBlockBoundary = _kPdfHeadingPattern.hasMatch(line) ||
        _kPdfFencedCodePattern.hasMatch(line) ||
        _kPdfHorizontalRulePattern.hasMatch(line.trim()) ||
        _kPdfQuotePattern.hasMatch(line) ||
        _isListStarterLine(line);
    if (isBlockBoundary && index != startIndex) {
      break;
    }

    collected.add(line.trim());
    index += 1;
  }

  final paragraph = _stripInlineMarkdownSyntax(
    collected.join(' '),
    stripEmphasis: false,
  );
  return (nextIndex: index, text: paragraph);
}

bool _isListStarterLine(String line) {
  return _kPdfTaskListPattern.hasMatch(line) ||
      _kPdfOrderedListPattern.hasMatch(line) ||
      _kPdfUnorderedListPattern.hasMatch(line);
}

bool _isFencedCodeClosingLine(String line, String openingFence) {
  final trimmed = line.trimLeft();
  if (openingFence.startsWith('```')) {
    return trimmed.startsWith('```');
  }
  return trimmed.startsWith('~~~');
}

int _indentLevelFromLeadingSpace(String value) {
  if (value.isEmpty) return 0;
  final expanded = value.replaceAll('\t', '  ');
  return (expanded.length ~/ 2).clamp(0, 6);
}

class _PdfInlineSpan {
  const _PdfInlineSpan(
    this.text, {
    required this.bold,
    required this.italic,
    required this.strike,
    required this.code,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;
}

List<_PdfInlineSpan> _parsePdfInlineMarkdownSpans(String input) {
  if (input.isEmpty) return const <_PdfInlineSpan>[];

  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubWeb,
    encodeHtml: false,
  );

  final spans = <_PdfInlineSpan>[];
  final lines = input.split('\n');

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final line = lines[lineIndex];
    if (line.isNotEmpty) {
      final nodes = document.parseInline(line);
      _appendPdfInlineSpansFromMarkdownNodes(
        nodes,
        spans: spans,
        style: const _PdfInlineParseStyle(),
      );
    }

    if (lineIndex != lines.length - 1) {
      _appendPdfInlineSpan(
        spans,
        '\n',
        style: const _PdfInlineParseStyle(),
      );
    }
  }

  return spans;
}

void _appendPdfInlineSpansFromMarkdownNodes(
  List<md.Node> nodes, {
  required List<_PdfInlineSpan> spans,
  required _PdfInlineParseStyle style,
}) {
  for (final node in nodes) {
    if (node is md.Text) {
      _appendPdfInlineSpan(spans, node.text, style: style);
      continue;
    }

    if (node is! md.Element) {
      _appendPdfInlineSpan(spans, node.textContent, style: style);
      continue;
    }

    if (node.tag == 'br') {
      _appendPdfInlineSpan(
        spans,
        '\n',
        style: const _PdfInlineParseStyle(),
      );
      continue;
    }

    final nextStyle = switch (node.tag) {
      'strong' => style.copyWith(bold: true),
      'em' => style.copyWith(italic: true),
      'del' => style.copyWith(strike: true),
      'code' => style.copyWith(code: true),
      _ => style,
    };

    final children = node.children;
    if (children == null || children.isEmpty) {
      _appendPdfInlineSpan(spans, node.textContent, style: nextStyle);
      continue;
    }

    _appendPdfInlineSpansFromMarkdownNodes(
      children,
      spans: spans,
      style: nextStyle,
    );
  }
}

void _appendPdfInlineSpan(
  List<_PdfInlineSpan> spans,
  String text, {
  required _PdfInlineParseStyle style,
}) {
  if (text.isEmpty) return;

  if (spans.isNotEmpty) {
    final previous = spans.last;
    if (previous.bold == style.bold &&
        previous.italic == style.italic &&
        previous.strike == style.strike &&
        previous.code == style.code) {
      spans[spans.length - 1] = _PdfInlineSpan(
        previous.text + text,
        bold: previous.bold,
        italic: previous.italic,
        strike: previous.strike,
        code: previous.code,
      );
      return;
    }
  }

  spans.add(
    _PdfInlineSpan(
      text,
      bold: style.bold,
      italic: style.italic,
      strike: style.strike,
      code: style.code,
    ),
  );
}

class _PdfInlineParseStyle {
  const _PdfInlineParseStyle({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
  });

  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;

  _PdfInlineParseStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strike,
    bool? code,
  }) {
    return _PdfInlineParseStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strike: strike ?? this.strike,
      code: code ?? this.code,
    );
  }
}

String _stripInlineMarkdownSyntax(
  String input, {
  bool collapseWhitespace = true,
  bool stripEmphasis = true,
}) {
  var text = input;

  for (final replacement in <({RegExp pattern, int group})>[
    (pattern: RegExp(r'!\[([^\]]*)\]\([^)]*\)'), group: 1),
    (pattern: RegExp(r'\[([^\]]+)\]\([^)]*\)'), group: 1),
    (pattern: RegExp(r'`([^`]*)`'), group: 1),
    (pattern: RegExp(r'\\([\\`*_{}\[\]()#+\-.!~>])'), group: 1),
  ]) {
    text = _replaceWithCaptureGroup(
      text,
      replacement.pattern,
      group: replacement.group,
    );
  }

  if (stripEmphasis) {
    for (final replacement in <({RegExp pattern, int group})>[
      (pattern: RegExp(r'(\*\*\*|___)(.+?)\1'), group: 2),
      (pattern: RegExp(r'(\*\*|__)(.+?)\1'), group: 2),
      (pattern: RegExp(r'(\*|_)(.+?)\1'), group: 2),
      (pattern: RegExp(r'~~(.+?)~~'), group: 1),
    ]) {
      text = _replaceWithCaptureGroup(
        text,
        replacement.pattern,
        group: replacement.group,
      );
    }
  }

  text = text.replaceAll(RegExp(r'<[^>]+>'), '');

  if (collapseWhitespace) {
    text = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), '\n');
  }

  return text.trim();
}

String _replaceWithCaptureGroup(
  String input,
  RegExp pattern, {
  required int group,
}) =>
    input.replaceAllMapped(pattern, (match) => match.group(group) ?? '');

PdfColor _toPdfColor(Color color, {int alpha = 255}) {
  return PdfColor(color.red, color.green, color.blue, alpha);
}
