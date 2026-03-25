part of 'chat_page.dart';

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
      case AudioRecordingRecoveryDialogAction.recover:
        await _recoverAndAttachRecordedAudioSegments(snapshot, existingPaths);
        break;
      case AudioRecordingRecoveryDialogAction.discard:
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

  Future<AudioRecordingRecoveryDialogAction?> _showRecordedAudioRecoveryDialog({
    required int recoverableSegmentCount,
  }) {
    if (!mounted) {
      return Future<AudioRecordingRecoveryDialogAction?>.value(null);
    }

    return ChatAudioRecordingRecoveryDialog.show(
      context,
      recoverableSegmentCount: recoverableSegmentCount,
    );
  }

  Future<void> _recoverAndAttachRecordedAudioSegments(
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

    _appendComposerAttachmentDrafts(
      <AttachmentDraftPayload>[
        AttachmentDraftPayload(
          localId: _nextComposerAttachmentDraftLocalId(),
          filename: 'recording_recovered_${snapshot.startedAtMs}.m4a',
          mimeType: _kRecordedAudioMimeType,
          bytes: bytes,
        ),
      ],
    );

    if (mounted) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            context.t.chat.recordingRecovery.recoveredToDraftSnack,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    await _discardRecoveredAudioSegments(snapshot, segmentPaths);
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
}
