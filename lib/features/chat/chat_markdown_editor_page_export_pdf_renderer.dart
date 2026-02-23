part of 'chat_markdown_editor_page.dart';

class _PdfMarkdownRenderer {
  _PdfMarkdownRenderer({
    required this.theme,
    Map<String, Uint8List>? latexBitmapCache,
  })  : _latexBitmapCache = latexBitmapCache ?? const <String, Uint8List>{},
        _backgroundBrush = PdfSolidBrush(_toPdfColor(theme.canvasColor)),
        _textBrush = PdfSolidBrush(_toPdfColor(theme.textColor)),
        _mutedBrush = PdfSolidBrush(_toPdfColor(theme.mutedTextColor)),
        _quoteBackgroundBrush =
            PdfSolidBrush(_toPdfColor(theme.quoteBackground)),
        _codeBackgroundBrush =
            PdfSolidBrush(_toPdfColor(theme.codeBlockBackground)),
        _dividerPen = PdfPen(_toPdfColor(theme.dividerColor), width: 0.9),
        _quotePen = PdfPen(_toPdfColor(theme.quoteBorder), width: 2.2),
        _codeBorderPen = PdfPen(
          _toPdfColor(theme.borderColor.withOpacity(0.9)),
          width: 0.9,
        ),
        _textPen = PdfPen(_toPdfColor(theme.textColor), width: 1.0),
        _mutedPen = PdfPen(_toPdfColor(theme.mutedTextColor), width: 1.0),
        _textBoldPen = PdfPen(_toPdfColor(theme.textColor), width: 0.32),
        _mutedBoldPen = PdfPen(_toPdfColor(theme.mutedTextColor), width: 0.28),
        _bodyFont = PdfCjkStandardFont(
          PdfCjkFontFamily.heiseiKakuGothicW5,
          12,
        ),
        _bodyBoldFont = PdfCjkStandardFont(
          PdfCjkFontFamily.monotypeHeiMedium,
          12,
        ),
        _quoteFont = PdfCjkStandardFont(
          PdfCjkFontFamily.heiseiKakuGothicW5,
          11.5,
        ),
        _quoteBoldFont = PdfCjkStandardFont(
          PdfCjkFontFamily.monotypeHeiMedium,
          11.5,
        ),
        _codeFont = PdfCjkStandardFont(
          PdfCjkFontFamily.heiseiKakuGothicW5,
          10.8,
        ),
        _headingFonts = <PdfFont>[
          PdfCjkStandardFont(PdfCjkFontFamily.monotypeHeiMedium, 24),
          PdfCjkStandardFont(PdfCjkFontFamily.monotypeHeiMedium, 20),
          PdfCjkStandardFont(PdfCjkFontFamily.monotypeHeiMedium, 17),
          PdfCjkStandardFont(PdfCjkFontFamily.monotypeHeiMedium, 15),
          PdfCjkStandardFont(PdfCjkFontFamily.monotypeHeiMedium, 13),
          PdfCjkStandardFont(PdfCjkFontFamily.monotypeHeiMedium, 12),
        ];

  final ChatMarkdownPreviewTheme theme;
  final Map<String, Uint8List> _latexBitmapCache;
  final PdfSolidBrush _backgroundBrush;
  final PdfSolidBrush _textBrush;
  final PdfSolidBrush _mutedBrush;
  final PdfSolidBrush _quoteBackgroundBrush;
  final PdfSolidBrush _codeBackgroundBrush;
  final PdfPen _dividerPen;
  final PdfPen _quotePen;
  final PdfPen _codeBorderPen;
  final PdfPen _textPen;
  final PdfPen _mutedPen;
  final PdfPen _textBoldPen;
  final PdfPen _mutedBoldPen;
  final PdfFont _bodyFont;
  final PdfFont _bodyBoldFont;
  final PdfFont _quoteFont;
  final PdfFont _quoteBoldFont;
  final PdfFont _codeFont;
  final List<PdfFont> _headingFonts;

  late PdfDocument _document;
  late PdfPage _currentPage;
  late double _cursorY;
  final HashSet<PdfPage> _paintedPages = HashSet<PdfPage>.identity();
  final Map<String, double> _glyphWidthCache = <String, double>{};
  final Map<String, Future<Uint8List?>> _imageBytesCache =
      <String, Future<Uint8List?>>{};

  Future<Uint8List> render({
    required List<_PdfMarkdownBlock> blocks,
    required String emptyFallback,
  }) async {
    _document = PdfDocument();
    _document.pageSettings.size = PdfPageSize.a4;
    _document.pageSettings.setMargins(0);

    _currentPage = _document.pages.add();
    _ensurePageBackground(_currentPage);
    _cursorY = _contentTop;

    final effectiveBlocks = blocks.isEmpty
        ? <_PdfMarkdownBlock>[
            _PdfMarkdownBlock.paragraph(
              _stripInlineMarkdownSyntax(emptyFallback),
            ),
          ]
        : blocks;

    for (var index = 0; index < effectiveBlocks.length; index += 1) {
      final block = effectiveBlocks[index];
      final isLast = index == effectiveBlocks.length - 1;

      switch (block.type) {
        case _PdfMarkdownBlockType.heading:
          _drawHeading(block, isLast: isLast);
          break;
        case _PdfMarkdownBlockType.paragraph:
          _drawParagraph(
            block.text,
            style: _PdfTextStyle(
              font: _bodyFont,
              boldFont: _bodyBoldFont,
              codeFont: _codeFont,
              brush: _textBrush,
              strikePen: _textPen,
              boldPen: _textBoldPen,
              lineSpacing: 3.1,
              topSpacing: _isAtTopOfPage ? 0 : 4,
              bottomSpacing: isLast ? 0 : 9,
              syntheticBold: true,
            ),
          );
          break;
        case _PdfMarkdownBlockType.quote:
          _drawParagraph(
            block.text,
            style: _PdfTextStyle(
              font: _quoteFont,
              boldFont: _quoteBoldFont,
              codeFont: _codeFont,
              brush: _mutedBrush,
              strikePen: _mutedPen,
              boldPen: _mutedBoldPen,
              lineSpacing: 3.0,
              indent: 14,
              topSpacing: _isAtTopOfPage ? 0 : 8,
              bottomSpacing: isLast ? 0 : 11,
              drawQuoteBorder: true,
              syntheticBold: true,
              blockBackgroundBrush: _quoteBackgroundBrush,
              blockPaddingHorizontal: 12,
              blockPaddingVertical: 8,
              keepTogether: true,
            ),
          );
          break;
        case _PdfMarkdownBlockType.code:
          _drawParagraph(
            block.text,
            style: _PdfTextStyle(
              font: _codeFont,
              boldFont: _codeFont,
              codeFont: _codeFont,
              brush: _textBrush,
              strikePen: _textPen,
              boldPen: _textBoldPen,
              lineSpacing: 2.2,
              topSpacing: _isAtTopOfPage ? 0 : 8,
              bottomSpacing: isLast ? 0 : 10,
              keepAtLeastOneLine: true,
              parseInlineMarkdown: false,
              blockBackgroundBrush: _codeBackgroundBrush,
              blockBorderPen: _codeBorderPen,
              blockPaddingHorizontal: 12,
              blockPaddingVertical: 10,
              keepTogether: true,
            ),
          );
          break;
        case _PdfMarkdownBlockType.latex:
          await _drawLatexBlock(block, isLast: isLast);
          break;
        case _PdfMarkdownBlockType.image:
          await _drawImageBlock(block, isLast: isLast);
          break;
        case _PdfMarkdownBlockType.listItem:
          _drawListItem(block, isLast: isLast);
          break;
        case _PdfMarkdownBlockType.horizontalRule:
          _drawHorizontalRule(isLast: isLast);
          break;
      }

      if (index % 8 == 7) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final bytes = await _document.save();
    _document.dispose();
    return Uint8List.fromList(bytes);
  }

  double get _contentTop => _kPdfPageMarginVertical;

  double _contentBottom(PdfPage page) {
    return page.size.height - _kPdfPageMarginVertical;
  }

  double _contentLeft(PdfPage page) {
    return _kPdfPageMarginHorizontal;
  }

  double _contentWidth(PdfPage page) {
    return page.size.width - (_kPdfPageMarginHorizontal * 2);
  }

  bool get _isAtTopOfPage => (_cursorY - _contentTop).abs() <= 0.5;

  void _ensurePageBackground(PdfPage page) {
    if (!_paintedPages.add(page)) return;

    final size = page.size;
    page.graphics.drawRectangle(
      brush: _backgroundBrush,
      bounds: Rect.fromLTWH(0, 0, size.width, size.height),
    );
  }

  void _startNewPage() {
    _currentPage = _document.pages.add();
    _ensurePageBackground(_currentPage);
    _cursorY = _contentTop;
  }

  void _ensureRoom(double minHeight) {
    if (_cursorY + minHeight > _contentBottom(_currentPage)) {
      _startNewPage();
    }
  }

  void _advanceWithSpacing(double spacing) {
    if (spacing <= 0) return;
    if (_cursorY + spacing > _contentBottom(_currentPage)) {
      _startNewPage();
      return;
    }
    _cursorY += spacing;
  }

  void _drawHeading(
    _PdfMarkdownBlock block, {
    required bool isLast,
  }) {
    final level = block.level.clamp(1, 6);
    final font = _headingFonts[level - 1];

    _drawParagraph(
      block.text,
      style: _PdfTextStyle(
        font: font,
        boldFont: font,
        codeFont: _codeFont,
        brush: _textBrush,
        strikePen: _textPen,
        boldPen: _textBoldPen,
        lineSpacing: level <= 2 ? 4.6 : 3.7,
        topSpacing: _isAtTopOfPage ? 0 : (level <= 2 ? 14 : 11),
        bottomSpacing: isLast ? 0 : (level <= 2 ? 10 : 8),
        keepAtLeastOneLine: true,
      ),
    );
  }

  void _drawListItem(
    _PdfMarkdownBlock block, {
    required bool isLast,
  }) {
    final level = block.level.clamp(0, 6);
    final indent = level * 16.0;

    final prefix = switch (block.listKind) {
      _PdfMarkdownListKind.ordered => '${block.order}.',
      _PdfMarkdownListKind.task => block.checked ? '[x]' : '[ ]',
      _PdfMarkdownListKind.unordered => '-',
      null => '-',
    };

    final payload =
        block.text.trim().isEmpty ? prefix : '$prefix ${block.text}';
    _drawParagraph(
      payload,
      style: _PdfTextStyle(
        font: _bodyFont,
        boldFont: _bodyBoldFont,
        codeFont: _codeFont,
        brush: _textBrush,
        strikePen: _textPen,
        boldPen: _textBoldPen,
        lineSpacing: 3.0,
        indent: indent,
        syntheticBold: true,
        topSpacing: _isAtTopOfPage ? 0 : 1,
        bottomSpacing: isLast ? 0 : 4,
      ),
    );
  }

  void _drawHorizontalRule({required bool isLast}) {
    if (!_isAtTopOfPage) {
      _advanceWithSpacing(9);
    }
    _ensureRoom(10);

    final y = _cursorY + 2;
    final x = _contentLeft(_currentPage);
    final width = _contentWidth(_currentPage);

    _currentPage.graphics.drawLine(
      _dividerPen,
      Offset(x, y),
      Offset(x + width, y),
    );
    _cursorY = y + 2;

    if (!isLast) {
      _advanceWithSpacing(8);
    }
  }

  Future<void> _drawLatexBlock(
    _PdfMarkdownBlock block, {
    required bool isLast,
  }) async {
    final expression = block.text.trim();
    final bytes = _latexBitmapCache[expression];
    if (bytes == null || bytes.isEmpty) {
      _drawParagraph(
        expression,
        style: _PdfTextStyle(
          font: _codeFont,
          boldFont: _codeFont,
          codeFont: _codeFont,
          brush: _textBrush,
          strikePen: _textPen,
          boldPen: _textBoldPen,
          lineSpacing: 2.4,
          topSpacing: _isAtTopOfPage ? 0 : 8,
          bottomSpacing: isLast ? 0 : 10,
          keepAtLeastOneLine: true,
          keepTogether: true,
          parseInlineMarkdown: false,
          blockBackgroundBrush: _codeBackgroundBrush,
          blockBorderPen: _codeBorderPen,
          blockPaddingHorizontal: 12,
          blockPaddingVertical: 10,
        ),
      );
      return;
    }

    if (!_isAtTopOfPage) {
      _advanceWithSpacing(8);
    }

    final bitmap = PdfBitmap(bytes);
    final bitmapWidth = bitmap.width.toDouble();
    final bitmapHeight = bitmap.height.toDouble();
    if (bitmapWidth <= 0 || bitmapHeight <= 0) {
      return;
    }

    final maxWidth = _contentWidth(_currentPage);
    final pageHeight = _contentBottom(_currentPage) - _contentTop;
    final maxHeight = pageHeight * 0.48;
    final scale = math.min(
      1.0,
      math.min(maxWidth / bitmapWidth, maxHeight / bitmapHeight),
    );
    final drawWidth = bitmapWidth * scale;
    final drawHeight = bitmapHeight * scale;

    _ensureRoom(drawHeight + (isLast ? 0 : 8));

    final drawX = _contentLeft(_currentPage) + (maxWidth - drawWidth) / 2;
    _currentPage.graphics.drawImage(
      bitmap,
      Rect.fromLTWH(drawX, _cursorY, drawWidth, drawHeight),
    );
    _cursorY += drawHeight;

    if (!isLast) {
      _advanceWithSpacing(8);
    }
  }

  Future<void> _drawImageBlock(
    _PdfMarkdownBlock block, {
    required bool isLast,
  }) async {
    final source = block.source?.trim() ?? '';
    if (source.isEmpty) {
      final fallback =
          block.text.trim().isEmpty ? '[Image]' : block.text.trim();
      _drawParagraph(
        fallback,
        style: _PdfTextStyle(
          font: _quoteFont,
          boldFont: _quoteBoldFont,
          codeFont: _codeFont,
          brush: _mutedBrush,
          strikePen: _mutedPen,
          boldPen: _mutedBoldPen,
          lineSpacing: 2.8,
          topSpacing: _isAtTopOfPage ? 0 : 6,
          bottomSpacing: isLast ? 0 : 8,
        ),
      );
      return;
    }

    if (!_isAtTopOfPage) {
      _advanceWithSpacing(8);
    }

    final imageBytes = await _imageBytesCache.putIfAbsent(
      source,
      () => loadMarkdownPdfImageBytes(source),
    );
    if (imageBytes == null || imageBytes.isEmpty) {
      final fallback = block.text.trim().isEmpty ? source : block.text.trim();
      _drawParagraph(
        fallback,
        style: _PdfTextStyle(
          font: _quoteFont,
          boldFont: _quoteBoldFont,
          codeFont: _codeFont,
          brush: _mutedBrush,
          strikePen: _mutedPen,
          boldPen: _mutedBoldPen,
          lineSpacing: 2.8,
          topSpacing: 0,
          bottomSpacing: isLast ? 0 : 8,
          parseInlineMarkdown: false,
        ),
      );
      return;
    }

    final bitmap = PdfBitmap(imageBytes);
    final imageWidth = bitmap.width.toDouble();
    final imageHeight = bitmap.height.toDouble();
    if (imageWidth <= 0 || imageHeight <= 0) {
      return;
    }

    final contentWidth = _contentWidth(_currentPage);
    final pageHeight = _contentBottom(_currentPage) - _contentTop;
    final maxImageHeight = pageHeight * 0.7;

    final drawScale = math.min(
      1.0,
      math.min(contentWidth / imageWidth, maxImageHeight / imageHeight),
    );
    final drawWidth = imageWidth * drawScale;
    final drawHeight = imageHeight * drawScale;

    final caption = block.text.trim();
    final captionHeight = caption.isEmpty ? 0 : (_quoteFont.height + 8);

    _ensureRoom(drawHeight + captionHeight + 4);

    final drawX = _contentLeft(_currentPage) + (contentWidth - drawWidth) / 2;
    _currentPage.graphics.drawImage(
      bitmap,
      Rect.fromLTWH(drawX, _cursorY, drawWidth, drawHeight),
    );
    _cursorY += drawHeight;

    if (caption.isNotEmpty) {
      _drawParagraph(
        caption,
        style: _PdfTextStyle(
          font: _quoteFont,
          boldFont: _quoteBoldFont,
          codeFont: _codeFont,
          brush: _mutedBrush,
          strikePen: _mutedPen,
          boldPen: _mutedBoldPen,
          lineSpacing: 2.4,
          topSpacing: 4,
          bottomSpacing: isLast ? 0 : 8,
          parseInlineMarkdown: false,
        ),
      );
    } else if (!isLast) {
      _advanceWithSpacing(8);
    }
  }

  void _drawParagraph(
    String text, {
    required _PdfTextStyle style,
  }) {
    final payload = text.trimRight();
    if (payload.isEmpty) return;

    if (!_isAtTopOfPage) {
      _advanceWithSpacing(style.topSpacing);
    }

    final baseX = (_contentLeft(_currentPage) + style.indent).toDouble();
    final baseWidth =
        math.max(72.0, _contentWidth(_currentPage) - style.indent).toDouble();

    final spans = style.parseInlineMarkdown
        ? _parsePdfInlineMarkdownSpans(payload)
        : <_PdfInlineSpan>[
            _PdfInlineSpan(
              payload,
              bold: false,
              italic: false,
              strike: false,
              code: false,
            ),
          ];

    List<_PdfInlineLine> layoutLines({required double horizontalPadding}) {
      final lineWidth = math.max(48.0, baseWidth - horizontalPadding * 2);
      return _layoutInlineLines(
        spans,
        style: style,
        maxWidth: lineWidth,
      );
    }

    var blockPaddingHorizontal = style.blockPaddingHorizontal;
    var blockPaddingVertical = style.blockPaddingVertical;
    var drawBlockDecoration = style.blockBackgroundBrush != null;

    var lines = layoutLines(horizontalPadding: blockPaddingHorizontal);
    if (lines.isEmpty) {
      return;
    }

    double linesHeight() {
      return lines.fold<double>(
        0,
        (sum, line) => sum + line.height,
      );
    }

    var textHeight = linesHeight();
    var blockHeight = textHeight + blockPaddingVertical * 2;
    final pageContentHeight = _contentBottom(_currentPage) - _contentTop;

    if (drawBlockDecoration && blockHeight > pageContentHeight) {
      drawBlockDecoration = false;
      blockPaddingHorizontal = 0;
      blockPaddingVertical = 0;
      lines = layoutLines(horizontalPadding: 0);
      if (lines.isEmpty) {
        return;
      }
      textHeight = linesHeight();
      blockHeight = textHeight;
    }

    if (!drawBlockDecoration) {
      blockPaddingHorizontal = 0;
      blockPaddingVertical = 0;
      blockHeight = textHeight;
    }

    if (style.keepTogether) {
      final blockRequestHeight = blockHeight + style.bottomSpacing + 2;
      if (blockRequestHeight <= pageContentHeight) {
        _ensureRoom(blockRequestHeight);
      }
    } else if (style.keepAtLeastOneLine) {
      _ensureRoom(lines.first.height + blockPaddingVertical * 2 + 2);
    }

    final textX = baseX + blockPaddingHorizontal;

    if (drawBlockDecoration) {
      _currentPage.graphics.drawRectangle(
        brush: style.blockBackgroundBrush,
        pen: style.blockBorderPen,
        bounds: Rect.fromLTWH(baseX, _cursorY, baseWidth, blockHeight),
      );
      _cursorY += blockPaddingVertical;
    }

    for (final line in lines) {
      _ensureRoom(line.height + 1);
      final y = _cursorY;
      var drawX = textX;

      if (style.drawQuoteBorder) {
        final minX = _contentLeft(_currentPage) + 1;
        final maxX =
            _contentLeft(_currentPage) + _contentWidth(_currentPage) - 1;
        final borderX = (textX - 8).clamp(minX, maxX).toDouble();
        _currentPage.graphics.drawLine(
          _quotePen,
          Offset(borderX, y),
          Offset(borderX, y + line.height),
        );
      }

      for (final run in line.runs) {
        _drawInlineRun(
          _currentPage.graphics,
          x: drawX,
          y: y,
          lineHeight: line.height,
          run: run,
        );
        drawX += run.width;
      }

      _cursorY += line.height;
    }

    if (drawBlockDecoration) {
      _cursorY += blockPaddingVertical;
    }

    _advanceWithSpacing(style.bottomSpacing);
  }

  List<_PdfInlineLine> _layoutInlineLines(
    List<_PdfInlineSpan> spans, {
    required _PdfTextStyle style,
    required double maxWidth,
  }) {
    final lines = <_PdfInlineLine>[];
    final lineRuns = <_PdfInlineRun>[];
    var lineWidth = 0.0;
    var lineHeight = style.font.height + style.lineSpacing;

    _PdfInlinePaint? currentPaint;
    StringBuffer? currentBuffer;
    var currentRunWidth = 0.0;

    void flushRun() {
      if (currentPaint == null ||
          currentBuffer == null ||
          currentBuffer!.isEmpty) {
        return;
      }
      lineRuns.add(
        _PdfInlineRun(
          text: currentBuffer!.toString(),
          width: currentRunWidth,
          paint: currentPaint!,
        ),
      );
      currentPaint = null;
      currentBuffer = null;
      currentRunWidth = 0;
    }

    void flushLine({required bool force}) {
      flushRun();
      if (lineRuns.isEmpty && !force) {
        return;
      }
      lines.add(
        _PdfInlineLine(
          runs: List<_PdfInlineRun>.from(lineRuns),
          height: lineHeight,
        ),
      );
      lineRuns.clear();
      lineWidth = 0;
      lineHeight = style.font.height + style.lineSpacing;
    }

    for (final span in spans) {
      final paint = _resolveInlinePaint(style, span);
      for (final rune in span.text.runes) {
        final glyph = String.fromCharCode(rune);
        if (glyph == '\n') {
          flushLine(force: true);
          continue;
        }

        final glyphWidth = _measureGlyphWidth(
          paint.font,
          glyph,
          italic: paint.italic,
        );

        if (lineWidth + glyphWidth > maxWidth && lineWidth > 0) {
          flushLine(force: false);
        }

        if (currentPaint == null || !currentPaint!.matches(paint)) {
          flushRun();
          currentPaint = paint;
          currentBuffer = StringBuffer();
        }

        currentBuffer!.write(glyph);
        currentRunWidth += glyphWidth;
        lineWidth += glyphWidth;
        lineHeight =
            math.max(lineHeight, paint.font.height + style.lineSpacing);
      }
    }

    flushLine(force: false);
    return lines;
  }

  _PdfInlinePaint _resolveInlinePaint(
    _PdfTextStyle style,
    _PdfInlineSpan span,
  ) {
    final isCode = span.code;
    final isBold = span.bold && !isCode;
    final isItalic = span.italic && !isCode;
    final isStrike = span.strike && !isCode;
    final useSyntheticBold = isBold && style.syntheticBold;

    return _PdfInlinePaint(
      font: isCode
          ? style.codeFont
          : (useSyntheticBold
              ? style.font
              : (isBold ? style.boldFont : style.font)),
      brush: style.brush,
      strikePen: style.strikePen,
      boldPen: style.boldPen,
      italic: isItalic,
      strike: isStrike,
      bold: useSyntheticBold,
    );
  }

  void _drawInlineRun(
    PdfGraphics graphics, {
    required double x,
    required double y,
    required double lineHeight,
    required _PdfInlineRun run,
  }) {
    if (run.text.isEmpty || run.width <= 0) return;

    final boldPen = run.paint.bold ? run.paint.boldPen : null;

    if (run.paint.italic) {
      final state = graphics.save();
      graphics.translateTransform(x, y);
      graphics.skewTransform(0, -9);
      graphics.drawString(
        run.text,
        run.paint.font,
        brush: run.paint.brush,
        pen: boldPen,
        bounds: Rect.fromLTWH(0, 0, run.width + 1.2, lineHeight),
      );
      graphics.restore(state);
    } else {
      graphics.drawString(
        run.text,
        run.paint.font,
        brush: run.paint.brush,
        pen: boldPen,
        bounds: Rect.fromLTWH(x, y, run.width + 0.6, lineHeight),
      );
    }

    if (run.paint.strike) {
      final strikeY = y + lineHeight * 0.56;
      graphics.drawLine(
        run.paint.strikePen,
        Offset(x, strikeY),
        Offset(x + run.width, strikeY),
      );
    }
  }

  double _measureGlyphWidth(
    PdfFont font,
    String glyph, {
    required bool italic,
  }) {
    final key = '${font.hashCode}:${italic ? 1 : 0}:$glyph';
    return _glyphWidthCache.putIfAbsent(key, () {
      final measured = font.measureString(glyph).width;
      final safeWidth = measured > 0 ? measured : font.size * 0.58;
      return italic ? safeWidth * 1.01 : safeWidth;
    });
  }
}
