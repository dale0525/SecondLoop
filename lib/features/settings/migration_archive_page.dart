import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

class MigrationArchivePage extends StatefulWidget {
  const MigrationArchivePage({super.key});

  @override
  State<MigrationArchivePage> createState() => _MigrationArchivePageState();
}

final class _MigrationArchiveProgressViewData {
  const _MigrationArchiveProgressViewData({
    required this.operation,
    required this.stage,
    required this.status,
    required this.done,
    required this.total,
  });

  final String operation;
  final String stage;
  final String status;
  final int done;
  final int total;
}

class _MigrationArchivePageState extends State<MigrationArchivePage> {
  static const String _typedConfirmPhrase = 'IMPORT';

  final TextEditingController _confirmInputController = TextEditingController();

  MigrationArchiveManifest? _lastExportManifest;
  MigrationArchiveManifest? _importPreviewManifest;
  MigrationArchiveManifest? _lastImportManifest;
  MigrationArchiveExportEstimate? _exportEstimate;
  _MigrationArchiveProgressViewData? _progress;
  String? _exportPath;
  String? _importPath;
  String? _errorMessage;
  int? _importArchiveSizeBytes;
  bool _busy = false;
  bool _confirmDestructiveImport = false;

  AppBackend get _backend => AppBackendScope.of(context);
  Uint8List get _sessionKey => SessionScope.of(context).sessionKey;

  bool get _typedConfirmMatches =>
      _confirmInputController.text.trim() == _typedConfirmPhrase;

  bool get _canStartImport =>
      !_busy &&
      _importPath != null &&
      _confirmDestructiveImport &&
      _typedConfirmMatches;

  @override
  void initState() {
    super.initState();
    _confirmInputController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _confirmInputController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_exportEstimate != null) return;
    unawaited(_loadEstimate());
  }

  Future<void> _loadEstimate() async {
    try {
      final estimate =
          await _backend.estimateMigrationArchiveExport(_sessionKey);
      if (!mounted) return;
      setState(() => _exportEstimate = estimate);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    }
  }

  Future<void> _pickExportPath() async {
    if (_busy) return;
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: context.t.settings.migrationArchive.exportDialogTitle,
      fileName: 'secondloop-migration.zip',
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    if (outputPath == null || outputPath.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
      _progress = null;
      _exportPath = outputPath;
      _lastExportManifest = null;
    });
    try {
      await _consumeMigrationArchiveStream(
        _backend.runMigrationArchiveExportProgress(
          _sessionKey,
          outputPath: outputPath,
        ),
        onResult: (manifest) {
          _lastExportManifest = manifest;
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImportArchive() async {
    if (_busy) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: context.t.settings.migrationArchive.importDialogTitle,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
      lockParentWindow: true,
    );
    final file = picked?.files.singleOrNull;
    final path = file?.path;
    if (path == null || path.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
      _progress = null;
      _importPath = path;
      _importArchiveSizeBytes = file?.size;
      _importPreviewManifest = null;
      _lastImportManifest = null;
      _confirmDestructiveImport = false;
      _confirmInputController.clear();
    });
    try {
      final manifest =
          await _backend.inspectMigrationArchive(archivePath: path);
      if (!mounted) return;
      setState(() {
        _importPreviewManifest = manifest;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startImport() async {
    final importPath = _importPath;
    if (!_canStartImport || importPath == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
      _progress = null;
      _lastImportManifest = null;
    });
    try {
      await _consumeMigrationArchiveStream(
        _backend.runMigrationArchiveImportProgress(
          _sessionKey,
          archivePath: importPath,
        ),
        onResult: (manifest) {
          _lastImportManifest = manifest;
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _consumeMigrationArchiveStream(
    Stream<String> stream, {
    required void Function(MigrationArchiveManifest manifest) onResult,
  }) async {
    await for (final raw in stream) {
      final payload = jsonDecode(raw);
      if (payload is! Map<String, dynamic>) continue;
      final type = payload['type'] as String? ?? '';
      if (type == 'progress') {
        if (!mounted) continue;
        setState(() {
          _progress = _MigrationArchiveProgressViewData(
            operation: payload['operation'] as String? ?? '',
            stage: payload['stage'] as String? ?? '',
            status: payload['status'] as String? ?? '',
            done: (payload['done'] as num?)?.toInt() ?? 0,
            total: (payload['total'] as num?)?.toInt() ?? 0,
          );
        });
        continue;
      }
      if (type == 'result') {
        final manifestJson = payload['manifest'];
        if (manifestJson is! Map<String, dynamic>) continue;
        final manifest = _manifestFromJson(manifestJson);
        if (!mounted) continue;
        setState(() {
          onResult(manifest);
        });
      }
    }
  }

  MigrationArchiveManifest _manifestFromJson(Map<String, dynamic> json) {
    return MigrationArchiveManifest(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 0,
      archiveKind: json['archive_kind'] as String? ?? '',
      exportedAtMs: (json['exported_at_ms'] as num?)?.toInt() ?? 0,
      appVersion: json['app_version'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => MigrationArchiveItem(
              id: item['id'] as String? ?? '',
              entityType: item['entity_type'] as String? ?? '',
              markdownPath: item['markdown_path'] as String? ?? '',
              createdAtMs: (item['created_at_ms'] as num?)?.toInt() ?? 0,
              updatedAtMs: (item['updated_at_ms'] as num?)?.toInt() ?? 0,
              title: item['title'] as String? ?? '',
              tags: (item['tags'] as List<dynamic>? ?? const <dynamic>[])
                  .map((tag) => tag.toString())
                  .toList(growable: false),
              status: item['status'] as String?,
              extraJson: item['extra_json'] as String?,
            ),
          )
          .toList(growable: false),
      attachments: (json['attachments'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (attachment) => MigrationArchiveAttachment(
              sha256: attachment['sha256'] as String? ?? '',
              archivePath: attachment['archive_path'] as String? ?? '',
              originalFilename:
                  attachment['original_filename'] as String? ?? '',
              mimeType: attachment['mime_type'] as String?,
              sizeBytes: (attachment['size_bytes'] as num?)?.toInt() ?? 0,
              itemIds: (attachment['item_ids'] as List<dynamic>? ??
                      const <dynamic>[])
                  .map((id) => id.toString())
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
      relations: (json['relations'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (relation) => MigrationArchiveRelation(
              fromId: relation['from_id'] as String? ?? '',
              toId: relation['to_id'] as String? ?? '',
              relationType: relation['relation_type'] as String? ?? '',
            ),
          )
          .toList(growable: false),
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _operationLabel(_MigrationArchiveProgressViewData progress) {
    final t = context.t.settings.migrationArchive;
    return switch (progress.operation) {
      'export' => t.operationExport,
      'import' => t.operationImport,
      _ => progress.operation,
    };
  }

  String _statusLabel(_MigrationArchiveProgressViewData progress) {
    final t = context.t.settings.migrationArchive;
    return switch (progress.status) {
      'completed' => t.statusCompleted,
      'rollback' => t.statusRollback,
      _ => t.statusInProgress,
    };
  }

  String _stageLabel(_MigrationArchiveProgressViewData progress) {
    final t = context.t.settings.migrationArchive;
    return switch (progress.stage) {
      'preparing' => t.stagePreparing,
      'collecting' => t.stageCollecting,
      'writing_markdown' => t.stageWritingMarkdown,
      'copying_attachments' => t.stageCopyingAttachments,
      'zipping' => t.stageZipping,
      'completed' => t.stageCompleted,
      'snapshot_created' => t.stageSnapshotCreated,
      'vault_cleared' => t.stageVaultCleared,
      'base_items_restored' => t.stageBaseItemsRestored,
      'attachments_restored' => t.stageAttachmentsRestored,
      'relations_restored' => t.stageRelationsRestored,
      'reindex_completed' => t.stageReindexCompleted,
      'rollback' => t.stageRollback,
      _ => progress.stage,
    };
  }

  Widget _summaryRows(
    MigrationArchiveManifest manifest, {
    int? archiveSizeBytes,
  }) {
    final t = context.t.settings.migrationArchive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(t.schemaVersion, '${manifest.schemaVersion.toInt()}'),
        _infoRow(t.archiveItems, '${manifest.items.length}'),
        _infoRow(t.archiveAttachments, '${manifest.attachments.length}'),
        if (archiveSizeBytes != null)
          _infoRow(t.archiveSize, _formatBytes(archiveSizeBytes)),
        _infoRow(t.exportedAt, _formatDate(manifest.exportedAtMs.toInt())),
      ],
    );
  }

  Widget _progressCard(_MigrationArchiveProgressViewData progress) {
    final t = context.t.settings.migrationArchive;
    return SlSurface(
      key: const ValueKey('migration_archive_progress'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.progressTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _infoRow(t.progressOperation, _operationLabel(progress)),
            _infoRow(
              t.progressStage,
              _stageLabel(progress),
              valueKey: const ValueKey('migration_archive_progress_stage'),
            ),
            _infoRow(t.progressStatus, _statusLabel(progress)),
            _infoRow(t.progressStep, '${progress.done}/${progress.total}'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label)),
          Expanded(child: Text(value, key: valueKey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.settings.migrationArchive;
    final preview = _importPreviewManifest;
    final progress = _progress;

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SlSurface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.introTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(t.introBody),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SlSurface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.exportSectionTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (_exportEstimate != null) ...[
                    _infoRow(t.archiveItems,
                        '${_exportEstimate!.itemCount.toInt()}'),
                    _infoRow(
                      t.archiveAttachments,
                      '${_exportEstimate!.attachmentCount.toInt()}',
                    ),
                    _infoRow(
                      t.archiveSize,
                      _formatBytes(_exportEstimate!.estimatedSizeBytes.toInt()),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    key: const ValueKey('migration_archive_export'),
                    onPressed: _busy ? null : _pickExportPath,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(t.exportAction),
                  ),
                  if (_exportPath != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _exportPath!,
                      key: const ValueKey('migration_archive_export_path'),
                    ),
                  ],
                  if (_lastExportManifest != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey('migration_archive_export_result'),
                      child: _summaryRows(_lastExportManifest!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SlSurface(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.importSectionTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('migration_archive_pick_import'),
                    onPressed: _busy ? null : _pickImportArchive,
                    icon: const Icon(Icons.archive_outlined),
                    label: Text(t.importPickArchive),
                  ),
                  if (_importPath != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _importPath!,
                      key: const ValueKey('migration_archive_import_path'),
                    ),
                  ],
                  if (preview != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      key: const ValueKey('migration_archive_import_summary'),
                      child: _summaryRows(
                        preview,
                        archiveSizeBytes: _importArchiveSizeBytes,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      key: const ValueKey('migration_archive_confirm'),
                      value: _confirmDestructiveImport,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.destructiveConfirmTitle),
                      subtitle: Text(t.destructiveConfirmBody),
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                _confirmDestructiveImport = value ?? false;
                              });
                            },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('migration_archive_confirm_input'),
                      controller: _confirmInputController,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: t.confirmInputLabel,
                        hintText: t.confirmInputHint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const ValueKey('migration_archive_start_import'),
                      onPressed: _canStartImport ? _startImport : null,
                      child: Text(t.importAction),
                    ),
                  ],
                  if (_lastImportManifest != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      key: const ValueKey('migration_archive_import_result'),
                      child: _summaryRows(_lastImportManifest!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 16),
            _progressCard(progress),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(
              key: ValueKey('migration_archive_busy'),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            SlSurface(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  key: const ValueKey('migration_archive_error'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
