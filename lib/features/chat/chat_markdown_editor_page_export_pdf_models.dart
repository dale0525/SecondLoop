part of 'chat_markdown_editor_page.dart';

class _PdfTextStyle {
  const _PdfTextStyle({
    required this.font,
    required this.boldFont,
    required this.codeFont,
    required this.brush,
    required this.strikePen,
    required this.boldPen,
    required this.lineSpacing,
    this.indent = 0,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
    this.keepAtLeastOneLine = false,
    this.keepTogether = false,
    this.drawQuoteBorder = false,
    this.parseInlineMarkdown = true,
    this.syntheticBold = false,
    this.blockBackgroundBrush,
    this.blockBorderPen,
    this.blockPaddingHorizontal = 0,
    this.blockPaddingVertical = 0,
  });

  final PdfFont font;
  final PdfFont boldFont;
  final PdfFont codeFont;
  final PdfBrush brush;
  final PdfPen strikePen;
  final PdfPen boldPen;
  final double lineSpacing;
  final double indent;
  final double topSpacing;
  final double bottomSpacing;
  final bool keepAtLeastOneLine;
  final bool keepTogether;
  final bool drawQuoteBorder;
  final bool parseInlineMarkdown;
  final bool syntheticBold;
  final PdfBrush? blockBackgroundBrush;
  final PdfPen? blockBorderPen;
  final double blockPaddingHorizontal;
  final double blockPaddingVertical;
}

class _PdfInlinePaint {
  const _PdfInlinePaint({
    required this.font,
    required this.brush,
    required this.strikePen,
    required this.boldPen,
    required this.italic,
    required this.strike,
    required this.bold,
  });

  final PdfFont font;
  final PdfBrush brush;
  final PdfPen strikePen;
  final PdfPen boldPen;
  final bool italic;
  final bool strike;
  final bool bold;

  bool matches(_PdfInlinePaint other) {
    return font == other.font &&
        brush == other.brush &&
        strikePen == other.strikePen &&
        boldPen == other.boldPen &&
        italic == other.italic &&
        strike == other.strike &&
        bold == other.bold;
  }
}

class _PdfInlineRun {
  const _PdfInlineRun({
    required this.text,
    required this.width,
    required this.paint,
  });

  final String text;
  final double width;
  final _PdfInlinePaint paint;
}

class _PdfInlineLine {
  const _PdfInlineLine({
    required this.runs,
    required this.height,
  });

  final List<_PdfInlineRun> runs;
  final double height;
}

enum _PdfMarkdownBlockType {
  heading,
  paragraph,
  quote,
  code,
  latex,
  image,
  listItem,
  horizontalRule,
}

enum _PdfMarkdownListKind {
  unordered,
  ordered,
  task,
}

class _PdfMarkdownBlock {
  const _PdfMarkdownBlock({
    required this.type,
    required this.text,
    this.level = 0,
    this.listKind,
    this.order = 1,
    this.checked = false,
    this.source,
  });

  const _PdfMarkdownBlock.heading(
    this.text, {
    required this.level,
  })  : type = _PdfMarkdownBlockType.heading,
        listKind = null,
        order = 1,
        checked = false,
        source = null;

  const _PdfMarkdownBlock.paragraph(this.text)
      : type = _PdfMarkdownBlockType.paragraph,
        level = 0,
        listKind = null,
        order = 1,
        checked = false,
        source = null;

  const _PdfMarkdownBlock.quote(this.text)
      : type = _PdfMarkdownBlockType.quote,
        level = 0,
        listKind = null,
        order = 1,
        checked = false,
        source = null;

  const _PdfMarkdownBlock.code(this.text)
      : type = _PdfMarkdownBlockType.code,
        level = 0,
        listKind = null,
        order = 1,
        checked = false,
        source = null;

  const _PdfMarkdownBlock.latex(this.text)
      : type = _PdfMarkdownBlockType.latex,
        level = 0,
        listKind = null,
        order = 1,
        checked = false,
        source = null;

  const _PdfMarkdownBlock.image({
    required this.source,
    this.text = '',
  })  : type = _PdfMarkdownBlockType.image,
        level = 0,
        listKind = null,
        order = 1,
        checked = false;

  const _PdfMarkdownBlock.listItem({
    required this.text,
    required this.level,
    required this.listKind,
    this.order = 1,
    this.checked = false,
  })  : type = _PdfMarkdownBlockType.listItem,
        source = null;

  const _PdfMarkdownBlock.horizontalRule()
      : type = _PdfMarkdownBlockType.horizontalRule,
        text = '',
        level = 0,
        listKind = null,
        order = 1,
        checked = false,
        source = null;

  final _PdfMarkdownBlockType type;
  final String text;
  final int level;
  final _PdfMarkdownListKind? listKind;
  final int order;
  final bool checked;
  final String? source;

  _PdfMarkdownBlock copyWith({
    String? text,
    String? source,
  }) {
    return _PdfMarkdownBlock(
      type: type,
      text: text ?? this.text,
      level: level,
      listKind: listKind,
      order: order,
      checked: checked,
      source: source ?? this.source,
    );
  }
}
