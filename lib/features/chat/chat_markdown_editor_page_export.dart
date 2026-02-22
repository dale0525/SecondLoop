part of 'chat_markdown_editor_page.dart';

const double _kPdfPageMarginHorizontal = 54;
const double _kPdfPageMarginVertical = 48;
const double _kPdfLatexCaptureMinWidth = 520;
const double _kPdfLatexCaptureMaxWidth = 1180;
const double _kPdfLatexCapturePixelRatio = 2.4;

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
    final normalized = sanitizeChatMarkdown(_controller.text);
    final blocks = _parseMarkdownBlocks(normalized);
    final emptyFallback = context.t.chat.markdownEditor.emptyPreview;
    final previewTheme =
        resolveChatMarkdownTheme(_themePreset, Theme.of(context));
    final latexBitmapCache = await _buildPdfLatexBitmapCache(
      blocks: blocks,
      previewTheme: previewTheme,
    );
    final renderer = _PdfMarkdownRenderer(
      theme: previewTheme,
      latexBitmapCache: latexBitmapCache,
    );
    return renderer.render(
      blocks: blocks,
      emptyFallback: emptyFallback,
    );
  }

  Future<Map<String, Uint8List>> _buildPdfLatexBitmapCache({
    required List<_PdfMarkdownBlock> blocks,
    required ChatMarkdownPreviewTheme previewTheme,
  }) async {
    final expressions = <String>{};
    for (final block in blocks) {
      if (block.type != _PdfMarkdownBlockType.latex) {
        continue;
      }

      final expression = block.text.trim();
      if (expression.isEmpty) {
        continue;
      }
      expressions.add(expression);
    }

    if (expressions.isEmpty) {
      return const <String, Uint8List>{};
    }

    final cache = <String, Uint8List>{};
    for (final expression in expressions) {
      final bytes = await _captureLatexFormulaBitmap(
        expression: expression,
        previewTheme: previewTheme,
      );
      if (bytes != null && bytes.isNotEmpty) {
        cache[expression] = bytes;
      }
      await Future<void>.delayed(Duration.zero);
    }

    return cache;
  }

  Future<Uint8List?> _captureLatexFormulaBitmap({
    required String expression,
    required ChatMarkdownPreviewTheme previewTheme,
  }) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return null;
    }

    final viewportWidth = MediaQuery.sizeOf(context).width;
    final captureWidth = viewportWidth.isFinite
        ? viewportWidth
            .clamp(_kPdfLatexCaptureMinWidth, _kPdfLatexCaptureMaxWidth)
            .toDouble()
        : 900.0;
    final boundaryKey = GlobalKey();

    final baseTextStyle = Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14, height: 1.5);
    final latexStyle = baseTextStyle.copyWith(
      color: previewTheme.textColor,
      fontSize: 14,
      height: 1.35,
    );

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          top: 0,
          left: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.001,
              child: Material(
                type: MaterialType.transparency,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                    width: captureWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: previewTheme.codeBlockBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: previewTheme.borderColor.withOpacity(0.92),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Math.tex(
                            expression,
                            mathStyle: MathStyle.display,
                            textStyle: latexStyle,
                            onErrorFallback: (_) {
                              return Text(
                                expression,
                                style: latexStyle.copyWith(
                                  color: previewTheme.mutedTextColor,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await WidgetsBinding.instance.endOfFrame;

      final renderObject = boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        return null;
      }

      final image = await renderObject.toImage(
        pixelRatio: _kPdfLatexCapturePixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        return null;
      }

      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      entry.remove();
    }
  }
}
