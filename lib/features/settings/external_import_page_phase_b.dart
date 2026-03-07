part of 'external_import_page.dart';

extension _ExternalImportPagePhaseBExtension on _ExternalImportPageState {
  Future<void> _refreshPhaseBStateForBatch(
    ExternalImportBatchSummary? batch, {
    bool maybeAutoStart = true,
  }) async {
    final batchId = batch?.batchId.trim();
    if (batchId == null || batchId.isEmpty) {
      _mutateState(() {
        _phaseBLoadedBatchId = null;
        _phaseBState = null;
        _loadingPhaseBState = false;
      });
      return;
    }

    _mutateState(() {
      _loadingPhaseBState = true;
      if (_phaseBLoadedBatchId != batchId) {
        _phaseBLoadedBatchId = batchId;
        _phaseBState = null;
      }
    });

    try {
      final raw =
          await _backend.readExternalImportPhaseBState(batchId: batchId);
      final state = ExternalImportPhaseBState.fromJsonString(raw);
      _mutateState(() {
        _phaseBLoadedBatchId = state.batchId;
        _phaseBState = state;
      });
      if (maybeAutoStart) {
        unawaited(_maybeAutoRunPhaseB(state));
      }
    } catch (error) {
      _mutateState(() {
        _errorMessage = error.toString();
      });
    } finally {
      _mutateState(() {
        _loadingPhaseBState = false;
      });
    }
  }

  Future<void> _maybeAutoRunPhaseB(ExternalImportPhaseBState state) async {
    if (!mounted || _importing || _phaseBRunning) return;
    if (state.batchStatus != 'completed') return;
    if (_phaseBAutoStartedBatchId == state.batchId) return;

    if (state.isInProgress) {
      _phaseBAutoStartedBatchId = state.batchId;
      await _startPhaseB(batchId: state.batchId);
      return;
    }

    if (!state.isNotStarted) return;
    final hasConsent = await ExternalImportPhaseBPrefs.readConsentGranted();
    if (!mounted || !hasConsent) return;
    _phaseBAutoStartedBatchId = state.batchId;
    await _startPhaseB(batchId: state.batchId);
  }

  Future<void> _handlePhaseBAction(ExternalImportBatchSummary batch) async {
    if (_isBusy || batch.status != 'completed') return;

    var state = _phaseBStateForBatch(batch);
    if (state == null) {
      await _refreshPhaseBStateForBatch(batch, maybeAutoStart: false);
      state = _phaseBStateForBatch(batch);
    }
    if (!mounted || state == null) return;
    if (!state.canStart && !state.isInProgress) return;

    final hasConsent = await ExternalImportPhaseBPrefs.readConsentGranted();
    if (state.isInProgress || hasConsent) {
      await _startPhaseB(batchId: batch.batchId);
      return;
    }

    try {
      final rawEstimate =
          await _backend.estimateExternalImportPhaseB(batchId: batch.batchId);
      final estimate = ExternalImportPhaseBEstimate.fromJsonString(rawEstimate);
      if (!mounted) return;
      final confirmed = await _showPhaseBEstimateDialog(estimate);
      if (!confirmed) return;
      await ExternalImportPhaseBPrefs.saveConsentGranted();
      if (!mounted) return;
      await _startPhaseB(batchId: batch.batchId);
    } catch (error) {
      _mutateState(() {
        _errorMessage = error.toString();
      });
    }
  }

  Future<bool> _showPhaseBEstimateDialog(
    ExternalImportPhaseBEstimate estimate,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_text(_ExternalImportText.phaseBEstimateTitle)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_text(_ExternalImportText.phaseBEstimateBody)),
                const SizedBox(height: 12),
                Text(
                  context.t.common.labels.labeledValue(
                    label: _text(_ExternalImportText.attachments),
                    value: '${estimate.eligibleAttachmentCount}',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t.common.labels.labeledValue(
                    label: _text(_ExternalImportText.phaseBEstimateRemaining),
                    value: '${estimate.remainingAttachmentCount}',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t.common.labels.labeledValue(
                    label: _text(_ExternalImportText.phaseBEstimateRuntime),
                    value: _formatDuration(
                      estimate.estimatedRuntimeSeconds * 1000,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t.common.labels.labeledValue(
                    label: _text(_ExternalImportText.estimatedDiskUsage),
                    value: _formatBytes(estimate.estimatedLocalBytes),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _text(_ExternalImportText.phaseBSaveConsentHint),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.t.common.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('external_import_phase_b_confirm_estimate'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(_text(_ExternalImportText.phaseBConfirmEstimate)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _startPhaseB({required String batchId}) async {
    if (_importing || _phaseBRunning) return;

    final state = _phaseBStateForBatch(
      _findBatchById(batchId, _batches) ??
          ExternalImportBatchSummary(
            batchId: batchId,
            sourceKind: '',
            sourceLabel: '',
            status: 'completed',
            notesCount: 0,
            attachmentsCount: 0,
            failedCount: 0,
            copiedBytes: 0,
            createdAtMs: 0,
            updatedAtMs: 0,
            completedAtMs: null,
            lastError: null,
          ),
    );

    _mutateState(() {
      _errorMessage = null;
      _phaseBRunning = true;
      _progressBatchId = batchId;
      _progressStage = 'indexing_phase_b';
      _progressStatus = 'in_progress';
      _progressDone = state?.processedAttachmentCount ?? 0;
      _progressTotal = state?.eligibleAttachmentCount ?? 0;
      _progressFailedCount = state?.failedAttachmentCount ?? 0;
    });

    try {
      await for (final raw in _backend.runExternalImportPhaseBProgress(
        SessionScope.of(context).sessionKey,
        batchId: batchId,
      )) {
        _handleProgressEvent(raw);
      }
    } catch (error) {
      _mutateState(() {
        _errorMessage = error.toString();
      });
    } finally {
      await _loadBatches(clearError: false, refreshPhaseB: false);
      await _refreshPhaseBStateForBatch(
        _findBatchById(batchId, _batches) ??
            _pickLatestCompletedBatch(_batches),
        maybeAutoStart: false,
      );
      if (mounted) {
        _mutateState(() {
          _phaseBRunning = false;
        });
      }
    }
  }

  ExternalImportPhaseBState? _phaseBStateForBatch(
    ExternalImportBatchSummary batch,
  ) {
    if (_phaseBLoadedBatchId != batch.batchId) {
      return null;
    }
    return _phaseBState;
  }

  bool _shouldShowPhaseBAction(
    ExternalImportBatchSummary batch,
    ExternalImportPhaseBState? state,
  ) {
    if (batch.status != 'completed' || state == null) {
      return false;
    }
    return state.isInProgress || state.canStart;
  }

  String _phaseBActionLabel(ExternalImportPhaseBState state) {
    return state.isInProgress
        ? _text(_ExternalImportText.phaseBResumeLatest)
        : _text(_ExternalImportText.phaseBStartLatest);
  }

  ExternalImportBatchSummary? _pickLatestFinishedBatch(
    List<ExternalImportBatchSummary> batches,
  ) {
    ExternalImportBatchSummary? current;
    for (final batch in batches) {
      if (!_isTerminalBatchStatus(batch.status)) continue;
      if (current == null ||
          _batchRecencyMs(batch) > _batchRecencyMs(current)) {
        current = batch;
      }
    }
    return current;
  }

  ExternalImportBatchSummary? _pickLatestCompletedBatch(
    List<ExternalImportBatchSummary> batches,
  ) {
    ExternalImportBatchSummary? current;
    for (final batch in batches) {
      if (batch.status != 'completed') continue;
      if (current == null ||
          _batchRecencyMs(batch) > _batchRecencyMs(current)) {
        current = batch;
      }
    }
    return current;
  }

  bool _isTerminalBatchStatus(String status) {
    return status == 'completed' || status == 'cancelled' || status == 'failed';
  }

  int _batchRecencyMs(ExternalImportBatchSummary batch) {
    return (batch.completedAtMs ?? batch.updatedAtMs).toInt();
  }
}
