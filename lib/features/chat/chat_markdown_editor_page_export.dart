part of 'chat_markdown_editor_page.dart';

const double _kPdfPageMarginHorizontal = 54;
const double _kPdfPageMarginVertical = 48;

final RegExp _kPdfHeadingPattern = RegExp(
  r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$',
);
final RegExp _kPdfFencedCodePattern = RegExp(r'^\s{0,3}(```|~~~)');
final RegExp _kPdfHorizontalRulePattern = RegExp(r'^\s{0,3}(?:[-*_]\s*){3,}$');
final RegExp _kPdfQuotePattern = RegExp(r'^\s{0,3}>\s?(.*)$');
final RegExp _kPdfTaskListPattern =
    RegExp(r'^(\s*)([-+*])\s+\[( |x|X)\]\s*(.*)$');
final RegExp _kPdfOrderedListPattern = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final RegExp _kPdfUnorderedListPattern = RegExp(r'^(\s*)([-+*])\s+(.*)$');
final RegExp _kPdfListContinuationPattern = RegExp(r'^\s{2,}\S');
final RegExp _kPdfLatexBlockOpeningPattern = RegExp(r'^\s*\$\$(.*)$');
final RegExp _kPdfLatexBlockClosingPattern = RegExp(r'^(.*?)\$\$\s*$');
final RegExp _kPdfImageLinePattern = RegExp(
  r'^\s*!\[([^\]]*)\]\((<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\)\s*$',
);

mixin _ChatMarkdownEditorExportMixin on State<ChatMarkdownEditorPage> {
  bool get _exporting;
  set _exporting(bool value);

  TextEditingController get _controller;
  ChatMarkdownCompactPane get _compactPane;
  set _compactPane(ChatMarkdownCompactPane value);

  ScrollController get _previewScrollController;
  GlobalKey get _previewRepaintBoundaryKey;
  FocusNode get _editorFocusNode;
  bool get _exportRenderMode;
  set _exportRenderMode(bool value);
  ChatMarkdownThemePreset get _themePreset;
  bool _isWideLayout(BuildContext context);

  Future<void> _handleExportAction(_MarkdownExportAction action) async {
    switch (action) {
      case _MarkdownExportAction.png:
        await _exportFile(_MarkdownExportFormat.png);
        return;
      case _MarkdownExportAction.pdf:
        await _exportFile(_MarkdownExportFormat.pdf);
        return;
      case _MarkdownExportAction.copyToClipboard:
        await _copyToClipboard();
        return;
    }
  }

  Future<void> _exportFile(_MarkdownExportFormat format) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final bytes = switch (format) {
        _MarkdownExportFormat.png => await _capturePreviewAsPngBytes(),
        _MarkdownExportFormat.pdf => await _buildPdfBytes(),
      };
      final file = await _materializeMarkdownExportFile(
        format: format,
        bytes: bytes,
        sourceMarkdown: _controller.text,
      );

      if (_shouldShareMarkdownExportedFile()) {
        await Share.shareXFiles(
          <XFile>[
            XFile(
              file.path,
              mimeType: format == _MarkdownExportFormat.png
                  ? 'image/png'
                  : 'application/pdf',
            ),
          ],
        );
      }

      if (!mounted) return;
      final formatLabel = format == _MarkdownExportFormat.png ? 'PNG' : 'PDF';
      final doneMessage =
          '${context.t.chat.markdownEditor.exportDone(format: formatLabel)}\n'
          '${context.t.chat.markdownEditor.exportSavedPath(path: file.path)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(doneMessage),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.chat.markdownEditor.exportFailed(error: '$error'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _copyToClipboard() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final previewTheme =
          resolveChatMarkdownTheme(_themePreset, Theme.of(context));
      final plainText = buildChatMarkdownClipboardPlainText(
        _controller.text,
        emptyFallback: context.t.chat.markdownEditor.emptyPreview,
      );
      final html = buildChatMarkdownClipboardHtml(
        markdown: _controller.text,
        theme: previewTheme,
        emptyFallback: context.t.chat.markdownEditor.emptyPreview,
      );

      try {
        final clipboard = SystemClipboard.instance;
        if (clipboard != null) {
          final item = DataWriterItem();
          item.add(Formats.htmlText(html));
          item.add(Formats.plainText(plainText));
          await clipboard.write(<DataWriterItem>[item]);
        } else {
          await Clipboard.setData(ClipboardData(text: plainText));
        }
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: plainText));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.markdownEditor.exportCopied),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.chat.markdownEditor.exportFailed(error: '$error'),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<Uint8List> _capturePreviewAsPngBytes() async {
    final isWideLayout = _isWideLayout(context);
    final switchedPane =
        !isWideLayout && _compactPane == ChatMarkdownCompactPane.editor;
    final previousRenderMode = _exportRenderMode;

    setState(() {
      _exportRenderMode = true;
      if (switchedPane) {
        _compactPane = ChatMarkdownCompactPane.preview;
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await WidgetsBinding.instance.endOfFrame;

    try {
      if (_previewScrollController.hasClients) {
        _previewScrollController.jumpTo(0);
      }

      final renderObject = await _waitForPreviewRenderBoundary();
      final pixelRatio = resolveMarkdownPreviewExportPixelRatio(
        logicalWidth: renderObject.size.width,
        logicalHeight: renderObject.size.height,
        devicePixelRatio:
            ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
      );

      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Failed to encode preview as PNG');
      }
      return byteData.buffer.asUint8List();
    } finally {
      if (mounted) {
        setState(() {
          _exportRenderMode = previousRenderMode;
          if (switchedPane) {
            _compactPane = ChatMarkdownCompactPane.editor;
          }
        });
        if (switchedPane) {
          _editorFocusNode.requestFocus();
        }
      }
    }
  }

  Future<RenderRepaintBoundary> _waitForPreviewRenderBoundary() async {
    for (var attempts = 0; attempts < 8; attempts += 1) {
      await WidgetsBinding.instance.endOfFrame;
      final renderObject =
          _previewRepaintBoundaryKey.currentContext?.findRenderObject();
      if (renderObject is RenderRepaintBoundary) {
        return renderObject;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    throw StateError('Preview is not ready for export');
  }

  Future<Uint8List> _buildPdfBytes() async {
    try {
      return await _buildPdfFromPreviewCapture();
    } catch (_) {
      return _buildPdfWithVectorRenderer();
    }
  }

  Future<Uint8List> _buildPdfFromPreviewCapture() async {
    final isWideLayout = _isWideLayout(context);
    final switchedPane =
        !isWideLayout && _compactPane == ChatMarkdownCompactPane.editor;
    final previousRenderMode = _exportRenderMode;

    setState(() {
      _exportRenderMode = true;
      if (switchedPane) {
        _compactPane = ChatMarkdownCompactPane.preview;
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    try {
      if (_previewScrollController.hasClients) {
        _previewScrollController.jumpTo(0);
      }

      final renderObject = await _waitForPreviewRenderBoundary();
      // ignore: invalid_use_of_protected_member
      final renderLayer = renderObject.layer;
      if (renderLayer is! OffsetLayer) {
        throw StateError('Preview render layer is not ready for PDF export');
      }

      const pageSize = PdfPageSize.a4;
      final contentBounds = buildPdfPreviewContentRect(
        Size(pageSize.width, pageSize.height),
      );
      final contentWidth = contentBounds.width;
      final contentHeight = contentBounds.height;

      final sourceWidth = renderObject.size.width;
      final sourceHeight = renderObject.size.height;
      if (!sourceWidth.isFinite ||
          !sourceHeight.isFinite ||
          sourceWidth <= 0 ||
          sourceHeight <= 0) {
        throw StateError('Preview has invalid dimensions for PDF export');
      }

      final contentScale = contentWidth / sourceWidth;
      final logicalPageHeight = contentHeight / contentScale;
      if (!logicalPageHeight.isFinite || logicalPageHeight <= 1) {
        throw StateError('Failed to calculate PDF page height from preview');
      }

      final pageCount =
          (sourceHeight / logicalPageHeight).ceil().clamp(1, 9999);
      final devicePixelRatio =
          ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
      final slicePixelRatio = math.min(
        _resolvePreviewSlicePixelRatio(
          logicalWidth: sourceWidth,
          logicalHeight: logicalPageHeight,
          devicePixelRatio: devicePixelRatio,
        ),
        _resolvePreviewSlicePixelRatioCap(pageCount: pageCount),
      );

      final document = PdfDocument();
      document.pageSettings.size = PdfPageSize.a4;
      document.pageSettings.setMargins(0);

      var logicalOffset = 0.0;
      while (logicalOffset < sourceHeight - 0.5) {
        final logicalHeight = math.min(
          logicalPageHeight,
          sourceHeight - logicalOffset,
        );
        if (logicalHeight <= 0) {
          break;
        }

        final sliceImage = await renderLayer.toImage(
          Rect.fromLTWH(0, logicalOffset, sourceWidth, logicalHeight),
          pixelRatio: slicePixelRatio,
        );
        final sliceBytes =
            await sliceImage.toByteData(format: ui.ImageByteFormat.png);
        sliceImage.dispose();
        if (sliceBytes == null) {
          throw StateError('Failed to encode preview slice for PDF export');
        }

        final bitmap = PdfBitmap(sliceBytes.buffer.asUint8List());
        final drawHeight = logicalHeight * contentScale;

        final page = document.pages.add();
        page.graphics.drawImage(
          bitmap,
          Rect.fromLTWH(
            contentBounds.left,
            contentBounds.top,
            contentBounds.width,
            drawHeight,
          ),
        );

        logicalOffset += logicalHeight;
        await Future<void>.delayed(Duration.zero);
        await WidgetsBinding.instance.endOfFrame;
      }

      final bytes = await document.save();
      document.dispose();
      return Uint8List.fromList(bytes);
    } finally {
      if (mounted) {
        setState(() {
          _exportRenderMode = previousRenderMode;
          if (switchedPane) {
            _compactPane = ChatMarkdownCompactPane.editor;
          }
        });
        if (switchedPane) {
          _editorFocusNode.requestFocus();
        }
      }
    }
  }

  Future<Uint8List> _buildPdfWithVectorRenderer() {
    final normalized = sanitizeChatMarkdown(_controller.text);
    final blocks = _parseMarkdownBlocks(normalized);
    final emptyFallback = context.t.chat.markdownEditor.emptyPreview;
    final previewTheme =
        resolveChatMarkdownTheme(_themePreset, Theme.of(context));
    final renderer = _PdfMarkdownRenderer(theme: previewTheme);
    return renderer.render(
      blocks: blocks,
      emptyFallback: emptyFallback,
    );
  }

  double _resolvePreviewSlicePixelRatio({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    const maxLayerDimensionPx = 14000.0;

    final preferred = resolveMarkdownPreviewExportPixelRatio(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: devicePixelRatio,
    );
    final longestDimension = math.max(logicalWidth, logicalHeight);
    if (!longestDimension.isFinite || longestDimension <= 0) {
      return preferred;
    }

    final safeRatio = maxLayerDimensionPx / longestDimension;
    final bounded = math.min(preferred, safeRatio);
    return bounded.clamp(1.0, 8.0);
  }

  double _resolvePreviewSlicePixelRatioCap({required int pageCount}) {
    if (pageCount >= 48) {
      return 2.2;
    }
    if (pageCount >= 30) {
      return 2.7;
    }
    if (pageCount >= 16) {
      return 3.2;
    }
    return 8.0;
  }
}
