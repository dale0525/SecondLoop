part of 'chat_page.dart';

const String _kRecordedAudioMimeType = 'audio/mp4';
const Duration kAudioRecordingMaxDuration = Duration(minutes: 30);
const Duration _kAudioRecordingUiTick = Duration(milliseconds: 250);

enum AudioRecordingFailureKind {
  permissionDenied,
  network,
  microphoneBusy,
  noMicrophone,
  emptyRecording,
  canceled,
  unknown,
}

enum _AudioRecordingSheetAction {
  stop,
  cancel,
}

enum _AudioSnackBarRetryAction {
  retryRecording,
  retryUpload,
}

final class _PendingAudioUploadRetry {
  _PendingAudioUploadRetry({
    required this.audioBytes,
    required this.filename,
  });

  final Uint8List audioBytes;
  final String filename;
}

String formatAudioRecordingElapsed(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60);
  final seconds = safe.inSeconds.remainder(60);

  String two(int value) => value.toString().padLeft(2, '0');

  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

double normalizeAudioRecordingAmplitude(double dbfs) {
  if (!dbfs.isFinite) return 0;
  final clamped = dbfs.clamp(-60.0, 0.0).toDouble();
  return (clamped + 60.0) / 60.0;
}

AudioRecordingFailureKind classifyAudioRecordingFailure(Object error) {
  final normalized = '$error'.toLowerCase();

  if (normalized.contains('permission') ||
      normalized.contains('denied') ||
      normalized.contains('record_audio') ||
      normalized.contains('not allowed')) {
    return AudioRecordingFailureKind.permissionDenied;
  }

  if (normalized.contains('network') ||
      normalized.contains('timeout') ||
      normalized.contains('timed out') ||
      normalized.contains('socket')) {
    return AudioRecordingFailureKind.network;
  }

  if (normalized.contains('audio session') ||
      normalized.contains('microphone') && normalized.contains('in use') ||
      normalized.contains('busy')) {
    return AudioRecordingFailureKind.microphoneBusy;
  }

  if (normalized.contains('no microphone') ||
      normalized.contains('no input device') ||
      normalized.contains('input device') ||
      normalized.contains('audio source') ||
      normalized.contains('microphone unavailable')) {
    return AudioRecordingFailureKind.noMicrophone;
  }

  if (normalized.contains('recording_path_empty') ||
      normalized.contains('recording_bytes_empty')) {
    return AudioRecordingFailureKind.emptyRecording;
  }

  if (normalized.contains('cancelled') ||
      normalized.contains('canceled') ||
      normalized.contains('cancelled_by_user') ||
      normalized.contains('cancelled by user')) {
    return AudioRecordingFailureKind.canceled;
  }

  return AudioRecordingFailureKind.unknown;
}

bool canRetryAudioFailure(AudioRecordingFailureKind kind) {
  switch (kind) {
    case AudioRecordingFailureKind.network:
    case AudioRecordingFailureKind.microphoneBusy:
    case AudioRecordingFailureKind.unknown:
      return true;
    case AudioRecordingFailureKind.permissionDenied:
    case AudioRecordingFailureKind.noMicrophone:
    case AudioRecordingFailureKind.emptyRecording:
    case AudioRecordingFailureKind.canceled:
      return false;
  }
}

bool shouldOpenMicrophoneSettings(AudioRecordingFailureKind kind) {
  return kind == AudioRecordingFailureKind.permissionDenied ||
      kind == AudioRecordingFailureKind.noMicrophone;
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
      _showAudioErrorSnackBar(
        error,
        retryAction: _AudioSnackBarRetryAction.retryRecording,
      );
      return;
    }

    if (!hasPermission) {
      _showAudioErrorSnackBar(
        'permission_denied',
        retryAction: _AudioSnackBarRetryAction.retryRecording,
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

      final action = await _showAudioRecordingSheet(startedAt: startedAt);
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

      await _uploadRecordedAudioWithRecovery(
        bytes,
        filename: 'recording_${startedAt.millisecondsSinceEpoch}.m4a',
      );
    } catch (error) {
      _showAudioErrorSnackBar(
        error,
        retryAction: _AudioSnackBarRetryAction.retryRecording,
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

  Future<void> _uploadRecordedAudioWithRecovery(
    Uint8List audioBytes, {
    required String filename,
  }) async {
    try {
      await _sendRecordedAudioAttachment(
        audioBytes,
        filename: filename,
      );
      _pendingAudioUploadRetry = null;
    } catch (error) {
      _pendingAudioUploadRetry = _PendingAudioUploadRetry(
        audioBytes: Uint8List.fromList(audioBytes),
        filename: filename,
      );
      _showAudioErrorSnackBar(
        error,
        retryAction: _AudioSnackBarRetryAction.retryUpload,
      );
    }
  }

  Future<void> _retryPendingRecordedAudioUpload() async {
    final pending = _pendingAudioUploadRetry;
    if (pending == null) return;

    await _uploadRecordedAudioWithRecovery(
      pending.audioBytes,
      filename: pending.filename,
    );
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

  Future<_AudioRecordingSheetAction?> _showAudioRecordingSheet({
    required DateTime startedAt,
  }) {
    Timer? ticker;
    var initialized = false;
    var paused = false;
    var togglingPause = false;
    var pausedDuration = Duration.zero;
    DateTime? pausedAt;
    var elapsed = Duration.zero;
    var normalizedAmplitude = 0.0;

    Duration computeElapsed() {
      final anchor = paused ? (pausedAt ?? DateTime.now()) : DateTime.now();
      final next = anchor.difference(startedAt) - pausedDuration;
      if (next.isNegative) return Duration.zero;
      return next;
    }

    Future<void> refreshUi(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      final nextElapsed = computeElapsed();
      var nextAmplitude = normalizedAmplitude;
      if (!paused) {
        try {
          final amplitude = await _audioRecorder.getAmplitude();
          nextAmplitude = normalizeAudioRecordingAmplitude(amplitude.current);
        } catch (_) {
          nextAmplitude = 0;
        }
      } else {
        nextAmplitude = 0;
      }

      if (!sheetContext.mounted) return;

      if (nextElapsed >= kAudioRecordingMaxDuration) {
        Navigator.of(sheetContext).pop(_AudioRecordingSheetAction.stop);
        return;
      }

      setSheetState(() {
        elapsed = nextElapsed;
        normalizedAmplitude = nextAmplitude;
      });
    }

    Future<void> togglePause(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      if (togglingPause) return;

      setSheetState(() => togglingPause = true);
      try {
        if (paused) {
          final pausedAnchor = pausedAt;
          await _audioRecorder.resume();
          if (pausedAnchor != null) {
            pausedDuration += DateTime.now().difference(pausedAnchor);
          }
          paused = false;
          pausedAt = null;
        } else {
          await _audioRecorder.pause();
          pausedAt = DateTime.now();
          paused = true;
        }
        if (!sheetContext.mounted) return;
        await refreshUi(sheetContext, setSheetState);
      } catch (error) {
        _showAudioErrorSnackBar(
          error,
          retryAction: _AudioSnackBarRetryAction.retryRecording,
        );
      } finally {
        if (sheetContext.mounted) {
          setSheetState(() => togglingPause = false);
        }
      }
    }

    return showModalBottomSheet<_AudioRecordingSheetAction>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            if (!initialized) {
              initialized = true;
              elapsed = computeElapsed();
              ticker = Timer.periodic(_kAudioRecordingUiTick, (_) {
                unawaited(refreshUi(sheetContext, setSheetState));
              });
              unawaited(refreshUi(sheetContext, setSheetState));
            }

            final elapsedLabel = formatAudioRecordingElapsed(elapsed);
            final pauseResumeLabel = paused
                ? _localizedByLanguage(zh: '继续', en: 'Resume')
                : _localizedByLanguage(zh: '暂停', en: 'Pause');
            final statusHint = paused
                ? _localizedByLanguage(
                    zh: '录音已暂停，点击继续后可接着录。',
                    en: 'Recording paused. Tap Resume when ready.',
                  )
                : context.t.chat.recordingHint;
            final maxDurationHint = _localizedByLanguage(
              zh: '最长 ${formatAudioRecordingElapsed(kAudioRecordingMaxDuration)}，到时会自动停止并发送。',
              en: 'Up to ${formatAudioRecordingElapsed(kAudioRecordingMaxDuration)}. Recording auto-stops and sends at limit.',
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      key: const ValueKey('chat_recording_status'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.mic_rounded),
                      title: Text(context.t.chat.recordingInProgress),
                      subtitle: Text(statusHint),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        elapsedLabel,
                        key: const ValueKey('chat_recording_elapsed'),
                        style: Theme.of(sheetContext)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRecordingWaveform(
                      normalizedAmplitude,
                      paused: paused,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      maxDurationHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const ValueKey('chat_recording_cancel'),
                            onPressed: () {
                              Navigator.of(sheetContext)
                                  .pop(_AudioRecordingSheetAction.cancel);
                            },
                            icon: const Icon(Icons.close_rounded),
                            label: Text(context.t.common.actions.cancel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const ValueKey('chat_recording_pause_resume'),
                            onPressed: togglingPause
                                ? null
                                : () => unawaited(
                                      togglePause(
                                        sheetContext,
                                        setSheetState,
                                      ),
                                    ),
                            icon: Icon(
                              paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                            label: Text(pauseResumeLabel),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey('chat_recording_stop'),
                            onPressed: () {
                              Navigator.of(sheetContext)
                                  .pop(_AudioRecordingSheetAction.stop);
                            },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: Text(context.t.common.actions.stop),
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
      },
    ).whenComplete(() {
      ticker?.cancel();
    });
  }

  Widget _buildRecordingWaveform(
    double normalizedAmplitude, {
    required bool paused,
  }) {
    final amplitude = normalizedAmplitude.clamp(0.0, 1.0).toDouble();
    final bars = List<Widget>.generate(9, (index) {
      final distanceToCenter = (index - 4).abs().toDouble();
      final emphasis = 1.0 - (distanceToCenter * 0.12);
      final dynamicBoost = paused ? 0.0 : amplitude * 22 * emphasis;
      final targetHeight = 10 + dynamicBoost;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 6,
        height: targetHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: paused
              ? Theme.of(context).colorScheme.outline
              : Theme.of(context).colorScheme.primary,
        ),
      );
    });

    return Center(
      child: Row(
        key: const ValueKey('chat_recording_waveform'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < bars.length; i++) ...[
            bars[i],
            if (i != bars.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  void _showAudioErrorSnackBar(
    Object error, {
    _AudioSnackBarRetryAction? retryAction,
  }) {
    if (!mounted) return;

    final kind = classifyAudioRecordingFailure(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_describeAudioError(error)),
        duration: const Duration(seconds: 3),
        action: _buildAudioErrorSnackBarAction(kind, retryAction),
      ),
    );
  }

  SnackBarAction? _buildAudioErrorSnackBarAction(
    AudioRecordingFailureKind kind,
    _AudioSnackBarRetryAction? retryAction,
  ) {
    if (shouldOpenMicrophoneSettings(kind)) {
      return SnackBarAction(
        label: _localizedByLanguage(zh: '去设置', en: 'Settings'),
        onPressed: () => unawaited(_openMicrophoneSettings()),
      );
    }

    if (retryAction == _AudioSnackBarRetryAction.retryUpload &&
        canRetryAudioFailure(kind)) {
      return SnackBarAction(
        label: context.t.common.actions.retry,
        onPressed: () => unawaited(_retryPendingRecordedAudioUpload()),
      );
    }

    if (retryAction == _AudioSnackBarRetryAction.retryRecording &&
        canRetryAudioFailure(kind)) {
      return SnackBarAction(
        label: context.t.common.actions.retry,
        onPressed: () => unawaited(_recordAndSendAudioFromSheet()),
      );
    }

    return null;
  }

  Future<void> _openMicrophoneSettings() async {
    for (final uri in _microphoneSettingsUris()) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return;
      } catch (_) {
        // Try next candidate.
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedByLanguage(
            zh: '无法自动打开系统设置，请手动前往系统隐私里开启麦克风权限。',
            en: 'Unable to open system settings automatically. Please enable microphone permission manually.',
          ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<Uri> _microphoneSettingsUris() {
    if (kIsWeb) return const <Uri>[];

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return <Uri>[Uri.parse('app-settings:')];
      case TargetPlatform.macOS:
        return <Uri>[
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
          ),
          Uri.parse('x-apple.systempreferences:'),
        ];
      case TargetPlatform.windows:
        return <Uri>[
          Uri.parse('ms-settings:privacy-microphone'),
          Uri.parse('ms-settings:sound'),
        ];
      case TargetPlatform.linux:
        return const <Uri>[];
      case TargetPlatform.fuchsia:
        return const <Uri>[];
    }
  }

  String _describeAudioError(Object error) {
    final kind = classifyAudioRecordingFailure(error);

    switch (kind) {
      case AudioRecordingFailureKind.permissionDenied:
        return context.t.chat.audioRecordPermissionDenied;
      case AudioRecordingFailureKind.network:
        return _localizedByLanguage(
          zh: '录音上传网络异常，请检查网络后重试。',
          en: 'Audio upload network issue. Please check your connection.',
        );
      case AudioRecordingFailureKind.microphoneBusy:
        return _localizedByLanguage(
          zh: '麦克风可能正被其他应用占用，请稍后重试。',
          en: 'Microphone appears busy. Please close other apps using audio.',
        );
      case AudioRecordingFailureKind.noMicrophone:
        return _localizedByLanguage(
          zh: '未检测到可用麦克风，请检查系统输入设备设置。',
          en: 'No microphone input is available. Check system input settings.',
        );
      case AudioRecordingFailureKind.emptyRecording:
        return _localizedByLanguage(
          zh: '录音内容为空，请重试并确保麦克风输入正常。',
          en: 'Recording is empty. Please retry and check microphone input.',
        );
      case AudioRecordingFailureKind.canceled:
        return _localizedByLanguage(
          zh: '录音已取消。',
          en: 'Recording canceled.',
        );
      case AudioRecordingFailureKind.unknown:
        return context.t.chat.audioRecordFailed(error: '$error');
    }
  }

  String _localizedByLanguage({
    required String zh,
    required String en,
  }) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }
}
