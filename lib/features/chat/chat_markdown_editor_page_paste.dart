part of 'chat_markdown_editor_page.dart';

const Duration _markdownEditorPasteImageReadTimeout = Duration(seconds: 5);

extension _ChatMarkdownEditorPagePaste on _ChatMarkdownEditorPageState {
  String _nextDraftAttachmentLocalId() {
    _draftAttachmentSeq += 1;
    return 'markdown_draft_$_draftAttachmentSeq';
  }

  KeyEventResult _handleEditorOnKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final hardware = HardwareKeyboard.instance;
    final metaPressed = hardware.isMetaPressed;
    final controlPressed = hardware.isControlPressed;
    final shiftPressed = hardware.isShiftPressed;
    final shortcut = resolveTextEditingShortcut(
      key: key,
      keyLabel: key.keyLabel,
      character: event.character,
      metaPressed: metaPressed,
      controlPressed: controlPressed,
      shiftPressed: shiftPressed,
      supportedShortcuts: const <TextEditingShortcut>{
        TextEditingShortcut.paste,
      },
    );

    if (shortcut == TextEditingShortcut.paste) {
      if (!_pasteInProgress) {
        unawaited(_pasteIntoMarkdownEditor());
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _pasteIntoMarkdownEditor() async {
    if (_pasteInProgress) {
      return;
    }
    _pasteInProgress = true;
    try {
      final pastedImage = await _readPastedImageData();
      if (!mounted) {
        return;
      }
      if (pastedImage != null && pastedImage.bytes.isNotEmpty) {
        final localId = _nextDraftAttachmentLocalId();
        final payload = buildImageAttachmentDraftPayload(
          localId: localId,
          rawBytes: pastedImage.bytes,
          inferredMimeType: pastedImage.mimeType,
          filename: pastedImage.filename,
        );
        _draftAttachments.add(payload);
        final altText = context.t.attachments.workspace.types.image;
        final markdownImage =
            '![$altText](${buildDraftMarkdownImageSource(localId)})';
        _replaceSelectionWithText(markdownImage);
        return;
      }

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text;
      if (text == null || text.isEmpty) return;
      _replaceSelectionWithText(text);
    } finally {
      _pasteInProgress = false;
    }
  }

  Future<ChatMarkdownPastedImageData?> _readPastedImageData() async {
    final overrideReader = widget.pastedImageReader;
    if (overrideReader != null) {
      return _withPasteImageReadTimeout(overrideReader());
    }

    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return null;
    }

    try {
      final reader = await clipboard.read();
      return _readPastedImageFromClipboardReader(reader);
    } catch (_) {
      return null;
    }
  }

  Future<ChatMarkdownPastedImageData?> _readPastedImageFromClipboardReader(
    ClipboardReader reader,
  ) async {
    for (final format in <FileFormat>[
      Formats.png,
      Formats.jpeg,
      Formats.webp,
      Formats.gif,
      Formats.tiff,
    ]) {
      if (!reader.canProvide(format)) {
        continue;
      }

      final completer = Completer<ChatMarkdownPastedImageData?>();
      final progress = reader.getFile(
        format,
        (file) async {
          try {
            final bytes = await file.readAll();
            if (!completer.isCompleted) {
              completer.complete(
                ChatMarkdownPastedImageData(
                  bytes: bytes,
                  mimeType: _mimeTypeForClipboardFormat(format),
                  filename: file.fileName,
                ),
              );
            }
          } catch (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );
      if (progress == null) {
        continue;
      }

      final resolved = await _withPasteImageReadTimeout(completer.future);
      if (resolved != null && resolved.bytes.isNotEmpty) {
        return resolved;
      }
    }

    return null;
  }

  Future<ChatMarkdownPastedImageData?> _withPasteImageReadTimeout(
    Future<ChatMarkdownPastedImageData?> future,
  ) {
    final completer = Completer<ChatMarkdownPastedImageData?>();
    final timer = Timer(_markdownEditorPasteImageReadTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    future.then((value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }).whenComplete(timer.cancel);

    return completer.future;
  }

  void _replaceSelectionWithText(String text) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : (_lastValidSelection ??
            TextSelection.collapsed(offset: value.text.length));
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final nextText = value.text.replaceRange(start, end, text);
    _controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
    _editorFocusNode.requestFocus();
  }
}

String _mimeTypeForClipboardFormat(FileFormat format) {
  if (format == Formats.png) return 'image/png';
  if (format == Formats.jpeg) return 'image/jpeg';
  if (format == Formats.webp) return 'image/webp';
  if (format == Formats.gif) return 'image/gif';
  if (format == Formats.tiff) return 'image/tiff';
  return 'image/png';
}
