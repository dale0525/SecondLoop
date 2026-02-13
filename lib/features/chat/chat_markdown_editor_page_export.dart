part of 'chat_markdown_editor_page.dart';

mixin _ChatMarkdownEditorExportMixin on State<ChatMarkdownEditorPage> {
  bool get _exporting;
  set _exporting(bool value);

  ChatMarkdownCompactPane get _compactPane;
  set _compactPane(ChatMarkdownCompactPane value);

  ScrollController get _previewScrollController;
  GlobalKey get _previewRepaintBoundaryKey;
  FocusNode get _editorFocusNode;
  ChatMarkdownThemePreset get _themePreset;

  bool _isWideLayout(BuildContext context);
  Future<void> _export(_MarkdownExportFormat format) async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final pngBytes = await _capturePreviewAsPngBytes();
      final bytes = format == _MarkdownExportFormat.png
          ? pngBytes
          : await _buildPdfBytes(pngBytes);
      final file = await _materializeExportFile(format, bytes);

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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.chat.markdownEditor.exportDone(
              format: format == _MarkdownExportFormat.png ? 'PNG' : 'PDF',
            ),
          ),
          duration: const Duration(seconds: 2),
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

    if (switchedPane) {
      setState(() => _compactPane = ChatMarkdownCompactPane.preview);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await WidgetsBinding.instance.endOfFrame;
    }

    try {
      if (_previewScrollController.hasClients) {
        _previewScrollController.jumpTo(0);
      }
      await WidgetsBinding.instance.endOfFrame;

      final renderObject =
          _previewRepaintBoundaryKey.currentContext?.findRenderObject();
      if (renderObject == null) {
        throw StateError('Preview is not ready for export');
      }
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Preview render boundary is unavailable');
      }

      final pixelRatio = ui
          .PlatformDispatcher.instance.views.first.devicePixelRatio
          .clamp(1.0, 3.0);

      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Failed to encode preview as PNG');
      }
      return byteData.buffer.asUint8List();
    } finally {
      if (switchedPane && mounted) {
        setState(() => _compactPane = ChatMarkdownCompactPane.editor);
        _editorFocusNode.requestFocus();
      }
    }
  }

  Future<Uint8List> _buildPdfBytes(Uint8List pngBytes) async {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) {
      throw StateError('Failed to decode preview image for PDF export');
    }

    final jpeg = img.encodeJpg(decoded, quality: 92);
    const pageWidth = 595.0;
    const pageHeight = 842.0;
    const margin = 24.0;
    const availableWidth = pageWidth - margin * 2;
    const availableHeight = pageHeight - margin * 2;

    final scale = math.min(
      availableWidth / decoded.width,
      availableHeight / decoded.height,
    );
    final drawWidth = decoded.width * scale;
    final drawHeight = decoded.height * scale;
    final offsetX = (pageWidth - drawWidth) / 2;
    final offsetY = (pageHeight - drawHeight) / 2;

    final contentStream = 'q\n'
        '${drawWidth.toStringAsFixed(2)} 0 0 ${drawHeight.toStringAsFixed(2)} '
        '${offsetX.toStringAsFixed(2)} ${offsetY.toStringAsFixed(2)} cm\n'
        '/Im0 Do\n'
        'Q\n';

    final builder = _PdfBinaryBuilder();
    builder.addAsciiObject('<< /Type /Catalog /Pages 2 0 R >>');
    builder.addAsciiObject('<< /Type /Pages /Count 1 /Kids [3 0 R] >>');
    builder.addAsciiObject(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth $pageHeight] '
      '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>',
    );
    builder.addBinaryStreamObject(
      dictionary:
          '<< /Type /XObject /Subtype /Image /Width ${decoded.width} /Height ${decoded.height} '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>',
      streamBytes: Uint8List.fromList(jpeg),
    );
    builder.addBinaryStreamObject(
      dictionary: '<< /Length ${contentStream.length} >>',
      streamBytes: Uint8List.fromList(contentStream.codeUnits),
    );

    return builder.build(rootObjectId: 1);
  }

  Future<File> _materializeExportFile(
    _MarkdownExportFormat format,
    Uint8List bytes,
  ) async {
    final dir = await getTemporaryDirectory();
    final extension = format == _MarkdownExportFormat.png ? 'png' : 'pdf';
    final filename =
        'markdown-${DateTime.now().millisecondsSinceEpoch}-${_themePreset.name}.$extension';
    final output = File('${dir.path}/$filename');
    await output.writeAsBytes(bytes, flush: true);
    return output;
  }
}

class _PdfBinaryBuilder {
  final List<_PdfObject> _objects = <_PdfObject>[];

  int addAsciiObject(String body) {
    _objects.add(_PdfObject.ascii(body));
    return _objects.length;
  }

  int addBinaryStreamObject({
    required String dictionary,
    required Uint8List streamBytes,
  }) {
    _objects.add(
      _PdfObject.binary(
        dictionary: dictionary,
        streamBytes: streamBytes,
      ),
    );
    return _objects.length;
  }

  Uint8List build({required int rootObjectId}) {
    final builder = BytesBuilder(copy: false);
    final offsets = <int>[0];

    void writeAscii(String value) {
      builder.add(Uint8List.fromList(value.codeUnits));
    }

    writeAscii('%PDF-1.4\n%PDF\n');

    for (var index = 0; index < _objects.length; index += 1) {
      final object = _objects[index];
      final objectId = index + 1;
      offsets.add(builder.length);
      writeAscii('$objectId 0 obj\n');
      if (object.isBinaryStream) {
        writeAscii('${object.dictionary}\nstream\n');
        builder.add(object.streamBytes!);
        writeAscii('\nendstream\n');
      } else {
        writeAscii('${object.body}\n');
      }
      writeAscii('endobj\n');
    }

    final xrefOffset = builder.length;
    writeAscii('xref\n0 ${_objects.length + 1}\n');
    writeAscii('0000000000 65535 f \n');
    for (var index = 1; index < offsets.length; index += 1) {
      writeAscii("${offsets[index].toString().padLeft(10, '0')} 00000 n \n");
    }

    writeAscii('trailer\n');
    writeAscii('<< /Size ${_objects.length + 1} /Root $rootObjectId 0 R >>\n');
    writeAscii('startxref\n$xrefOffset\n%%EOF');

    return builder.takeBytes();
  }
}

class _PdfObject {
  const _PdfObject.ascii(this.body)
      : dictionary = null,
        streamBytes = null,
        isBinaryStream = false;

  const _PdfObject.binary({
    required this.dictionary,
    required this.streamBytes,
  })  : body = null,
        isBinaryStream = true;

  final String? body;
  final String? dictionary;
  final Uint8List? streamBytes;
  final bool isBinaryStream;
}
