import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../i18n/strings.g.dart';
import '../../core/session/session_scope.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

enum _ExternalImportText {
  chooseImportFolder,
  chooseZipExport,
  importPreparingTryAgain,
  cancelImportTitle,
  cancelImportBody,
  keepImporting,
  confirmCancel,
  deleteImportBatchTitle,
  deleteImportBatchBody,
  importBatchDeleted,
  title,
  introTitle,
  introBody,
  sourceSectionTitle,
  chooseFolder,
  chooseZip,
  rescan,
  scanSummaryTitle,
  detectedType,
  sourceLabel,
  notes,
  attachments,
  estimatedDiskUsage,
  compatibilityWarnings,
  startImport,
  latestImportCancelledAndCleaned,
  latestImportCompleted,
  latestImport,
  status,
  failedCount,
  copiedData,
  lastError,
  deleteThisBatch,
  error,
  importedBatches,
  noImportBatchesYet,
  batchId,
  createdAt,
  updatedAt,
  completedAt,
  importingTitle,
  requestingCancel,
  cancelImport,
  cannotLeaveHint,
  stagePreparing,
  stageScanning,
  stageParsing,
  stageCopyingAttachments,
  stageIndexingPhaseA,
  stageVerifying,
  stageRollback,
  stageCancelled,
  stageCompleted,
  statusInProgress,
  statusCancelling,
  statusCancelled,
  statusCompleted,
  statusFailed,
  progress,
  processed,
}

class ExternalImportPage extends StatefulWidget {
  const ExternalImportPage({super.key});

  @override
  State<ExternalImportPage> createState() => _ExternalImportPageState();
}

class _ExternalImportPageState extends State<ExternalImportPage> {
  String? _sourcePath;
  ExternalImportScanSummary? _scanSummary;
  List<ExternalImportBatchSummary> _batches =
      const <ExternalImportBatchSummary>[];
  ExternalImportBatchSummary? _lastFinishedBatch;
  bool _loadingBatches = true;
  bool _scanning = false;
  bool _importing = false;
  bool _requestingCancel = false;
  String? _deletingBatchId;
  String? _errorMessage;
  String? _progressBatchId;
  String _progressStage = 'preparing';
  String _progressStatus = 'in_progress';
  int _progressDone = 0;
  int _progressTotal = 0;
  int _progressFailedCount = 0;

  AppBackend get _backend => AppBackendScope.of(context);

  bool _didLoadInitialBatches = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadInitialBatches) return;
    _didLoadInitialBatches = true;
    unawaited(_loadBatches());
  }

  bool get _isBusy => _scanning || _importing || _deletingBatchId != null;

  String _text(_ExternalImportText text) {
    final t = context.t.settings.externalImport;
    return switch (text) {
      _ExternalImportText.chooseImportFolder => t.chooseImportFolder,
      _ExternalImportText.chooseZipExport => t.chooseZipExport,
      _ExternalImportText.importPreparingTryAgain => t.importPreparingTryAgain,
      _ExternalImportText.cancelImportTitle => t.cancelImportTitle,
      _ExternalImportText.cancelImportBody => t.cancelImportBody,
      _ExternalImportText.keepImporting => t.keepImporting,
      _ExternalImportText.confirmCancel => t.confirmCancel,
      _ExternalImportText.deleteImportBatchTitle => t.deleteImportBatchTitle,
      _ExternalImportText.deleteImportBatchBody => t.deleteImportBatchBody,
      _ExternalImportText.importBatchDeleted => t.importBatchDeleted,
      _ExternalImportText.title => t.title,
      _ExternalImportText.introTitle => t.introTitle,
      _ExternalImportText.introBody => t.introBody,
      _ExternalImportText.sourceSectionTitle => t.sourceSectionTitle,
      _ExternalImportText.chooseFolder => t.chooseFolder,
      _ExternalImportText.chooseZip => t.chooseZip,
      _ExternalImportText.rescan => t.rescan,
      _ExternalImportText.scanSummaryTitle => t.scanSummaryTitle,
      _ExternalImportText.detectedType => t.detectedType,
      _ExternalImportText.sourceLabel => t.sourceLabel,
      _ExternalImportText.notes => t.notes,
      _ExternalImportText.attachments => t.attachments,
      _ExternalImportText.estimatedDiskUsage => t.estimatedDiskUsage,
      _ExternalImportText.compatibilityWarnings => t.compatibilityWarnings,
      _ExternalImportText.startImport => t.startImport,
      _ExternalImportText.latestImportCancelledAndCleaned =>
        t.latestImportCancelledAndCleaned,
      _ExternalImportText.latestImportCompleted => t.latestImportCompleted,
      _ExternalImportText.latestImport => t.latestImport,
      _ExternalImportText.status => t.status,
      _ExternalImportText.failedCount => t.failed,
      _ExternalImportText.copiedData => t.copiedData,
      _ExternalImportText.lastError => t.lastError,
      _ExternalImportText.deleteThisBatch => t.deleteThisBatch,
      _ExternalImportText.error => t.error,
      _ExternalImportText.importedBatches => t.importedBatches,
      _ExternalImportText.noImportBatchesYet => t.noImportBatchesYet,
      _ExternalImportText.batchId => t.batchId,
      _ExternalImportText.createdAt => t.createdAt,
      _ExternalImportText.updatedAt => t.updatedAt,
      _ExternalImportText.completedAt => t.completedAt,
      _ExternalImportText.importingTitle => t.importingTitle,
      _ExternalImportText.requestingCancel => t.requestingCancel,
      _ExternalImportText.cancelImport => t.cancelImport,
      _ExternalImportText.cannotLeaveHint => t.cannotLeaveHint,
      _ExternalImportText.stagePreparing => t.stagePreparing,
      _ExternalImportText.stageScanning => t.stageScanning,
      _ExternalImportText.stageParsing => t.stageParsing,
      _ExternalImportText.stageCopyingAttachments => t.stageCopyingAttachments,
      _ExternalImportText.stageIndexingPhaseA => t.stageIndexingPhaseA,
      _ExternalImportText.stageVerifying => t.stageVerifying,
      _ExternalImportText.stageRollback => t.stageRollback,
      _ExternalImportText.stageCancelled => t.stageCancelled,
      _ExternalImportText.stageCompleted => t.stageCompleted,
      _ExternalImportText.statusInProgress => t.statusInProgress,
      _ExternalImportText.statusCancelling => t.statusCancelling,
      _ExternalImportText.statusCancelled => t.statusCancelled,
      _ExternalImportText.statusCompleted => t.statusCompleted,
      _ExternalImportText.statusFailed => t.statusFailed,
      _ExternalImportText.progress => t.progress,
      _ExternalImportText.processed => t.processed,
    };
  }

  Future<void> _loadBatches({bool clearError = true}) async {
    setState(() {
      _loadingBatches = true;
      if (clearError) {
        _errorMessage = null;
      }
    });
    try {
      final batches = await _backend.listExternalImportBatches();
      if (!mounted) return;
      final lastFinishedBatch = _findBatchById(_progressBatchId, batches);
      setState(() {
        _batches = batches;
        _lastFinishedBatch = lastFinishedBatch ?? _lastFinishedBatch;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingBatches = false;
        });
      }
    }
  }

  Future<void> _pickDirectory() async {
    if (_isBusy) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: _text(_ExternalImportText.chooseImportFolder),
    );
    if (path == null || path.trim().isEmpty) return;
    await _scanSource(path.trim());
  }

  Future<void> _pickZip() async {
    if (_isBusy) return;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      lockParentWindow: true,
      dialogTitle: _text(_ExternalImportText.chooseZipExport),
    );
    final path = picked?.files.singleOrNull?.path?.trim();
    if (path == null || path.isEmpty) return;
    await _scanSource(path);
  }

  Future<void> _scanSource(String sourcePath) async {
    setState(() {
      _sourcePath = sourcePath;
      _scanSummary = null;
      _errorMessage = null;
      _scanning = true;
    });

    try {
      final summary = await _backend.scanExternalImportSource(
        sourcePath: sourcePath,
      );
      if (!mounted) return;
      setState(() {
        _scanSummary = summary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  Future<void> _startImport() async {
    final sourcePath = _sourcePath;
    final scanSummary = _scanSummary;
    if (_importing || sourcePath == null || scanSummary == null) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _importing = true;
      _progressBatchId = null;
      _progressStage = 'preparing';
      _progressStatus = 'in_progress';
      _progressDone = 0;
      _progressTotal = 0;
      _progressFailedCount = 0;
      _lastFinishedBatch = null;
    });

    try {
      await for (final raw in _backend.runExternalImportProgress(
        SessionScope.of(context).sessionKey,
        sourcePath: sourcePath,
      )) {
        _handleProgressEvent(raw);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      await _loadBatches(clearError: false);
      if (mounted) {
        setState(() {
          _importing = false;
          _requestingCancel = false;
          _lastFinishedBatch = _findBatchById(_progressBatchId, _batches);
        });
      }
    }
  }

  void _handleProgressEvent(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final type = decoded['type']?.toString();
    if (type == 'progress') {
      if (!mounted) return;
      setState(() {
        _progressBatchId = decoded['batch_id']?.toString() ?? _progressBatchId;
        _progressStage = decoded['stage']?.toString() ?? _progressStage;
        _progressStatus = decoded['status']?.toString() ?? _progressStatus;
        _progressDone = _toInt(decoded['done']);
        _progressTotal = _toInt(decoded['total']);
        _progressFailedCount = _toInt(decoded['failed_count']);
      });
      return;
    }

    if (type == 'result') {
      if (!mounted) return;
      setState(() {
        _progressBatchId = decoded['batch_id']?.toString() ?? _progressBatchId;
        _progressStatus = decoded['status']?.toString() ?? _progressStatus;
      });
    }
  }

  Future<void> _confirmCancelImport() async {
    if (_progressBatchId == null || _requestingCancel) {
      _showSnack(
        _text(_ExternalImportText.importPreparingTryAgain),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_text(_ExternalImportText.cancelImportTitle)),
            content: Text(
              _text(_ExternalImportText.cancelImportBody),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text(_ExternalImportText.keepImporting)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_text(_ExternalImportText.confirmCancel)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() {
      _requestingCancel = true;
      _errorMessage = null;
    });

    try {
      await _backend.requestExternalImportCancel(batchId: _progressBatchId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requestingCancel = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _confirmDeleteBatch(ExternalImportBatchSummary batch) async {
    if (_isBusy) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_text(_ExternalImportText.deleteImportBatchTitle)),
            content: Text(
              _text(_ExternalImportText.deleteImportBatchBody),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.t.common.actions.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() {
      _deletingBatchId = batch.batchId;
      _errorMessage = null;
    });
    try {
      await _backend.deleteExternalImportBatch(batchId: batch.batchId);
      if (!mounted) return;
      setState(() {
        if (_lastFinishedBatch?.batchId == batch.batchId) {
          _lastFinishedBatch = null;
        }
      });
      await _loadBatches();
      if (!mounted) return;
      _showSnack(_text(_ExternalImportText.importBatchDeleted));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _deletingBatchId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_importing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_text(_ExternalImportText.title)),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildIntroCard(),
                const SizedBox(height: 16),
                _buildSourcePickerCard(),
                if (_scanSummary != null) ...[
                  const SizedBox(height: 16),
                  _buildScanSummaryCard(_scanSummary!),
                ],
                if (_lastFinishedBatch != null) ...[
                  const SizedBox(height: 16),
                  _buildLastResultCard(_lastFinishedBatch!),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(_errorMessage!),
                ],
                const SizedBox(height: 16),
                _buildBatchesSection(),
              ],
            ),
            if (_importing) _buildBlockingOverlay(),
          ],
        ),
      ),
    );
  }

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
            Text(
              _text(_ExternalImportText.introBody),
            ),
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
            _infoRow(_text(_ExternalImportText.detectedType),
                summary.detectedSourceKind),
            _infoRow(
                _text(_ExternalImportText.sourceLabel), summary.sourceLabel),
            _infoRow(_text(_ExternalImportText.notes),
                '${summary.notesCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.attachments),
                '${summary.attachmentsCount.toInt()}'),
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
              onPressed: _importing ? null : _startImport,
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
            _infoRow(_text(_ExternalImportText.sourceLabel), batch.sourceLabel),
            _infoRow(
                _text(_ExternalImportText.status), _statusLabel(batch.status)),
            _infoRow(_text(_ExternalImportText.notes),
                '${batch.notesCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.attachments),
                '${batch.attachmentsCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.failedCount),
                '${batch.failedCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.copiedData),
                _formatBytes(batch.copiedBytes.toInt())),
            if (batch.lastError != null && batch.lastError!.trim().isNotEmpty)
              _infoRow(_text(_ExternalImportText.lastError),
                  batch.lastError!.trim()),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('external_import_delete_latest_batch'),
              onPressed: _isBusy ? null : () => _confirmDeleteBatch(batch),
              icon: const Icon(Icons.delete_outline),
              label: Text(_text(_ExternalImportText.deleteThisBatch)),
            ),
          ],
        ),
      ),
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
              child: Text(
                _text(_ExternalImportText.noImportBatchesYet),
              ),
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
            _infoRow(_text(_ExternalImportText.notes),
                '${batch.notesCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.attachments),
                '${batch.attachmentsCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.failedCount),
                '${batch.failedCount.toInt()}'),
            _infoRow(_text(_ExternalImportText.copiedData),
                _formatBytes(batch.copiedBytes.toInt())),
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
              _infoRow(_text(_ExternalImportText.lastError),
                  batch.lastError!.trim()),
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
                            _text(_ExternalImportText.importingTitle),
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
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey('external_import_cancel'),
                            onPressed:
                                _requestingCancel ? null : _confirmCancelImport,
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
                            label: Text(_requestingCancel
                                ? _text(_ExternalImportText.requestingCancel)
                                : _text(_ExternalImportText.cancelImport)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _text(_ExternalImportText.cannotLeaveHint),
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
      'completed' => _text(_ExternalImportText.stageCompleted),
      'failed' => _text(_ExternalImportText.statusFailed),
      _ => status,
    };
  }

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

  ExternalImportBatchSummary? _findBatchById(
    String? batchId,
    List<ExternalImportBatchSummary> batches,
  ) {
    if (batchId == null || batchId.trim().isEmpty) {
      return null;
    }
    for (final batch in batches) {
      if (batch.batchId == batchId) {
        return batch;
      }
    }
    return null;
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
