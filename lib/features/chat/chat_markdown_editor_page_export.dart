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

String _formatPdfExportColorHex(Color color) =>
    '#${color.value.toRadixString(16).padLeft(8, '0').toLowerCase()}';

mixin _ChatMarkdownEditorExportMixin on State<ChatMarkdownEditorPage> {
  bool get _exporting;
  set _exporting(bool value);

  TextEditingController get _controller;
  List<AttachmentDraftPayload> get _draftAttachments;
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
      case _MarkdownExportAction.markdownBundle:
        await _exportMarkdownBundle();
        return;
      case _MarkdownExportAction.copyToClipboard:
        await _copyToClipboard();
        return;
    }
  }

  Future<File> _debugExportFileForTest(_MarkdownExportFormat format) async {
    final bytes = switch (format) {
      _MarkdownExportFormat.png => await _capturePreviewAsPngBytes(),
      _MarkdownExportFormat.pdf => await _buildPdfBytes(),
    };
    return _materializeMarkdownExportFile(
      format: format,
      bytes: bytes,
      sourceMarkdown: _controller.text,
    );
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
      final doneMessage = context.t.chat.markdownEditor.exportDoneSavedPath(
        format: formatLabel,
        path: file.path,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(doneMessage),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final resolvedReason = format == _MarkdownExportFormat.pdf
          ? _resolvePdfExportFailureReason(error)
          : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.chat.markdownEditor.exportFailed(error: resolvedReason),
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

  String _resolvePdfExportFailureReason(Object error) {
    switch (classifyMarkdownPdfExportError(error)) {
      case MarkdownPdfExportErrorKind.noWindowsBrowser:
        return context.t.chat.markdownEditor.exportReasonNoWindowsBrowser;
      case MarkdownPdfExportErrorKind.windowsBrowserPrintFailed:
        return context.t.chat.markdownEditor.exportReasonWindowsBrowserPrint;
      case MarkdownPdfExportErrorKind.timeout:
        return context.t.chat.markdownEditor.exportReasonTimeout;
      case MarkdownPdfExportErrorKind.renderFailed:
        return context.t.chat.markdownEditor.exportReasonRender;
      case MarkdownPdfExportErrorKind.writeFailed:
        return context.t.chat.markdownEditor.exportReasonWrite;
      case MarkdownPdfExportErrorKind.cancelled:
        return context.t.chat.markdownEditor.exportReasonCancelled;
      case MarkdownPdfExportErrorKind.notSupported:
        return context.t.chat.markdownEditor.exportReasonUnsupported;
      case MarkdownPdfExportErrorKind.unknown:
        return '$error';
    }
  }

  Future<void> _exportMarkdownBundle() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final backend = AppBackendScope.maybeOf(context);
      final AttachmentsBackend? attachmentsBackend =
          backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
      final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
      final directory = await _resolveMarkdownExportDirectory();
      final sourceMarkdown = _controller.text;
      final baseStem = deriveMarkdownExportFilenameStem(sourceMarkdown);
      var stem = baseStem;
      var duplicateIndex = 2;
      while (await File('${directory.path}/$stem.md').exists() ||
          await Directory('${directory.path}/$stem.assets').exists()) {
        stem = '$baseStem-$duplicateIndex';
        duplicateIndex += 1;
      }

      final result = await exportChatMarkdownBundle(
        markdown: sourceMarkdown,
        filenameStem: stem,
        outputDirectory: directory,
        draftAttachments: _draftAttachments,
        readPersistedAttachment:
            attachmentsBackend == null || sessionKey == null || backend == null
                ? null
                : (attachmentSha256) async {
                    final attachment = await backend.readAttachmentBySha256(
                      attachmentSha256,
                    );
                    if (attachment == null) return null;
                    final bytes = await attachmentsBackend.readAttachmentBytes(
                      sessionKey,
                      sha256: attachmentSha256,
                    );
                    return MarkdownBundleAssetData(
                      bytes: bytes,
                      mimeType: attachment.mimeType,
                      filename: attachment.path,
                    );
                  },
      );

      if (!mounted) return;
      final doneMessage = context.t.chat.markdownEditor.exportDoneSavedPath(
        format: 'Markdown',
        path: result.markdownFile.path,
      );
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
      final backend = AppBackendScope.maybeOf(context);
      final AttachmentsBackend? attachmentsBackend =
          backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
      final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
      final html = await buildChatMarkdownClipboardHtml(
        markdown: _controller.text,
        theme: previewTheme,
        emptyFallback: context.t.chat.markdownEditor.emptyPreview,
        draftAttachments: _draftAttachments,
        readPersistedAttachment:
            attachmentsBackend == null || sessionKey == null || backend == null
                ? null
                : (attachmentSha256) async {
                    final attachment = await backend.readAttachmentBySha256(
                      attachmentSha256,
                    );
                    if (attachment == null) return null;
                    final bytes = await attachmentsBackend.readAttachmentBytes(
                      sessionKey,
                      sha256: attachmentSha256,
                    );
                    return ChatMarkdownExportImageData(
                      bytes: bytes,
                      mimeType: attachment.mimeType,
                    );
                  },
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
    final markdown = _controller.text;
    final previewTheme =
        resolveChatMarkdownTheme(_themePreset, Theme.of(context));
    final backend = AppBackendScope.maybeOf(context);
    final AttachmentsBackend? attachmentsBackend =
        backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    final readPersistedAttachment =
        attachmentsBackend == null || sessionKey == null || backend == null
            ? null
            : (String attachmentSha256) async {
                final attachment = await backend.readAttachmentBySha256(
                  attachmentSha256,
                );
                if (attachment == null) return null;
                final bytes = await attachmentsBackend.readAttachmentBytes(
                  sessionKey,
                  sha256: attachmentSha256,
                );
                return ChatMarkdownExportImageData(
                  bytes: bytes,
                  mimeType: attachment.mimeType,
                );
              };
    final htmlBuilder =
        widget.pdfHtmlBuilder ?? buildChatMarkdownPdfHtmlDocument;
    final html = await htmlBuilder(
      markdown: markdown,
      theme: previewTheme,
      emptyFallback: context.t.chat.markdownEditor.emptyPreview,
      draftAttachments: _draftAttachments,
      readPersistedAttachment: readPersistedAttachment,
    );
    final pageBackgroundColorHex =
        _formatPdfExportColorHex(previewTheme.panelColor);
    await widget.beforePdfExport?.call(
      html: html,
      pageBackgroundColorHex: pageBackgroundColorHex,
    );

    if (widget.pdfExporter != null) {
      return widget.pdfExporter!(
        html: html,
        pageBackgroundColorHex: pageBackgroundColorHex,
      );
    }

    if (isNativeMarkdownPdfExportSupported()) {
      final nativeBytes = await exportMarkdownHtmlToPdfBytes(
        html: html,
        pageBackgroundColorHex: pageBackgroundColorHex,
      );
      return _composeNativePdfWithThemeBackground(
        pdfBytes: nativeBytes,
        backgroundColor: previewTheme.panelColor,
      );
    }

    return _buildPdfWithVectorRenderer();
  }

  Future<Uint8List> _composeNativePdfWithThemeBackground({
    required Uint8List pdfBytes,
    required Color backgroundColor,
  }) async {
    PdfDocument? sourceDocument;
    PdfDocument? composedDocument;

    try {
      sourceDocument = PdfDocument(inputBytes: pdfBytes);
      if (sourceDocument.pages.count == 0) {
        return pdfBytes;
      }

      composedDocument = PdfDocument()..pageSettings.setMargins(0);
      final backgroundBrush = PdfSolidBrush(_toPdfColor(backgroundColor));

      for (var pageIndex = 0;
          pageIndex < sourceDocument.pages.count;
          pageIndex += 1) {
        final sourcePage = sourceDocument.pages[pageIndex];
        final sourceSize = sourcePage.size;
        composedDocument.pageSettings.size =
            Size(sourceSize.width, sourceSize.height);

        final outputPage = composedDocument.pages.add();
        outputPage.graphics.drawRectangle(
          brush: backgroundBrush,
          bounds: Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height),
        );
        outputPage.graphics.drawPdfTemplate(
          sourcePage.createTemplate(),
          Offset.zero,
          Size(sourceSize.width, sourceSize.height),
        );
      }

      final composedBytes = await composedDocument.save();
      if (composedBytes.isEmpty) {
        return pdfBytes;
      }
      return Uint8List.fromList(composedBytes);
    } catch (_) {
      return pdfBytes;
    } finally {
      sourceDocument?.dispose();
      composedDocument?.dispose();
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
}
