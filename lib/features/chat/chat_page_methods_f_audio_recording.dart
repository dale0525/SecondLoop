part of 'chat_page.dart';

const String _kRecordedAudioMimeType = 'audio/mp4';

enum _AudioRecordingSheetAction {
  stop,
  cancel,
}

extension _ChatPageStateMethodsFAudioRecording on _ChatPageState {
  AudioRecorder get _audioRecorder =>
      _audioRecorderInstance ??= AudioRecorder();

  Future<void> _recordAndSendAudioFromSheet() async {
    if (_isComposerBusy) return;
    if (!_supportsAudioRecording) return;

    bool hasPermission;
    try {
      hasPermission = await _audioRecorder.hasPermission();
    } catch (error) {
      _showAudioErrorSnackBar(error);
      return;
    }

    if (!hasPermission) {
      _showAudioErrorSnackBar('permission_denied');
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
      _showAudioErrorSnackBar(error);
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
    if (_sending || _asking) {
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

  void _showAudioErrorSnackBar(Object error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_describeAudioError(error)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _describeAudioError(Object error) {
    final raw = '$error';
    final normalized = raw.toLowerCase();

    if (normalized.contains('permission') ||
        normalized.contains('denied') ||
        normalized.contains('record_audio') ||
        normalized.contains('not allowed')) {
      return context.t.chat.audioRecordPermissionDenied;
    }

    if (normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('timed out')) {
      return _localizedByLanguage(
        zh: '录音上传网络异常，请检查网络后重试。',
        en: 'Audio upload network issue. Please check your connection.',
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

    return context.t.chat.audioRecordFailed(error: raw);
  }

  String _localizedByLanguage({
    required String zh,
    required String en,
  }) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }
}
