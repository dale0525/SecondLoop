part of 'agent_conversation_page.dart';

enum _AgentAudioRecordingSheetAction {
  stop,
  cancel,
}

extension _AgentConversationInputActions on _AgentConversationPageState {
  AgentRecordedAudioCapture get _audioCapture =>
      _audioCaptureInstance ??= createAgentRecordedAudioCapture();

  Future<void> _openComposerMarkdownEditor() async {
    if (_isComposerBusy) return;

    final result = await openChatMarkdownEditor(
      context,
      initialText: _controller.text,
      allowPlainMode: true,
      routePusher: widget.markdownEditorRoutePusher,
    );
    if (!mounted || result == null) return;

    final nextText = result.text;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
    _appendComposerAttachmentDrafts(result.draftAttachments);
    _focusNode.requestFocus();
  }

  Future<void> _recordAndAttachAudioFromSheet() async {
    if (_isComposerBusy ||
        !_supportsComposerAudioRecording ||
        _audioRecordingActionCompleter != null) {
      return;
    }

    bool hasPermission;
    try {
      hasPermission = await _audioCapture.hasPermission();
    } catch (error) {
      _showAudioRecordErrorSnackBar(error);
      return;
    }

    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.audioRecordPermissionDenied),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final startedAt = DateTime.now();
    var recorderStarted = false;
    String? recordedPath;
    Completer<_AgentAudioRecordingSheetAction>? actionCompleter;

    try {
      recordedPath = await _audioCapture.start(startedAt: startedAt);
      recorderStarted = true;

      if (!mounted) return;
      actionCompleter = Completer<_AgentAudioRecordingSheetAction>();
      _audioRecordingActionCompleter = actionCompleter;
      _setComposerRecordingAudio(true);

      final action = await actionCompleter.future;
      final shouldAttach = action == _AgentAudioRecordingSheetAction.stop;

      final stoppedPath = await _audioCapture.stop();
      recorderStarted = false;
      recordedPath =
          stoppedPath?.trim().isNotEmpty == true ? stoppedPath : recordedPath;

      if (!shouldAttach) return;

      final path = recordedPath?.trim();
      if (path == null || path.isEmpty) {
        throw Exception('recording_path_empty');
      }

      final bytes = await _audioCapture.readBytes(path);
      if (bytes.isEmpty) {
        throw Exception('recording_bytes_empty');
      }

      _appendComposerAttachmentDrafts([
        AttachmentDraftPayload(
          localId: _nextAttachmentLocalId(),
          filename: 'recording_${startedAt.millisecondsSinceEpoch}.m4a',
          mimeType: kAgentRecordedAudioMimeType,
          bytes: bytes,
        ),
      ]);
    } catch (error) {
      _showAudioRecordErrorSnackBar(error);
    } finally {
      if (recorderStarted) {
        try {
          recordedPath = await _audioCapture.stop() ?? recordedPath;
        } catch (_) {
          // Ignore stop failures during cleanup.
        }
      }

      final pathToDelete = recordedPath?.trim();
      if (pathToDelete != null && pathToDelete.isNotEmpty) {
        await _audioCapture.deleteFile(pathToDelete);
      }

      if (identical(_audioRecordingActionCompleter, actionCompleter)) {
        _audioRecordingActionCompleter = null;
      }
      _setComposerRecordingAudio(false);
    }
  }

  void _completeAudioRecordingAction(_AgentAudioRecordingSheetAction action) {
    final completer = _audioRecordingActionCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(action);
  }

  void _showAudioRecordErrorSnackBar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t.chat.audioRecordFailed(error: '$error')),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
