part of 'chat_page.dart';

enum _AudioRecordingRecoveryAction {
  recover,
  discard,
}

extension _ChatPageStateMethodsFAudioRecordingRecovery on _ChatPageState {
  Future<void> _checkPendingRecordedAudioRecoveryIfNeeded() async {
    if (_audioRecordingRecoveryChecked) return;
    _audioRecordingRecoveryChecked = true;

    final snapshot = await AudioRecordingRecoveryStore.loadRecoverableSession();
    if (!mounted || snapshot == null) return;

    final existingPaths = await _resolveExistingRecoverableAudioPaths(
      snapshot.recoverableSegmentPaths,
    );
    if (existingPaths.isEmpty) {
      await AudioRecordingRecoveryStore.clearSession(
        expectedSessionId: snapshot.sessionId,
      );
      return;
    }

    if (_isComposerBusy) {
      _audioRecordingRecoveryChecked = false;
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        unawaited(_checkPendingRecordedAudioRecoveryIfNeeded());
      });
      return;
    }

    final action = await _showRecordedAudioRecoveryDialog(
      recoverableSegmentCount: existingPaths.length,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _AudioRecordingRecoveryAction.recover:
        await _recoverAndSendRecordedAudioSegments(snapshot, existingPaths);
        break;
      case _AudioRecordingRecoveryAction.discard:
        await _discardRecoveredAudioSegments(snapshot, existingPaths);
        break;
    }
  }

  Future<List<String>> _resolveExistingRecoverableAudioPaths(
    List<String> candidatePaths,
  ) async {
    final known = <String>{};
    final existing = <String>[];

    for (final raw in candidatePaths) {
      final path = raw.trim();
      if (path.isEmpty || !known.add(path)) continue;
      try {
        final file = File(path);
        if (await file.exists()) {
          existing.add(path);
        }
      } catch (_) {
        // Skip unreadable paths.
      }
    }

    return existing;
  }

  Future<_AudioRecordingRecoveryAction?> _showRecordedAudioRecoveryDialog({
    required int recoverableSegmentCount,
  }) {
    if (!mounted) {
      return Future<_AudioRecordingRecoveryAction?>.value(null);
    }

    final details = _audioRecoveryLocalized(
      zh: '检测到上次录音中断，找到 $recoverableSegmentCount 段可恢复音频。你可以恢复并发送，或直接丢弃。',
      en: 'An interrupted recording was found ($recoverableSegmentCount segments). You can recover and send it, or discard it.',
    );

    return showDialog<_AudioRecordingRecoveryAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _audioRecoveryLocalized(
              zh: '检测到未完成录音',
              en: 'Interrupted recording detected',
            ),
          ),
          content: Text(details),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  _AudioRecordingRecoveryAction.discard,
                );
              },
              child: Text(
                _audioRecoveryLocalized(
                  zh: '丢弃',
                  en: 'Discard',
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  _AudioRecordingRecoveryAction.recover,
                );
              },
              child: Text(
                _audioRecoveryLocalized(
                  zh: '恢复并发送',
                  en: 'Recover & Send',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _recoverAndSendRecordedAudioSegments(
    RecordedAudioRecoverySnapshot snapshot,
    List<String> segmentPaths,
  ) async {
    final segmentBytes = await _readRecordedAudioSegmentBytes(segmentPaths);
    if (segmentBytes.isEmpty) {
      _showAudioErrorSnackBar(
        'recording_bytes_empty',
        retryAction: _AudioSnackBarRetryAction.retryRecording,
      );
      await _discardRecoveredAudioSegments(snapshot, segmentPaths);
      return;
    }

    final bytes = await _stitchRecordedAudioSegmentsToM4a(segmentBytes);
    if (bytes.isEmpty) {
      _showAudioErrorSnackBar(
        'recording_segments_stitch_empty',
        retryAction: _AudioSnackBarRetryAction.retryRecording,
      );
      await _discardRecoveredAudioSegments(snapshot, segmentPaths);
      return;
    }

    await _uploadRecordedAudioWithRecovery(
      bytes,
      filename: 'recording_recovered_${snapshot.startedAtMs}.m4a',
    );

    if (_pendingAudioUploadRetry == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _audioRecoveryLocalized(
                zh: '已恢复并发送上次中断的录音。',
                en: 'Recovered and sent interrupted recording.',
              ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      await _discardRecoveredAudioSegments(snapshot, segmentPaths);
    }
  }

  Future<void> _discardRecoveredAudioSegments(
    RecordedAudioRecoverySnapshot snapshot,
    List<String> segmentPaths,
  ) async {
    final known = <String>{};
    for (final raw in segmentPaths) {
      final path = raw.trim();
      if (path.isEmpty || !known.add(path)) continue;
      try {
        await File(path).delete();
      } catch (_) {
        // Ignore cleanup failures.
      }
    }

    await AudioRecordingRecoveryStore.clearSession(
      expectedSessionId: snapshot.sessionId,
    );
  }

  String _audioRecoveryLocalized({
    required String zh,
    required String en,
  }) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('zh') ? zh : en;
  }
}
