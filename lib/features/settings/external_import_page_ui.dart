part of 'external_import_page.dart';

extension _ExternalImportPageUiExtension on _ExternalImportPageState {
  Widget _buildIntroCard() {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text(_ExternalImportText.introTitle),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(_text(_ExternalImportText.introBody)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcePickerCard() {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text(_ExternalImportText.sourceSectionTitle),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('external_import_choose_folder'),
                  onPressed: _isBusy ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: Text(_text(_ExternalImportText.chooseFolder)),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('external_import_choose_zip'),
                  onPressed: _isBusy ? null : _pickZip,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(_text(_ExternalImportText.chooseZip)),
                ),
                if (_sourcePath != null)
                  OutlinedButton.icon(
                    key: const ValueKey('external_import_rescan'),
                    onPressed:
                        _isBusy ? null : () => _scanSource(_sourcePath!.trim()),
                    icon: const Icon(Icons.refresh),
                    label: Text(_text(_ExternalImportText.rescan)),
                  ),
              ],
            ),
            if (_sourcePath != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                _sourcePath!,
                key: const ValueKey('external_import_source_path'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            if (_scanning) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                key: ValueKey('external_import_scan_progress'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanSummaryCard(ExternalImportScanSummary summary) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text(_ExternalImportText.scanSummaryTitle),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _infoRow(
              _text(_ExternalImportText.detectedType),
              summary.detectedSourceKind,
            ),
            _infoRow(
              _text(_ExternalImportText.sourceLabel),
              summary.sourceLabel,
            ),
            _infoRow(
              _text(_ExternalImportText.notes),
              '${summary.notesCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.attachments),
              '${summary.attachmentsCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.estimatedDiskUsage),
              _formatBytes(summary.estimatedDiskUsageBytes.toInt()),
            ),
            if (summary.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _text(_ExternalImportText.compatibilityWarnings),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final warning in summary.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(_warningBullet(warning)),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('external_import_start'),
              onPressed: _importing || _phaseBRunning ? null : _startImport,
              icon: const Icon(Icons.play_arrow),
              label: Text(_text(_ExternalImportText.startImport)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastResultCard(ExternalImportBatchSummary batch) {
    final isCancelled = batch.status == 'cancelled';
    final title = isCancelled
        ? _text(_ExternalImportText.latestImportCancelledAndCleaned)
        : batch.status == 'completed'
            ? _text(_ExternalImportText.latestImportCompleted)
            : _text(_ExternalImportText.latestImport);
    final phaseBState = _phaseBStateForBatch(batch);

    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_shouldShowPhaseBAction(batch, phaseBState))
                  FilledButton.icon(
                    key: const ValueKey('external_import_phase_b_start_latest'),
                    onPressed:
                        _isBusy ? null : () => _handlePhaseBAction(batch),
                    icon: Icon(
                      phaseBState?.isInProgress == true
                          ? Icons.refresh
                          : Icons.auto_awesome,
                    ),
                    label: Text(_phaseBActionLabel(phaseBState!)),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('external_import_delete_latest_batch'),
                  onPressed: _isBusy ? null : () => _confirmDeleteBatch(batch),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_text(_ExternalImportText.deleteThisBatch)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(_text(_ExternalImportText.sourceLabel), batch.sourceLabel),
            _infoRow(
              _text(_ExternalImportText.status),
              _statusLabel(batch.status),
            ),
            _infoRow(
              _text(_ExternalImportText.notes),
              '${batch.notesCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.attachments),
              '${batch.attachmentsCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.failedCount),
              '${batch.failedCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.copiedData),
              _formatBytes(batch.copiedBytes.toInt()),
            ),
            if (batch.lastError != null && batch.lastError!.trim().isNotEmpty)
              _infoRow(
                _text(_ExternalImportText.lastError),
                batch.lastError!.trim(),
              ),
            if (batch.status == 'completed') ...[
              const SizedBox(height: 8),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 8),
              _buildPhaseBSection(batch, phaseBState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseBSection(
    ExternalImportBatchSummary batch,
    ExternalImportPhaseBState? state,
  ) {
    final showLoading =
        _loadingPhaseBState && _phaseBLoadedBatchId == batch.batchId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(_ExternalImportText.phaseBTitle),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _text(_ExternalImportText.phaseBDescription),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (showLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (state != null) ...[
          const SizedBox(height: 12),
          _infoRow(
            _text(_ExternalImportText.phaseBStatus),
            _phaseBStatusLabel(state.phaseBStatus),
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBEligibleAttachments),
            '${state.eligibleAttachmentCount}',
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBProcessedAttachments),
            '${state.processedAttachmentCount}',
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBRemainingAttachments),
            '${state.remainingAttachmentCount}',
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBEnrichedChunks),
            '${state.enrichedChunkCount}',
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBSuccessDocs),
            '${state.successDocCount}',
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBAttachmentRefs),
            '${state.attachmentRefCount}',
          ),
          _infoRow(
            _text(_ExternalImportText.elapsed),
            _formatDuration(state.elapsedMs),
          ),
          _infoRow(
            _text(_ExternalImportText.phaseBElapsed),
            _formatDuration(state.phaseBElapsedMs),
          ),
          if (state.phaseBLastError != null)
            _infoRow(
              _text(_ExternalImportText.phaseBLastError),
              state.phaseBLastError!,
            ),
        ],
      ],
    );
  }

  Widget _buildErrorCard(String message) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text(_ExternalImportText.error),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            SelectableText(message),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(_ExternalImportText.importedBatches),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_loadingBatches)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_batches.isEmpty)
          _surface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_text(_ExternalImportText.noImportBatchesYet)),
            ),
          )
        else
          Column(
            children: [
              for (final batch in _batches) ...[
                _buildBatchCard(batch),
                const SizedBox(height: 12),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildBatchCard(ExternalImportBatchSummary batch) {
    final deleting = _deletingBatchId == batch.batchId;
    return _surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.sourceLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _batchStatusSummary(batch),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: deleting || _isBusy
                      ? null
                      : () => _confirmDeleteBatch(batch),
                  icon: deleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(context.t.common.actions.delete),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(_text(_ExternalImportText.batchId), batch.batchId),
            _infoRow(
              _text(_ExternalImportText.notes),
              '${batch.notesCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.attachments),
              '${batch.attachmentsCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.failedCount),
              '${batch.failedCount.toInt()}',
            ),
            _infoRow(
              _text(_ExternalImportText.copiedData),
              _formatBytes(batch.copiedBytes.toInt()),
            ),
            _infoRow(
              _text(_ExternalImportText.createdAt),
              _formatTimestamp(batch.createdAtMs.toInt()),
            ),
            _infoRow(
              _text(_ExternalImportText.updatedAt),
              _formatTimestamp(batch.updatedAtMs.toInt()),
            ),
            if (batch.completedAtMs != null)
              _infoRow(
                _text(_ExternalImportText.completedAt),
                _formatTimestamp(batch.completedAtMs!.toInt()),
              ),
            if (batch.lastError != null && batch.lastError!.trim().isNotEmpty)
              _infoRow(
                _text(_ExternalImportText.lastError),
                batch.lastError!.trim(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockingOverlay() {
    final progressValue = _progressTotal > 0
        ? (_progressDone / _progressTotal).clamp(0.0, 1.0)
        : null;
    final percentLabel = progressValue == null
        ? '—'
        : '${(progressValue * 100).floor().clamp(0, 100)}%';
    final overlayTitle = _phaseBRunning
        ? _text(_ExternalImportText.phaseBRunningTitle)
        : _text(_ExternalImportText.importingTitle);
    final hint = _phaseBRunning
        ? _text(_ExternalImportText.phaseBCannotLeaveHint)
        : _text(_ExternalImportText.cannotLeaveHint);

    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _surface(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            overlayTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Text(_stageLabel(_progressStage)),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            key: const ValueKey('external_import_progress_bar'),
                            value: progressValue,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              Text(_progressPercentSummary(percentLabel)),
                              Text(_progressProcessedSummary()),
                              Text(_progressFailedSummary()),
                              Text(
                                context.t.common.labels.labeledValue(
                                  label: _text(_ExternalImportText.status),
                                  value: _statusLabel(_progressStatus),
                                ),
                              ),
                            ],
                          ),
                          if (_progressBatchId != null) ...[
                            const SizedBox(height: 8),
                            SelectableText(
                              _progressBatchIdSummary(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (_importing) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              key: const ValueKey('external_import_cancel'),
                              onPressed: _requestingCancel
                                  ? null
                                  : _confirmCancelImport,
                              icon: _requestingCancel
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.stop_circle_outlined),
                              label: Text(
                                _requestingCancel
                                    ? _text(
                                        _ExternalImportText.requestingCancel)
                                    : _text(_ExternalImportText.cancelImport),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            hint,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _surface({required Widget child}) {
    return SlSurface(
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _stageLabel(String stage) {
    return switch (stage) {
      'preparing' => _text(_ExternalImportText.stagePreparing),
      'scanning' => _text(_ExternalImportText.stageScanning),
      'parsing' => _text(_ExternalImportText.stageParsing),
      'copying_attachments' =>
        _text(_ExternalImportText.stageCopyingAttachments),
      'indexing_phase_a' => _text(_ExternalImportText.stageIndexingPhaseA),
      'indexing_phase_b' => _text(_ExternalImportText.stageIndexingPhaseB),
      'verifying' => _text(_ExternalImportText.stageVerifying),
      'rollback' => _text(_ExternalImportText.stageRollback),
      'cancelled' => _text(_ExternalImportText.stageCancelled),
      'completed' => _text(_ExternalImportText.stageCompleted),
      _ => stage,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'in_progress' => _text(_ExternalImportText.statusInProgress),
      'cancelling' => _text(_ExternalImportText.statusCancelling),
      'cancelled' => _text(_ExternalImportText.statusCancelled),
      'completed' => _text(_ExternalImportText.statusCompleted),
      'failed' => _text(_ExternalImportText.statusFailed),
      'not_started' => _text(_ExternalImportText.statusNotStarted),
      'no_work' => _text(_ExternalImportText.statusNoWork),
      _ => status,
    };
  }

  String _phaseBStatusLabel(String status) => _statusLabel(status);

  String _warningBullet(String warning) => '• $warning';

  String _batchStatusSummary(ExternalImportBatchSummary batch) =>
      '${_statusLabel(batch.status)} · ${batch.sourceKind}';

  String _progressPercentSummary(String percentLabel) =>
      '${_text(_ExternalImportText.progress)}: $percentLabel';

  String _progressProcessedSummary() =>
      '${_text(_ExternalImportText.processed)}: $_progressDone / $_progressTotal';

  String _progressFailedSummary() =>
      '${_text(_ExternalImportText.statusFailed)}: $_progressFailedCount';

  String _progressBatchIdSummary() =>
      '${_text(_ExternalImportText.batchId)}: $_progressBatchId';

  String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble().clamp(0, double.infinity);
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final digits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  String _formatTimestamp(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }

  String _formatDuration(int milliseconds) {
    final safeMs = milliseconds < 0 ? 0 : milliseconds;
    final totalSeconds = safeMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
