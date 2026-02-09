part of 'chat_page.dart';

const String _kRecordedAudioMimeType = 'audio/mp4';

enum _AudioRecordingSheetAction {
  stop,
  cancel,
}

extension _ChatPageStateMethodsFAudioRecording on _ChatPageState {
  AudioRecorder get _audioRecorder =>
      _audioRecorderInstance ??= AudioRecorder();

  SpeechToText get _speechToText => _speechToTextInstance ??= SpeechToText();

  Future<void> _recordAndSendAudioFromSheet() async {
    if (_sending || _asking || _recordingAudio) return;
    if (!_supportsAudioRecording) return;

    final hasPermission = await _audioRecorder.hasPermission();
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

    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final tempDir = await getTemporaryDirectory();
    final startedAt = DateTime.now();
    final filePath =
        '${tempDir.path}/secondloop_record_${startedAt.millisecondsSinceEpoch}.m4a';

    String transcript = '';
    var recorderStarted = false;
    String? recordedPath;

    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: filePath,
      );
      recorderStarted = true;

      await _startSpeechToTextCapture(
        locale: locale,
        onWords: (words) {
          final normalized = words.trim();
          if (normalized.isEmpty) return;
          transcript = normalized;
        },
      );

      if (!mounted) return;
      _setState(() => _recordingAudio = true);
      final action = await _showAudioRecordingSheet();
      final shouldProcess = action == _AudioRecordingSheetAction.stop;

      recordedPath = await _audioRecorder.stop();
      recorderStarted = false;
      await _stopSpeechToTextCapture();

      if (!shouldProcess) return;

      final path = recordedPath?.trim();
      if (path == null || path.isEmpty) {
        throw Exception('recording_path_empty');
      }
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('recording_bytes_empty');
      }

      final duration = DateTime.now().difference(startedAt);
      await _handleRecordedAudioPayload(
        duration: duration,
        audioBytes: bytes,
        transcript: transcript,
        filename: 'recording_${startedAt.millisecondsSinceEpoch}.m4a',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.audioRecordFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (recorderStarted) {
        try {
          await _audioRecorder.stop();
        } catch (_) {
          // Ignore stop errors during cleanup.
        }
      }
      await _stopSpeechToTextCapture();

      final pathToDelete = recordedPath?.trim();
      if (pathToDelete != null && pathToDelete.isNotEmpty) {
        try {
          await File(pathToDelete).delete();
        } catch (_) {
          // Ignore cleanup failures.
        }
      }

      if (mounted) {
        _setState(() => _recordingAudio = false);
      }
    }
  }

  Future<_AudioRecordingSheetAction?> _showAudioRecordingSheet() {
    return showModalBottomSheet<_AudioRecordingSheetAction>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('chat_recording_status'),
                leading: const Icon(Icons.mic_rounded),
                title: Text(context.t.chat.recordingInProgress),
                subtitle: Text(context.t.chat.recordingHint),
              ),
              ListTile(
                key: const ValueKey('chat_recording_stop'),
                leading: const Icon(Icons.stop_circle_outlined),
                title: Text(context.t.common.actions.stop),
                onTap: () {
                  Navigator.of(sheetContext)
                      .pop(_AudioRecordingSheetAction.stop);
                },
              ),
              ListTile(
                key: const ValueKey('chat_recording_cancel'),
                leading: const Icon(Icons.close_rounded),
                title: Text(context.t.common.actions.cancel),
                onTap: () {
                  Navigator.of(sheetContext)
                      .pop(_AudioRecordingSheetAction.cancel);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleRecordedAudioPayload({
    required Duration duration,
    required Uint8List audioBytes,
    required String transcript,
    required String filename,
  }) async {
    if (_sending || _asking) return;

    _setState(() => _sending = true);
    try {
      final dispatch = decideAudioRecordingDispatch(duration);
      if (dispatch == AudioRecordingDispatch.transcribeAsText) {
        final normalized = transcript.trim();
        if (normalized.isNotEmpty) {
          await _sendTextMessageFromAudioTranscript(normalized);
          return;
        }

        await _sendFileAttachment(
          audioBytes,
          _kRecordedAudioMimeType,
          filename: filename,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.t.chat.audioRecordNoSpeechFallback),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      await _sendFileAttachment(
        audioBytes,
        _kRecordedAudioMimeType,
        filename: filename,
      );
    } finally {
      if (mounted) _setState(() => _sending = false);
    }
  }

  Future<void> _sendTextMessageFromAudioTranscript(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;
    final syncEngine = SyncEngineScope.maybeOf(context);
    final sentAsUrlAttachment = await _trySendTextAsUrlAttachment(normalized);
    Message? sentMessage;

    if (!sentAsUrlAttachment) {
      sentMessage = await backend.insertMessage(
        sessionKey,
        widget.conversation.id,
        role: 'user',
        content: normalized,
      );
      syncEngine?.notifyLocalMutation();
      if (mounted) {
        _refreshAfterAttachmentMutation();
      }
    }

    if (sentMessage != null) {
      _messageAutoActionsQueue ??= MessageAutoActionsQueue(
        backend: backend,
        sessionKey: sessionKey,
        handler: _handleMessageAutoActions,
      );
      _messageAutoActionsQueue!.enqueue(
        message: sentMessage,
        rawText: normalized,
        createdAtMs: sentMessage.createdAtMs,
      );
    }
  }

  Future<void> _startSpeechToTextCapture({
    required Locale locale,
    required void Function(String words) onWords,
  }) async {
    final speech = _speechToText;

    bool isAvailable;
    try {
      isAvailable = await speech.initialize();
    } catch (_) {
      isAvailable = false;
    }
    if (!isAvailable) return;

    final localeId = await _resolveSpeechLocaleId(locale);

    try {
      await speech.listen(
        localeId: localeId,
        listenFor: kAudioRecordingTranscribeThreshold,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          if (result.recognizedWords.trim().isEmpty) return;
          onWords(result.recognizedWords);
        },
      );
    } catch (_) {
      // Ignore speech-to-text failures and fallback to sending audio file.
    }
  }

  Future<void> _stopSpeechToTextCapture() async {
    final speech = _speechToTextInstance;
    if (speech == null) return;

    try {
      if (speech.isListening) {
        await speech.stop();
      } else {
        await speech.cancel();
      }
    } catch (_) {
      // Ignore speech-to-text stop failures.
    }
  }

  Future<String?> _resolveSpeechLocaleId(Locale locale) async {
    final speech = _speechToText;
    List<LocaleName> locales;
    try {
      locales = await speech.locales();
    } catch (_) {
      return null;
    }
    if (locales.isEmpty) return null;

    final languageTag = locale.toLanguageTag().toLowerCase();
    final underscoreTag = locale.toString().toLowerCase();

    for (final item in locales) {
      final current = item.localeId.toLowerCase();
      if (current == languageTag || current == underscoreTag) {
        return item.localeId;
      }
    }

    final langPrefix = locale.languageCode.toLowerCase();
    for (final item in locales) {
      final current = item.localeId.toLowerCase();
      if (current.startsWith(langPrefix)) {
        return item.localeId;
      }
    }

    return null;
  }
}
