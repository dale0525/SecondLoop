part of 'chat_page.dart';

const String _kRecordedAudioMimeType = 'audio/mp4';
const Duration _kPressToTalkListenFor = Duration(seconds: 90);

enum _AudioRecordingSheetAction {
  stop,
  cancel,
}

extension _ChatPageStateMethodsFAudioRecording on _ChatPageState {
  AudioRecorder get _audioRecorder =>
      _audioRecorderInstance ??= AudioRecorder();

  SpeechToText get _speechToText => _speechToTextInstance ??= SpeechToText();

  void _toggleVoiceInputMode() {
    if (_isComposerBusy) return;

    final nextValue = !_voiceInputMode;
    _setState(() => _voiceInputMode = nextValue);

    if (!nextValue && _isDesktopPlatform) {
      _inputFocusNode.requestFocus();
    }
  }

  void _onPressToTalkLongPressStart(LongPressStartDetails details) {
    unawaited(_startPressToTalkCapture());
  }

  void _onPressToTalkLongPressEnd(LongPressEndDetails details) {
    unawaited(_finishPressToTalkCapture(commitTranscript: true));
  }

  void _onPressToTalkLongPressCancel() {
    unawaited(_finishPressToTalkCapture(commitTranscript: false));
  }

  Future<void> _startPressToTalkCapture() async {
    if (_sending || _asking || _recordingAudio || _pressToTalkActive) return;
    if (!_supportsAudioRecording || !_voiceInputMode) return;
    if (!mounted) return;

    final locale = Localizations.localeOf(context);
    _setState(() {
      _pressToTalkActive = true;
      _pressToTalkTranscript = '';
    });

    final started = await _startSpeechToTextCapture(
      locale: locale,
      onWords: (words) {
        _pressToTalkTranscript = words.trim();
      },
      listenFor: _kPressToTalkListenFor,
    );

    if (!mounted) return;
    if (!_pressToTalkActive) {
      if (started) {
        await _stopSpeechToTextCapture();
      }
      return;
    }

    if (!started) {
      _setState(() => _pressToTalkActive = false);
    }
  }

  Future<void> _finishPressToTalkCapture({
    required bool commitTranscript,
  }) async {
    if (!_pressToTalkActive) return;

    await _stopSpeechToTextCapture();
    final transcript = _pressToTalkTranscript.trim();

    if (!mounted) return;
    _setState(() {
      _pressToTalkActive = false;
      _pressToTalkTranscript = '';
    });

    if (commitTranscript && transcript.isNotEmpty) {
      _appendTranscriptToComposer(transcript);
    }
  }

  void _appendTranscriptToComposer(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) return;

    final existing = _controller.text.trim();
    final nextText = existing.isEmpty ? normalized : '$existing $normalized';

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _recordAndSendAudioFromSheet() async {
    if (_isComposerBusy) return;
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

    final tempDir = await getTemporaryDirectory();
    final startedAt = DateTime.now();
    final filePath =
        '${tempDir.path}/secondloop_record_${startedAt.millisecondsSinceEpoch}.m4a';

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

      if (!mounted) return;
      _setState(() => _recordingAudio = true);

      final action = await _showAudioRecordingSheet();
      final shouldSend = action == _AudioRecordingSheetAction.stop;

      recordedPath = await _audioRecorder.stop();
      recorderStarted = false;

      if (!shouldSend) return;

      final path = recordedPath?.trim();
      if (path == null || path.isEmpty) {
        throw Exception('recording_path_empty');
      }

      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('recording_bytes_empty');
      }

      await _sendRecordedAudioAttachment(
        bytes,
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
          // Ignore stop failures during cleanup.
        }
      }

      final pathToDelete = recordedPath?.trim();
      if (pathToDelete != null && pathToDelete.isNotEmpty) {
        try {
          await File(pathToDelete).delete();
        } catch (_) {
          // Ignore file cleanup failures.
        }
      }

      if (mounted) {
        _setState(() => _recordingAudio = false);
      }
    }
  }

  Future<void> _sendRecordedAudioAttachment(
    Uint8List audioBytes, {
    required String filename,
  }) async {
    if (_sending || _asking || _pressToTalkActive) return;

    _setState(() => _sending = true);
    try {
      await _sendFileAttachment(
        audioBytes,
        _kRecordedAudioMimeType,
        filename: filename,
      );
    } finally {
      if (mounted) _setState(() => _sending = false);
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

  Future<bool> _startSpeechToTextCapture({
    required Locale locale,
    required void Function(String words) onWords,
    required Duration listenFor,
  }) async {
    final speech = _speechToText;

    bool isAvailable;
    try {
      isAvailable = await speech.initialize();
    } catch (_) {
      isAvailable = false;
    }

    if (!isAvailable) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.audioRecordPermissionDenied),
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
    }

    final localeId = await _resolveSpeechLocaleId(locale);

    try {
      await speech.listen(
        localeId: localeId,
        listenFor: listenFor,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          final normalized = result.recognizedWords.trim();
          if (normalized.isEmpty) return;
          onWords(normalized);
        },
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.chat.audioRecordFailed(error: '$e')),
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
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
      // Ignore stop failures.
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
