part of 'chat_page.dart';

const String _kRecordedAudioMimeType = 'audio/mp4';
const Duration _kPressToTalkListenFor = Duration(seconds: 90);
const Duration _kPressToTalkFinalizeTimeout = Duration(seconds: 2);
const Duration _kPressToTalkPollInterval = Duration(milliseconds: 60);

enum _AudioRecordingSheetAction {
  stop,
  cancel,
}

enum _AudioFailureContext {
  speechToText,
  recording,
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
    if (_sending ||
        _asking ||
        _recordingAudio ||
        _pressToTalkActive ||
        _pressToTalkRecognizing) {
      return;
    }
    if (!_supportsPressToTalk || !_voiceInputMode) return;
    if (!mounted) return;

    final locale = Localizations.localeOf(context);
    final sessionToken = ++_pressToTalkSessionToken;
    _setState(() {
      _pressToTalkActive = true;
      _pressToTalkRecognizing = false;
      _pressToTalkTranscript = '';
    });

    final started = await _startSpeechToTextCapture(
      locale: locale,
      onWords: (words) {
        if (_pressToTalkSessionToken != sessionToken) return;
        _pressToTalkTranscript = words.trim();
      },
      listenFor: _kPressToTalkListenFor,
    );

    if (!mounted) return;
    if (!_pressToTalkActive && !_pressToTalkRecognizing) {
      if (started) {
        await _stopSpeechToTextCapture();
      }
      return;
    }

    if (!started) {
      _setState(() {
        _pressToTalkActive = false;
        _pressToTalkRecognizing = false;
      });
    }
  }

  Future<void> _finishPressToTalkCapture({
    required bool commitTranscript,
  }) async {
    if (!_pressToTalkActive) return;

    final sessionToken = _pressToTalkSessionToken;
    if (mounted) {
      _setState(() {
        _pressToTalkActive = false;
        _pressToTalkRecognizing = commitTranscript;
        if (commitTranscript) {
          _voiceInputMode = false;
        }
      });
    }

    await _stopSpeechToTextCapture();

    final transcript = commitTranscript
        ? await _waitForPressToTalkTranscript(sessionToken: sessionToken)
        : '';

    if (!mounted) return;
    _setState(() {
      _pressToTalkRecognizing = false;
      _pressToTalkTranscript = '';
    });

    if (commitTranscript && transcript.isNotEmpty) {
      _appendTranscriptToComposer(transcript);
      return;
    }

    if (commitTranscript) {
      _showAudioErrorSnackBar(
        'speech_result_empty',
        context: _AudioFailureContext.speechToText,
      );
    }
  }

  Future<String> _waitForPressToTalkTranscript({
    required int sessionToken,
  }) async {
    var transcript = _pressToTalkTranscript.trim();
    if (transcript.isNotEmpty) return transcript;

    final deadline = DateTime.now().add(_kPressToTalkFinalizeTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_kPressToTalkPollInterval);
      if (!mounted || _pressToTalkSessionToken != sessionToken) {
        return '';
      }

      transcript = _pressToTalkTranscript.trim();
      if (transcript.isNotEmpty) {
        return transcript;
      }
    }

    return '';
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

    bool hasPermission;
    try {
      hasPermission = await _audioRecorder.hasPermission();
    } catch (error) {
      _showAudioErrorSnackBar(
        error,
        context: _AudioFailureContext.recording,
      );
      return;
    }

    if (!hasPermission) {
      _showAudioErrorSnackBar(
        'permission_denied',
        context: _AudioFailureContext.recording,
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
    } catch (error) {
      _showAudioErrorSnackBar(
        error,
        context: _AudioFailureContext.recording,
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
    if (_sending || _asking || _pressToTalkActive || _pressToTalkRecognizing) {
      return;
    }

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

    bool hasPermission;
    try {
      hasPermission = await speech.hasPermission;
    } catch (_) {
      hasPermission = false;
    }

    bool isAvailable;
    try {
      isAvailable = await speech.initialize();
    } catch (_) {
      isAvailable = false;
    }

    if (!isAvailable) {
      _showAudioErrorSnackBar(
        hasPermission ? 'speech_recognition_unavailable' : 'permission_denied',
        context: _AudioFailureContext.speechToText,
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
    } catch (error) {
      _showAudioErrorSnackBar(
        error,
        context: _AudioFailureContext.speechToText,
      );
      return false;
    }
  }

  Future<void> _stopSpeechToTextCapture() async {
    final speech = _speechToTextInstance;
    if (speech == null) return;

    try {
      await speech.stop();
      return;
    } catch (_) {
      // Fall through to cancel.
    }

    try {
      await speech.cancel();
    } catch (_) {
      // Ignore stop failures.
    }
  }

  void _showAudioErrorSnackBar(
    Object error, {
    required _AudioFailureContext context,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(
        content: Text(
          _describeAudioError(
            error,
            context: context,
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _describeAudioError(
    Object error, {
    required _AudioFailureContext context,
  }) {
    final raw = '$error';
    final normalized = raw.toLowerCase();

    if (normalized.contains('permission') ||
        normalized.contains('denied') ||
        normalized.contains('record_audio') ||
        normalized.contains('not allowed')) {
      return this.context.t.chat.audioRecordPermissionDenied;
    }

    if (normalized.contains('speech_recognition_unavailable') ||
        normalized.contains('speech recognizer') ||
        normalized.contains('recognizer not available') ||
        normalized.contains('recognizer unavailable') ||
        normalized.contains('service not available')) {
      return _localizedByLanguage(
        zh: '当前设备语音识别服务不可用，请检查系统语音服务设置。',
        en: 'Speech recognition service is unavailable on this device.',
      );
    }

    if (normalized.contains('speech_result_empty') ||
        normalized.contains('no match') ||
        normalized.contains('no speech')) {
      return _localizedByLanguage(
        zh: '没有识别到语音内容，请再试一次。',
        en: 'No speech was recognized. Please try again.',
      );
    }

    if (normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('timed out')) {
      return _localizedByLanguage(
        zh: '语音识别网络异常，请检查网络后重试。',
        en: 'Speech recognition network issue. Please check your connection.',
      );
    }

    if (normalized.contains('audio session') ||
        normalized.contains('microphone') && normalized.contains('in use') ||
        normalized.contains('busy')) {
      return _localizedByLanguage(
        zh: '麦克风可能正被其他应用占用，请稍后重试。',
        en: 'Microphone appears busy. Please close other apps using audio.',
      );
    }

    if (normalized.contains('no microphone') ||
        normalized.contains('no input device') ||
        normalized.contains('input device') ||
        normalized.contains('audio source') ||
        normalized.contains('microphone unavailable')) {
      return _localizedByLanguage(
        zh: '未检测到可用麦克风，请检查系统输入设备设置。',
        en: 'No microphone input is available. Check system input settings.',
      );
    }

    if (normalized.contains('recording_path_empty') ||
        normalized.contains('recording_bytes_empty')) {
      return _localizedByLanguage(
        zh: '录音内容为空，请重试并确保麦克风输入正常。',
        en: 'Recording is empty. Please retry and check microphone input.',
      );
    }

    if (context == _AudioFailureContext.speechToText &&
        (normalized.contains('cancelled') || normalized.contains('canceled'))) {
      return _localizedByLanguage(
        zh: '语音识别已取消。',
        en: 'Speech recognition was canceled.',
      );
    }

    return this.context.t.chat.audioRecordFailed(error: raw);
  }

  String _pressToTalkRecognizingTitle() {
    return _localizedByLanguage(
      zh: '正在识别…',
      en: 'Recognizing…',
    );
  }

  String _pressToTalkRecognizingHint() {
    return _localizedByLanguage(
      zh: '请稍候，识别结果会自动填入输入框。',
      en: 'Please wait, recognized text will be inserted automatically.',
    );
  }

  String _localizedByLanguage({
    required String zh,
    required String en,
  }) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
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
