part of 'chat_markdown_editor_page.dart';

const double _kPdfPageMarginHorizontal = 0;
const double _kPdfPageMarginVertical = 0;

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
    final previewTheme =
        resolveChatMarkdownTheme(_themePreset, Theme.of(context));
    final renderer = _PdfMarkdownRenderer(theme: previewTheme);
    return renderer.render(
      blocks: blocks,
      emptyFallback: context.t.chat.markdownEditor.emptyPreview,
    );
  }
}
