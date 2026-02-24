part of 'todo_detail_page.dart';

enum _TodoAudioRecordingSheetAction { stop, cancel }

extension _TodoDetailPageStateComposer on _TodoDetailPageState {
  String _inferImageMimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  String _inferMimeTypeFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif')) {
      return _inferImageMimeTypeFromPath(filename);
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.ini')) return 'text/plain';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return 'application/x-yaml';
    }
    if (lower.endsWith('.toml')) return 'application/toml';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.opus')) return 'audio/opus';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.wmv')) return 'video/x-ms-wmv';
    if (lower.endsWith('.flv')) return 'video/x-flv';
    if (lower.endsWith('.mpeg') || lower.endsWith('.mpg')) {
      return 'video/mpeg';
    }
    if (lower.endsWith('.ts') ||
        lower.endsWith('.m2ts') ||
        lower.endsWith('.mts')) {
      return 'video/mp2t';
    }
    if (lower.endsWith('.3gp')) return 'video/3gpp';
    if (lower.endsWith('.3g2')) return 'video/3gpp2';
    if (lower.endsWith('.asf')) return 'video/x-ms-asf';
    if (lower.endsWith('.ogv')) return 'video/ogg';
    return 'application/octet-stream';
  }

  void _setComposerAttaching(bool attaching) {
    if (!mounted) {
      _attachingMedia = attaching;
      return;
    }
    _setState(() => _attachingMedia = attaching);
  }

  Future<Attachment> _readAttachmentOrFallback({
    required AppBackend backend,
    required String attachmentSha256,
    required String mimeType,
    required int byteLen,
  }) async {
    try {
      final existing = await backend.readAttachmentBySha256(attachmentSha256);
      if (existing != null) return existing;
    } catch (_) {
      // ignore
    }

    return Attachment(
      sha256: attachmentSha256,
      mimeType: mimeType,
      path: '',
      byteLen: byteLen,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _attachImageBytes(
    Uint8List rawBytes,
    String inferredMimeType, {
    String? filename,
    int? fallbackCapturedAtMs,
  }) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) {
      throw Exception('native_backend_required');
    }

    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final lang = Localizations.localeOf(context).toLanguageTag();

    final ingested = await ingestImageAttachmentBytes(
      backend: backend,
      sessionKey: sessionKey,
      rawBytes: rawBytes,
      inferredMimeType: inferredMimeType,
      lang: lang,
      fallbackCapturedAtMs: fallbackCapturedAtMs,
    );

    final attachment = await _readAttachmentOrFallback(
      backend: backend,
      attachmentSha256: ingested.attachmentSha256,
      mimeType: inferredMimeType,
      byteLen: rawBytes.length,
    );
    _appendPendingAttachment(attachment);

    final safeFilename = (filename ?? '').trim();
    if (safeFilename.isNotEmpty) {
      unawaited(
        const RustAttachmentMetadataStore().upsert(
          sessionKey,
          attachmentSha256: ingested.attachmentSha256,
          filenames: [safeFilename],
        ).catchError((_) {}),
      );
    }
  }

  Future<void> _attachFileBytes(
    Uint8List rawBytes,
    String mimeType, {
    required String filename,
  }) async {
    final backendAny = AppBackendScope.of(context);
    if (backendAny is! NativeAppBackend) {
      throw Exception('native_backend_required');
    }

    final backend = backendAny;
    final sessionKey = SessionScope.of(context).sessionKey;
    final subscriptionStatus = SubscriptionScope.maybeOf(context)?.status ??
        SubscriptionStatus.unknown;
    final useLocalAudioTranscode = shouldUseLocalAudioTranscode(
      subscriptionStatus: subscriptionStatus,
    );
    final normalizedMimeType = mimeType.trim();

    final attachmentSha256 = await ingestFileAttachmentBytes(
      backend: backend,
      sessionKey: sessionKey,
      rawBytes: rawBytes,
      mimeType: normalizedMimeType,
      options: FileAttachmentIngestOptions(
        useLocalAudioTranscode: useLocalAudioTranscode,
        videoProxyEnabled: true,
        videoProxyMaxDurationMs: kAttachmentVideoProxyMaxDurationMs,
        videoProxyMaxBytes: kAttachmentVideoProxyMaxBytes,
      ),
    );

    final attachment = await _readAttachmentOrFallback(
      backend: backend,
      attachmentSha256: attachmentSha256,
      mimeType: normalizedMimeType,
      byteLen: rawBytes.length,
    );
    _appendPendingAttachment(attachment);

    final safeFilename = filename.trim();
    if (safeFilename.isNotEmpty) {
      unawaited(
        const RustAttachmentMetadataStore().upsert(
          sessionKey,
          attachmentSha256: attachmentSha256,
          filenames: [safeFilename],
        ).catchError((_) {}),
      );
    }
  }

  Future<void> _attachDesktopFilePayloads(
    List<({String filename, Uint8List bytes})> payloads,
  ) async {
    for (final payload in payloads) {
      final safeName = payload.filename.trim().isEmpty
          ? 'attachment.bin'
          : payload.filename.trim();
      final inferredMimeType = _inferMimeTypeFromFilename(safeName);
      if (inferredMimeType.startsWith('image/')) {
        await _attachImageBytes(
          payload.bytes,
          inferredMimeType,
          filename: safeName,
        );
      } else {
        await _attachFileBytes(
          payload.bytes,
          inferredMimeType,
          filename: safeName,
        );
      }
    }
  }

  Future<void> _attachDroppedDesktopFiles(List<XFile> droppedFiles) async {
    if (_isComposerBusy) return;
    if (!_isDesktopPlatform) return;
    if (droppedFiles.isEmpty) return;

    _setComposerAttaching(true);
    try {
      final payloads = <({String filename, Uint8List bytes})>[];
      for (final dropped in droppedFiles) {
        final bytes = await dropped.readAsBytes();
        if (bytes.isEmpty) continue;
        final filename = dropped.name.trim().isEmpty
            ? 'attachment.bin'
            : dropped.name.trim();
        payloads.add((filename: filename, bytes: bytes));
      }
      if (payloads.isEmpty) {
        throw Exception('drop payload contains no readable files');
      }
      await _attachDesktopFilePayloads(payloads);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _setComposerAttaching(false);
    }
  }

  Future<void> _pickAndAttachFromFile() async {
    if (_isComposerBusy) return;

    _setComposerAttaching(true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final payloads = <({String filename, Uint8List bytes})>[];
      for (final file in picked.files) {
        var bytes = file.bytes;
        final path = file.path?.trim();
        if ((bytes == null || bytes.isEmpty) &&
            path != null &&
            path.isNotEmpty) {
          bytes = await XFile(path).readAsBytes();
        }
        if (bytes == null || bytes.isEmpty) continue;
        payloads.add((filename: file.name, bytes: bytes));
      }
      if (payloads.isEmpty) {
        throw Exception('file_picker returned no readable file data');
      }
      await _attachDesktopFilePayloads(payloads);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _setComposerAttaching(false);
    }
  }

  Future<void> _captureAndAttachPhoto() async {
    if (_isComposerBusy) return;
    if (!_supportsCamera) return;

    _setComposerAttaching(true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        requestFullMetadata: true,
      );
      if (picked == null) return;

      final rawBytes = await picked.readAsBytes();
      final inferredMimeType = _inferImageMimeTypeFromPath(picked.path);
      final pickedFilename = (() {
        final byName = picked.name.trim();
        if (byName.isNotEmpty) return byName;
        final normalizedPath = picked.path.trim().replaceAll('\\', '/');
        if (normalizedPath.isEmpty) return '';
        return normalizedPath.split('/').last.trim();
      })();
      int? fallbackCapturedAtMs;
      try {
        fallbackCapturedAtMs =
            (await picked.lastModified()).toUtc().millisecondsSinceEpoch;
      } catch (_) {}

      await _attachImageBytes(
        rawBytes,
        inferredMimeType,
        filename: pickedFilename,
        fallbackCapturedAtMs: fallbackCapturedAtMs,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _setComposerAttaching(false);
    }
  }

  Future<_TodoAudioRecordingSheetAction> _showTodoAudioRecordingSheet() async {
    final action = await showModalBottomSheet<_TodoAudioRecordingSheetAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.t.chat.attachRecordAudio,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(context.t.chat.recordingInProgress),
                const SizedBox(height: 6),
                Text(context.t.chat.recordingHint),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SlButton(
                        variant: SlButtonVariant.outline,
                        onPressed: () => Navigator.of(sheetContext).pop(
                          _TodoAudioRecordingSheetAction.cancel,
                        ),
                        child: Text(context.t.common.actions.cancel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SlButton(
                        onPressed: () => Navigator.of(sheetContext).pop(
                          _TodoAudioRecordingSheetAction.stop,
                        ),
                        child: Text(context.t.common.actions.stop),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return action ?? _TodoAudioRecordingSheetAction.cancel;
  }

  Future<void> _recordAndAttachAudioFromSheet() async {
    if (_isComposerBusy) return;
    if (!_supportsAudioRecording) return;

    final recorder = _audioRecorder ??= AudioRecorder();

    bool hasPermission;
    try {
      hasPermission = await recorder.hasPermission();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.t.errors.loadFailed(error: 'permission_denied')),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '${tempDir.path}/todo_note_record_$startedAtMs.m4a';

    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: tempPath,
      );
      if (!mounted) return;
      _setState(() => _recordingAudio = true);

      final action = await _showTodoAudioRecordingSheet();
      final recordedPath = await recorder.stop();
      if (action != _TodoAudioRecordingSheetAction.stop) {
        return;
      }
      if (recordedPath == null || recordedPath.trim().isEmpty) {
        throw Exception('recording_path_empty');
      }

      _setComposerAttaching(true);
      try {
        final bytes = await XFile(recordedPath).readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('recording_bytes_empty');
        }
        final filename = 'recording_$startedAtMs.m4a';
        await _attachFileBytes(
          bytes,
          'audio/mp4',
          filename: filename,
        );
      } finally {
        _setComposerAttaching(false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.errors.loadFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        _setState(() => _recordingAudio = false);
      } else {
        _recordingAudio = false;
      }
    }
  }

  Future<void> _openTodoAttachmentSheet() async {
    if (_isComposerBusy) return;

    if (!_supportsImageUpload && !_supportsAudioRecording) {
      await _pickAttachment();
      return;
    }

    if (_isDesktopPlatform) {
      await _pickAndAttachFromFile();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('todo_detail_attach_pick_media'),
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(context.t.chat.attachPickMedia),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_pickAndAttachFromFile());
                },
              ),
              if (_supportsCamera)
                ListTile(
                  key: const ValueKey('todo_detail_attach_take_photo'),
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: Text(context.t.chat.attachTakePhoto),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_captureAndAttachPhoto());
                  },
                ),
              if (_supportsAudioRecording)
                ListTile(
                  key: const ValueKey('todo_detail_attach_record_audio'),
                  leading: const Icon(Icons.mic_rounded),
                  title: Text(context.t.chat.attachRecordAudio),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_recordAndAttachAudioFromSheet());
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTodoMarkdownEditor() async {
    if (_isComposerBusy) return;

    final result = await openChatMarkdownEditor(
      context,
      initialText: _noteController.text,
      allowPlainMode: true,
    );
    if (!mounted || result == null) return;

    final updatedText = result.text;
    _noteController.value = _noteController.value.copyWith(
      text: updatedText,
      selection: TextSelection.collapsed(offset: updatedText.length),
      composing: TextRange.empty,
    );

    if (result.shouldSwitchToSimpleInput) {
      if (_isDesktopPlatform) {
        _noteInputFocusNode.requestFocus();
      }
      return;
    }

    await _appendNote();
  }

  // ignore: deprecated_member_use
  KeyEventResult _handleTodoComposerOnKey(FocusNode node, RawKeyEvent event) {
    // ignore: deprecated_member_use
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    if (event.repeat) {
      return KeyEventResult.handled;
    }

    final composing = _noteController.value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    if (isComposing) {
      return KeyEventResult.ignored;
    }

    final hardware = HardwareKeyboard.instance;
    final modifierData = event.data;
    final shiftPressed = hardware.isShiftPressed ||
        modifierData.isModifierPressed(ModifierKey.shiftModifier);

    if (shiftPressed) {
      final value = _noteController.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : value.text.length;
      final normalizedStart = start < end ? start : end;
      final normalizedEnd = start < end ? end : start;
      final updatedText = value.text.replaceRange(
        normalizedStart,
        normalizedEnd,
        '\n',
      );
      _noteController.value = value.copyWith(
        text: updatedText,
        selection: TextSelection.collapsed(offset: normalizedStart + 1),
        composing: TextRange.empty,
      );
      return KeyEventResult.handled;
    }

    unawaited(_appendNote());
    return KeyEventResult.handled;
  }

  Widget _buildTodoComposerMarkdownEditorButton(BuildContext context) {
    return Semantics(
      button: true,
      label: context.t.chat.markdownEditor.openButton,
      child: SlIconButton(
        key: const ValueKey('todo_detail_open_markdown_editor'),
        icon: Icons.open_in_full_rounded,
        size: 40,
        iconSize: 20,
        tooltip: context.t.chat.markdownEditor.openButton,
        canRequestFocus: false,
        triggerOnTapDown: true,
        onPressed: _isComposerBusy ? null : _openTodoMarkdownEditor,
      ),
    );
  }

  Widget _buildTodoCompactAttachButton(
    BuildContext context, {
    bool includeLeadingPadding = true,
  }) {
    if (!_supportsImageUpload && !_supportsAudioRecording) {
      return const SizedBox.shrink();
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_supportsDesktopRecordAudioAction) ...[
          SlIconButton(
            key: const ValueKey('todo_detail_record_audio'),
            icon: Icons.mic_rounded,
            size: 44,
            iconSize: 22,
            tooltip: context.t.chat.attachRecordAudio,
            onPressed: _isComposerBusy
                ? null
                : () => unawaited(_recordAndAttachAudioFromSheet()),
          ),
          const SizedBox(width: 8),
        ],
        SlIconButton(
          key: const ValueKey('todo_detail_attach'),
          icon: Icons.add_rounded,
          size: 44,
          iconSize: 22,
          tooltip: context.t.actions.todoDetail.attach,
          onPressed: _isComposerBusy ? null : _openTodoAttachmentSheet,
        ),
      ],
    );

    if (!includeLeadingPadding) return row;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: row,
    );
  }

  Widget _buildTodoCompactComposerActions(
    BuildContext context, {
    required ColorScheme colorScheme,
  }) {
    return ListenableBuilder(
      listenable: _noteInputFocusNode,
      builder: (context, child) {
        final showMarkdownButton = _noteInputFocusNode.hasFocus;
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: _noteController,
          builder: (context, value, child) {
            final hasText = value.text.trim().isNotEmpty;
            final canSend = hasText || _pendingAttachments.isNotEmpty;
            final hasAttachActions =
                _supportsImageUpload || _supportsAudioRecording;

            if (!canSend) {
              if (!hasAttachActions) {
                if (!showMarkdownButton) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildTodoComposerMarkdownEditorButton(context),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showMarkdownButton) ...[
                      _buildTodoComposerMarkdownEditorButton(context),
                      const SizedBox(width: 8),
                    ],
                    _buildTodoCompactAttachButton(
                      context,
                      includeLeadingPadding: false,
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChatComposerInlineButton(
                buttonKey: const ValueKey('todo_detail_send'),
                label: context.t.common.actions.send,
                icon: Icons.send_rounded,
                onPressed:
                    _isComposerBusy ? null : () => unawaited(_appendNote()),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                iconOnly: true,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTodoPendingAttachmentsRow() {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final attachment in _pendingAttachments)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onLongPress: () {
                    _setState(
                      () => _pendingAttachments.removeWhere(
                        (a) => a.sha256 == attachment.sha256,
                      ),
                    );
                  },
                  child: AttachmentCard(
                    attachment: attachment,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AttachmentViewerPage(
                            attachment: attachment,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoDesktopDropTargetComposer(
    BuildContext context, {
    required SlTokens tokens,
    required ColorScheme colorScheme,
    required Widget child,
  }) {
    if (!_isDesktopPlatform) return child;

    return DropTarget(
      key: const ValueKey('todo_detail_desktop_drop_target'),
      onDragEntered: (_) {
        if (!mounted || _desktopDropActive) return;
        _setState(() => _desktopDropActive = true);
      },
      onDragExited: (_) {
        if (!mounted || !_desktopDropActive) return;
        _setState(() => _desktopDropActive = false);
      },
      onDragDone: (detail) {
        if (mounted && _desktopDropActive) {
          _setState(() => _desktopDropActive = false);
        }
        unawaited(_attachDroppedDesktopFiles(detail.files));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          border: Border.all(
            color: _desktopDropActive
                ? colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
            width: _desktopDropActive ? 2 : 1,
          ),
          color: _desktopDropActive
              ? colorScheme.primaryContainer.withOpacity(0.16)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  Widget _buildTodoComposer(
    BuildContext context, {
    required SlTokens tokens,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final useCompactComposer = !_isDesktopPlatform;

    final compactComposer = SlFocusRing(
      key: const ValueKey('todo_detail_composer'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: SlSurface(
        color: tokens.surface2,
        borderColor: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTodoPendingAttachmentsRow(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    // ignore: deprecated_member_use
                    onKey: _handleTodoComposerOnKey,
                    child: TextField(
                      key: const ValueKey('todo_detail_input'),
                      focusNode: _noteInputFocusNode,
                      controller: _noteController,
                      decoration: InputDecoration(
                        hintText: context.t.actions.todoDetail.noteHint,
                        border: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: 6,
                    ),
                  ),
                ),
                _buildTodoCompactComposerActions(
                  context,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final desktopComposer = _buildTodoDesktopDropTargetComposer(
      context,
      tokens: tokens,
      colorScheme: colorScheme,
      child: SlFocusRing(
        key: const ValueKey('todo_detail_composer'),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        child: SlSurface(
          color: tokens.surface2,
          borderColor: tokens.borderSubtle,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTodoPendingAttachmentsRow(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Focus(
                      // ignore: deprecated_member_use
                      onKey: _handleTodoComposerOnKey,
                      child: TextField(
                        key: const ValueKey('todo_detail_input'),
                        focusNode: _noteInputFocusNode,
                        controller: _noteController,
                        decoration: InputDecoration(
                          hintText: context.t.actions.todoDetail.noteHint,
                          border: InputBorder.none,
                          filled: false,
                        ),
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 1,
                        maxLines: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ListenableBuilder(
                    listenable: _noteInputFocusNode,
                    builder: (context, child) {
                      if (!_noteInputFocusNode.hasFocus) {
                        return const SizedBox.shrink();
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTodoComposerMarkdownEditorButton(context),
                          if (_supportsImageUpload ||
                              _supportsDesktopRecordAudioAction)
                            const SizedBox(width: 8),
                        ],
                      );
                    },
                  ),
                  if (_supportsImageUpload ||
                      _supportsDesktopRecordAudioAction) ...[
                    if (_supportsDesktopRecordAudioAction) ...[
                      SlIconButton(
                        key: const ValueKey('todo_detail_record_audio'),
                        icon: Icons.mic_rounded,
                        size: 44,
                        iconSize: 22,
                        tooltip: context.t.chat.attachRecordAudio,
                        onPressed: _isComposerBusy
                            ? null
                            : () => unawaited(_recordAndAttachAudioFromSheet()),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_supportsImageUpload) ...[
                      SlIconButton(
                        key: const ValueKey('todo_detail_attach'),
                        icon: Icons.add_rounded,
                        size: 44,
                        iconSize: 22,
                        tooltip: context.t.actions.todoDetail.attach,
                        onPressed:
                            _isComposerBusy ? null : _openTodoAttachmentSheet,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _noteController,
                    builder: (context, value, child) {
                      final hasText = value.text.trim().isNotEmpty;
                      final canSend = hasText || _pendingAttachments.isNotEmpty;
                      if (!canSend) {
                        return const SizedBox.shrink();
                      }
                      return SlButton(
                        buttonKey: const ValueKey('todo_detail_send'),
                        icon: const Icon(
                          Icons.send_rounded,
                          size: 18,
                        ),
                        variant: SlButtonVariant.primary,
                        onPressed: _isComposerBusy
                            ? null
                            : () => unawaited(_appendNote()),
                        child: Text(context.t.common.actions.send),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: useCompactComposer ? compactComposer : desktopComposer,
    );
  }
}
