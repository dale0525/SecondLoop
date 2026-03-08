import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'external_import_phase_b_models.dart';
import 'external_import_phase_b_prefs.dart';
import 'external_import_report_models.dart';

part 'external_import_page_phase_b.dart';
part 'external_import_page_ui.dart';

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
  successCount,
  copiedAttachments,
  diskUsage,
  lastError,
  viewReport,
  deleteThisBatch,
  error,
  importedBatches,
  noImportBatchesYet,
  batchId,
  createdAt,
  updatedAt,
  completedAt,
  importingTitle,
  phaseBRunningTitle,
  requestingCancel,
  cancelImport,
  cannotLeaveHint,
  phaseBCannotLeaveHint,
  stagePreparing,
  stageScanning,
  stageParsing,
  stageCopyingAttachments,
  stageIndexingPhaseA,
  stageIndexingPhaseB,
  stageVerifying,
  stageRollback,
  stageCancelled,
  stageCompleted,
  statusInProgress,
  statusCancelling,
  statusCancelled,
  statusCompleted,
  statusFailed,
  statusNotStarted,
  statusNoWork,
  progress,
  processed,
  elapsed,
  eta,
  estimatingEta,
  phaseBTitle,
  phaseBDescription,
  phaseBStartLatest,
  phaseBResumeLatest,
  phaseBEstimateTitle,
  phaseBEstimateBody,
  phaseBEstimateRuntime,
  phaseBEstimateRemaining,
  phaseBSaveConsentHint,
  phaseBConfirmEstimate,
  phaseBStatus,
  phaseBEligibleAttachments,
  phaseBProcessedAttachments,
  phaseBRemainingAttachments,
  phaseBEnrichedChunks,
  phaseBSuccessDocs,
  phaseBAttachmentRefs,
  phaseBElapsed,
  phaseBLastError,
  reportTitle,
  reportDiagnostics,
  reportNoDiagnostics,
  reportCode,
  reportStage,
  reportSeverity,
  reportSourcePath,
  reportCopied,
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
  ExternalImportBatchReport? _latestBatchReport;
  ExternalImportPhaseBState? _phaseBState;
  bool _loadingBatches = true;
  bool _loadingBatchReport = false;
  bool _scanning = false;
  bool _importing = false;
  bool _phaseBRunning = false;
  bool _loadingPhaseBState = false;
  bool _requestingCancel = false;
  String? _deletingBatchId;
  String? _errorMessage;
  String? _progressBatchId;
  String _progressStage = 'preparing';
  String _progressStatus = 'in_progress';
  int _progressDone = 0;
  int _progressTotal = 0;
  int _progressFailedCount = 0;
  int? _progressSampleAtMs;
  int? _previousProgressDone;
  int? _etaMs;
  String? _batchReportLoadedBatchId;
  String? _phaseBLoadedBatchId;
  String? _phaseBAutoStartedBatchId;
  bool _didLoadInitialBatches = false;

  AppBackend get _backend => AppBackendScope.of(context);

  bool get _isBusy =>
      _scanning || _importing || _phaseBRunning || _deletingBatchId != null;

  bool get _isBlockingOperation => _importing || _phaseBRunning;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadInitialBatches) return;
    _didLoadInitialBatches = true;
    unawaited(_loadBatches());
  }

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
      _ExternalImportText.successCount => t.successCount,
      _ExternalImportText.copiedAttachments => t.copiedAttachments,
      _ExternalImportText.diskUsage => t.diskUsage,
      _ExternalImportText.lastError => t.lastError,
      _ExternalImportText.viewReport => t.viewReport,
      _ExternalImportText.deleteThisBatch => t.deleteThisBatch,
      _ExternalImportText.error => t.error,
      _ExternalImportText.importedBatches => t.importedBatches,
      _ExternalImportText.noImportBatchesYet => t.noImportBatchesYet,
      _ExternalImportText.batchId => t.batchId,
      _ExternalImportText.createdAt => t.createdAt,
      _ExternalImportText.updatedAt => t.updatedAt,
      _ExternalImportText.completedAt => t.completedAt,
      _ExternalImportText.importingTitle => t.importingTitle,
      _ExternalImportText.phaseBRunningTitle => t.phaseBRunningTitle,
      _ExternalImportText.requestingCancel => t.requestingCancel,
      _ExternalImportText.cancelImport => t.cancelImport,
      _ExternalImportText.cannotLeaveHint => t.cannotLeaveHint,
      _ExternalImportText.phaseBCannotLeaveHint => t.phaseBCannotLeaveHint,
      _ExternalImportText.stagePreparing => t.stagePreparing,
      _ExternalImportText.stageScanning => t.stageScanning,
      _ExternalImportText.stageParsing => t.stageParsing,
      _ExternalImportText.stageCopyingAttachments => t.stageCopyingAttachments,
      _ExternalImportText.stageIndexingPhaseA => t.stageIndexingPhaseA,
      _ExternalImportText.stageIndexingPhaseB => t.stageIndexingPhaseB,
      _ExternalImportText.stageVerifying => t.stageVerifying,
      _ExternalImportText.stageRollback => t.stageRollback,
      _ExternalImportText.stageCancelled => t.stageCancelled,
      _ExternalImportText.stageCompleted => t.stageCompleted,
      _ExternalImportText.statusInProgress => t.statusInProgress,
      _ExternalImportText.statusCancelling => t.statusCancelling,
      _ExternalImportText.statusCancelled => t.statusCancelled,
      _ExternalImportText.statusCompleted => t.statusCompleted,
      _ExternalImportText.statusFailed => t.statusFailed,
      _ExternalImportText.statusNotStarted => t.statusNotStarted,
      _ExternalImportText.statusNoWork => t.statusNoWork,
      _ExternalImportText.progress => t.progress,
      _ExternalImportText.processed => t.processed,
      _ExternalImportText.elapsed => t.elapsed,
      _ExternalImportText.eta => t.eta,
      _ExternalImportText.estimatingEta => t.estimatingEta,
      _ExternalImportText.phaseBTitle => t.phaseBTitle,
      _ExternalImportText.phaseBDescription => t.phaseBDescription,
      _ExternalImportText.phaseBStartLatest => t.phaseBStartLatest,
      _ExternalImportText.phaseBResumeLatest => t.phaseBResumeLatest,
      _ExternalImportText.phaseBEstimateTitle => t.phaseBEstimateTitle,
      _ExternalImportText.phaseBEstimateBody => t.phaseBEstimateBody,
      _ExternalImportText.phaseBEstimateRuntime => t.phaseBEstimateRuntime,
      _ExternalImportText.phaseBEstimateRemaining => t.phaseBEstimateRemaining,
      _ExternalImportText.phaseBSaveConsentHint => t.phaseBSaveConsentHint,
      _ExternalImportText.phaseBConfirmEstimate => t.phaseBConfirmEstimate,
      _ExternalImportText.phaseBStatus => t.phaseBStatus,
      _ExternalImportText.phaseBEligibleAttachments =>
        t.phaseBEligibleAttachments,
      _ExternalImportText.phaseBProcessedAttachments =>
        t.phaseBProcessedAttachments,
      _ExternalImportText.phaseBRemainingAttachments =>
        t.phaseBRemainingAttachments,
      _ExternalImportText.phaseBEnrichedChunks => t.phaseBEnrichedChunks,
      _ExternalImportText.phaseBSuccessDocs => t.phaseBSuccessDocs,
      _ExternalImportText.phaseBAttachmentRefs => t.phaseBAttachmentRefs,
      _ExternalImportText.phaseBElapsed => t.phaseBElapsed,
      _ExternalImportText.phaseBLastError => t.phaseBLastError,
      _ExternalImportText.reportTitle => t.reportTitle,
      _ExternalImportText.reportDiagnostics => t.reportDiagnostics,
      _ExternalImportText.reportNoDiagnostics => t.reportNoDiagnostics,
      _ExternalImportText.reportCode => t.reportCode,
      _ExternalImportText.reportStage => t.reportStage,
      _ExternalImportText.reportSeverity => t.reportSeverity,
      _ExternalImportText.reportSourcePath => t.reportSourcePath,
      _ExternalImportText.reportCopied => t.reportCopied,
    };
  }

  Future<void> _loadBatches({
    bool clearError = true,
    bool refreshPhaseB = true,
  }) async {
    setState(() {
      _loadingBatches = true;
      if (clearError) {
        _errorMessage = null;
      }
    });
    try {
      final batches = await _backend.listExternalImportBatches();
      if (!mounted) return;
      final lastFinishedBatch = _findBatchById(_progressBatchId, batches) ??
          _pickLatestFinishedBatch(batches);
      final latestCompletedBatch = _pickLatestCompletedBatch(batches);
      setState(() {
        _batches = batches;
        _lastFinishedBatch = lastFinishedBatch;
        if (lastFinishedBatch == null) {
          _batchReportLoadedBatchId = null;
          _latestBatchReport = null;
          _loadingBatchReport = false;
        }
      });
      unawaited(_refreshBatchReportForBatch(lastFinishedBatch));
      if (refreshPhaseB) {
        unawaited(_refreshPhaseBStateForBatch(latestCompletedBatch));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
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
    if (_importing ||
        _phaseBRunning ||
        sourcePath == null ||
        scanSummary == null) {
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
      _progressSampleAtMs = null;
      _previousProgressDone = null;
      _etaMs = null;
      _lastFinishedBatch = null;
      _latestBatchReport = null;
      _batchReportLoadedBatchId = null;
      _loadingBatchReport = false;
      _phaseBState = null;
      _phaseBLoadedBatchId = null;
      _phaseBAutoStartedBatchId = null;
    });

    try {
      await for (final raw in _backend.runExternalImportProgress(
        SessionScope.of(context).sessionKey,
        sourcePath: sourcePath,
      )) {
        _handleProgressEvent(raw);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      await _loadBatches(clearError: false);
      if (mounted) {
        setState(() {
          _importing = false;
          _requestingCancel = false;
        });
      }
    }
  }

  void _handleProgressEvent(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return;
    }
    final payload = Map<String, Object?>.from(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );

    final type = payload['type']?.toString();
    if (type == 'progress') {
      if (!mounted) return;
      final done = _toInt(payload['done']);
      final total = _toInt(payload['total']);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final etaMs = _estimateEtaMs(nowMs: nowMs, done: done, total: total);
      setState(() {
        _progressBatchId = payload['batch_id']?.toString() ?? _progressBatchId;
        _progressStage = payload['stage']?.toString() ?? _progressStage;
        _progressStatus = payload['status']?.toString() ?? _progressStatus;
        _progressDone = done;
        _progressTotal = total;
        _progressFailedCount = _toInt(payload['failed_count']);
        _etaMs = etaMs;
        if (total > 0 && done >= 0 && done < total) {
          _progressSampleAtMs = nowMs;
          _previousProgressDone = done;
        } else {
          _progressSampleAtMs = null;
          _previousProgressDone = null;
        }
      });
      return;
    }

    if (type == 'result') {
      if (!mounted) return;
      setState(() {
        _progressBatchId = payload['batch_id']?.toString() ?? _progressBatchId;
        _progressStatus = payload['status']?.toString() ?? _progressStatus;
        _etaMs = null;
        _progressSampleAtMs = null;
        _previousProgressDone = null;
      });
      return;
    }

    if (type == 'phase_b_result') {
      final state = ExternalImportPhaseBState.tryFromObject(payload['state']);
      if (!mounted) return;
      setState(() {
        _progressBatchId = payload['batch_id']?.toString() ?? _progressBatchId;
        _progressStage = 'completed';
        _progressStatus = state?.phaseBStatus ?? 'completed';
        _etaMs = null;
        _progressSampleAtMs = null;
        _previousProgressDone = null;
        if (state != null) {
          _phaseBLoadedBatchId = state.batchId;
          _phaseBState = state;
          _progressDone = state.processedAttachmentCount;
          _progressTotal = state.eligibleAttachmentCount;
          _progressFailedCount = state.failedAttachmentCount;
        }
      });
    }
  }

  Future<ExternalImportBatchReport?> _refreshBatchReportForBatch(
    ExternalImportBatchSummary? batch,
  ) async {
    final batchId = batch?.batchId.trim();
    if (batchId == null || batchId.isEmpty) {
      _mutateState(() {
        _batchReportLoadedBatchId = null;
        _latestBatchReport = null;
        _loadingBatchReport = false;
      });
      return null;
    }

    _mutateState(() {
      _loadingBatchReport = true;
      if (_batchReportLoadedBatchId != batchId) {
        _batchReportLoadedBatchId = batchId;
        _latestBatchReport = null;
      }
    });

    try {
      final raw =
          await _backend.readExternalImportBatchReport(batchId: batchId);
      final report = ExternalImportBatchReport.fromJsonString(raw);
      _mutateState(() {
        _batchReportLoadedBatchId = report.batchId;
        _latestBatchReport = report;
      });
      return report;
    } catch (error) {
      _mutateState(() {
        _errorMessage = error.toString();
      });
      return null;
    } finally {
      _mutateState(() {
        _loadingBatchReport = false;
      });
    }
  }

  Future<void> _showBatchReportDialog(ExternalImportBatchSummary batch) async {
    var report = _latestBatchReportForBatch(batch);
    report ??= await _refreshBatchReportForBatch(batch);
    if (!mounted || report == null) return;
    final resolvedReport = report;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('external_import_report_dialog'),
        title: Text(_text(_ExternalImportText.reportTitle)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: _buildBatchReportDialogContent(resolvedReport),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyBatchReportToClipboard(resolvedReport),
            child: Text(context.t.common.actions.copy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.t.common.actions.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _copyBatchReportToClipboard(
    ExternalImportBatchReport report,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: report.toPrettyJson()));
      if (!mounted) return;
      _showSnack(_text(_ExternalImportText.reportCopied));
    } catch (error) {
      if (!mounted) return;
      _showSnack(
        context.t.settings.externalImport.reportCopyFailed(
          error: error.toString(),
        ),
      );
    }
  }

  int? _estimateEtaMs({
    required int nowMs,
    required int done,
    required int total,
  }) {
    if (total <= 0 || done <= 0 || done >= total) return null;
    final previousAtMs = _progressSampleAtMs;
    final previousDone = _previousProgressDone;
    if (previousAtMs == null || previousDone == null) return null;
    if (done <= previousDone || nowMs <= previousAtMs) return null;

    final deltaDone = done - previousDone;
    final deltaMs = nowMs - previousAtMs;
    final remaining = total - done;
    if (deltaDone <= 0 || deltaMs <= 0 || remaining <= 0) return null;

    final etaMs = ((deltaMs / deltaDone) * remaining).round();
    return etaMs < 0 ? null : etaMs;
  }

  Future<void> _confirmCancelImport() async {
    if (_progressBatchId == null || _requestingCancel) {
      _showSnack(_text(_ExternalImportText.importPreparingTryAgain));
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_text(_ExternalImportText.cancelImportTitle)),
            content: Text(_text(_ExternalImportText.cancelImportBody)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_text(_ExternalImportText.keepImporting)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _requestingCancel = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _confirmDeleteBatch(ExternalImportBatchSummary batch) async {
    if (_isBusy) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(_text(_ExternalImportText.deleteImportBatchTitle)),
            content: Text(_text(_ExternalImportText.deleteImportBatchBody)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.t.common.actions.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
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
      if (_phaseBLoadedBatchId == batch.batchId) {
        _phaseBLoadedBatchId = null;
        _phaseBState = null;
        _phaseBAutoStartedBatchId = null;
      }
      await _loadBatches();
      if (!mounted) return;
      _showSnack(_text(_ExternalImportText.importBatchDeleted));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
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
      canPop: !_isBlockingOperation,
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
            if (_isBlockingOperation) _buildBlockingOverlay(),
          ],
        ),
      ),
    );
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

  void _mutateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
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
