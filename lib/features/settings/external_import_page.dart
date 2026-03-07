import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

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

  bool get _isZh => Localizations.localeOf(context)
      .languageCode
      .toLowerCase()
      .startsWith('zh');

  String _text(String zh, String en) => _isZh ? zh : en;

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
      dialogTitle: _text('选择导入文件夹', 'Choose import folder'),
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
      dialogTitle: _text('选择 zip 导出包', 'Choose zip export'),
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
        _text('导入尚在准备中，请稍候再取消',
            'Import is still preparing. Try again in a moment.'),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_text('取消导入？', 'Cancel import?')),
            content: Text(
              _text(
                '当前导入会进入回滚并清理已写入的数据，完成后才会返回正常状态。',
                'The current import will roll back and clean any written data before returning to normal.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('继续导入', 'Keep importing')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_text('确认取消', 'Confirm cancel')),
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
            title: Text(_text('删除导入批次？', 'Delete import batch?')),
            content: Text(
              _text(
                '这会永久删除该批次的文档、索引和仅由该批次引用的附件。',
                'This permanently deletes the batch documents, indexes, and attachments referenced only by this batch.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_text('删除', 'Delete')),
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
      _showSnack(_text('已删除导入批次', 'Import batch deleted'));
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
          title: Text(_text('导入外部知识', 'Import External Knowledge')),
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
              _text('只读导入你的 Obsidian、思源或 Markdown 导出',
                  'Readonly import for Obsidian, SiYuan, or Markdown exports'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _text(
                '导入后的内容仅参与检索，不会回写源应用。导入过程中会复制附件、构建 Phase A 索引，并支持取消后回滚清理。',
                'Imported content participates in retrieval only. It does not write back to the source app. The import copies attachments, builds Phase A indexes, and supports cancel with rollback cleanup.',
              ),
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
              _text('1. 选择导入源', '1. Choose import source'),
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
                  label: Text(_text('选择文件夹', 'Choose folder')),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('external_import_choose_zip'),
                  onPressed: _isBusy ? null : _pickZip,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(_text('选择 zip', 'Choose zip')),
                ),
                if (_sourcePath != null)
                  OutlinedButton.icon(
                    key: const ValueKey('external_import_rescan'),
                    onPressed:
                        _isBusy ? null : () => _scanSource(_sourcePath!.trim()),
                    icon: const Icon(Icons.refresh),
                    label: Text(_text('重新扫描', 'Rescan')),
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
              _text('2. 预扫描摘要', '2. Scan summary'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _infoRow(
                _text('识别类型', 'Detected type'), summary.detectedSourceKind),
            _infoRow(_text('来源标签', 'Source label'), summary.sourceLabel),
            _infoRow(_text('笔记数', 'Notes'), '${summary.notesCount.toInt()}'),
            _infoRow(_text('附件数', 'Attachments'),
                '${summary.attachmentsCount.toInt()}'),
            _infoRow(
              _text('预计占用', 'Estimated disk usage'),
              _formatBytes(summary.estimatedDiskUsageBytes.toInt()),
            ),
            if (summary.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _text('兼容性提示', 'Compatibility warnings'),
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
              label: Text(_text('开始导入', 'Start import')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastResultCard(ExternalImportBatchSummary batch) {
    final isCancelled = batch.status == 'cancelled';
    final title = isCancelled
        ? _text('最近一次导入：已取消并清理', 'Latest import: cancelled and cleaned')
        : batch.status == 'completed'
            ? _text('最近一次导入：已完成', 'Latest import: completed')
            : _text('最近一次导入', 'Latest import');

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
            _infoRow(_text('来源标签', 'Source label'), batch.sourceLabel),
            _infoRow(_text('状态', 'Status'), _statusLabel(batch.status)),
            _infoRow(_text('笔记数', 'Notes'), '${batch.notesCount.toInt()}'),
            _infoRow(_text('附件数', 'Attachments'),
                '${batch.attachmentsCount.toInt()}'),
            _infoRow(_text('失败数', 'Failed'), '${batch.failedCount.toInt()}'),
            _infoRow(_text('复制数据', 'Copied data'),
                _formatBytes(batch.copiedBytes.toInt())),
            if (batch.lastError != null && batch.lastError!.trim().isNotEmpty)
              _infoRow(_text('最后错误', 'Last error'), batch.lastError!.trim()),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('external_import_delete_latest_batch'),
              onPressed: _isBusy ? null : () => _confirmDeleteBatch(batch),
              icon: const Icon(Icons.delete_outline),
              label: Text(_text('删除这个批次', 'Delete this batch')),
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
              _text('错误', 'Error'),
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
          _text('已导入批次', 'Imported batches'),
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
                _text('还没有导入批次。', 'No import batches yet.'),
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
                  label: Text(_text('删除', 'Delete')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(_text('批次 ID', 'Batch ID'), batch.batchId),
            _infoRow(_text('笔记数', 'Notes'), '${batch.notesCount.toInt()}'),
            _infoRow(_text('附件数', 'Attachments'),
                '${batch.attachmentsCount.toInt()}'),
            _infoRow(_text('失败数', 'Failed'), '${batch.failedCount.toInt()}'),
            _infoRow(_text('复制数据', 'Copied data'),
                _formatBytes(batch.copiedBytes.toInt())),
            _infoRow(
              _text('创建时间', 'Created at'),
              _formatTimestamp(batch.createdAtMs.toInt()),
            ),
            _infoRow(
              _text('更新时间', 'Updated at'),
              _formatTimestamp(batch.updatedAtMs.toInt()),
            ),
            if (batch.completedAtMs != null)
              _infoRow(
                _text('完成时间', 'Completed at'),
                _formatTimestamp(batch.completedAtMs!.toInt()),
              ),
            if (batch.lastError != null && batch.lastError!.trim().isNotEmpty)
              _infoRow(_text('最后错误', 'Last error'), batch.lastError!.trim()),
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
                            _text('正在导入外部知识', 'Importing external knowledge'),
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
                              Text(_progressStatusSummary()),
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
                                ? _text('正在请求取消', 'Requesting cancel')
                                : _text('取消导入', 'Cancel import')),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _text(
                              '导入完成或回滚清理结束前，不能返回上一页。',
                              'You cannot leave this page until the import finishes or rollback cleanup completes.',
                            ),
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
      'preparing' => _text('准备中', 'Preparing'),
      'scanning' => _text('扫描中', 'Scanning'),
      'parsing' => _text('解析中', 'Parsing'),
      'copying_attachments' => _text('复制附件中', 'Copying attachments'),
      'indexing_phase_a' => _text('建立 Phase A 索引中', 'Indexing Phase A'),
      'verifying' => _text('校验中', 'Verifying'),
      'rollback' => _text('回滚清理中', 'Rolling back'),
      'cancelled' => _text('已取消并清理', 'Cancelled and cleaned'),
      'completed' => _text('已完成', 'Completed'),
      _ => stage,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'in_progress' => _text('进行中', 'In progress'),
      'cancelling' => _text('取消中', 'Cancelling'),
      'cancelled' => _text('已取消', 'Cancelled'),
      'completed' => _text('已完成', 'Completed'),
      'failed' => _text('失败', 'Failed'),
      _ => status,
    };
  }

  String _warningBullet(String warning) => '• $warning';

  String _batchStatusSummary(ExternalImportBatchSummary batch) =>
      '${_statusLabel(batch.status)} · ${batch.sourceKind}';

  String _progressPercentSummary(String percentLabel) =>
      '${_text('进度', 'Progress')}: $percentLabel';

  String _progressProcessedSummary() =>
      '${_text('已处理', 'Processed')}: $_progressDone / $_progressTotal';

  String _progressFailedSummary() =>
      '${_text('失败', 'Failed')}: $_progressFailedCount';

  String _progressStatusSummary() =>
      '${_text('状态', 'Status')}: ${_statusLabel(_progressStatus)}';

  String _progressBatchIdSummary() =>
      '${_text('批次 ID', 'Batch ID')}: $_progressBatchId';

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
