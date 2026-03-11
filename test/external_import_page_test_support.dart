part of 'external_import_page_test.dart';

Widget _buildTestApp(AppBackend backend) {
  return AppBackendScope(
    backend: backend,
    child: SessionScope(
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
      lock: () {},
      child: wrapWithI18n(
        const MaterialApp(
          home: Scaffold(
            body: ExternalImportPage(),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpUi(WidgetTester tester, {int times = 2}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _setLargeViewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1200, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _installPicker(
  WidgetTester tester, {
  String? directoryPath,
  String? pickedFilePath,
}) {
  FilePicker? oldPicker;
  try {
    oldPicker = FilePicker.platform;
  } catch (_) {
    oldPicker = null;
  }
  FilePicker.platform = _TestExternalImportFilePicker(
    directoryPath: directoryPath,
    pickedFilePath: pickedFilePath,
  );
  addTearDown(() {
    FilePicker.platform = oldPicker ?? _TestExternalImportFilePicker();
  });
}

Finder _labelFinder(String zh, String en) {
  final zhFinder = find.text(zh);
  if (zhFinder.evaluate().isNotEmpty) {
    return zhFinder;
  }
  return find.text(en);
}

ExternalImportScanSummary _scanSummary({
  required String detectedSourceKind,
  required String sourceLabel,
  required int notesCount,
  required int attachmentsCount,
  required int estimatedDiskUsageBytes,
  List<String> warnings = const <String>[],
}) {
  return ExternalImportScanSummary(
    detectedSourceKind: detectedSourceKind,
    sourceLabel: sourceLabel,
    notesCount: notesCount,
    attachmentsCount: attachmentsCount,
    estimatedDiskUsageBytes: estimatedDiskUsageBytes,
    warnings: warnings,
  );
}

ExternalImportBatchSummary _batchSummary({
  required String batchId,
  required String sourceKind,
  required String sourceLabel,
  required String status,
  required int notesCount,
  required int attachmentsCount,
  required int failedCount,
  required int copiedBytes,
}) {
  return ExternalImportBatchSummary(
    batchId: batchId,
    sourceKind: sourceKind,
    sourceLabel: sourceLabel,
    status: status,
    notesCount: notesCount,
    attachmentsCount: attachmentsCount,
    failedCount: failedCount,
    copiedBytes: copiedBytes,
    createdAtMs: 1710000000000,
    updatedAtMs: 1710000005000,
    completedAtMs: 1710000010000,
    lastError: null,
  );
}

String _batchReportJson({
  required String batchId,
  required String sourceKind,
  required String sourceLabel,
  required String status,
  required int notesCount,
  required int attachmentsCount,
  required int failedCount,
  required int copiedBytes,
  required int successCount,
  required int copiedAttachmentCount,
  required int diskUsageBytes,
  required int elapsedMs,
  required List<Map<String, Object?>> diagnostics,
}) {
  return jsonEncode(<String, Object?>{
    'batch_id': batchId,
    'source_kind': sourceKind,
    'source_label': sourceLabel,
    'status': status,
    'notes_count': notesCount,
    'attachments_count': attachmentsCount,
    'failed_count': failedCount,
    'copied_bytes': copiedBytes,
    'success_count': successCount,
    'copied_attachment_count': copiedAttachmentCount,
    'disk_usage_bytes': diskUsageBytes,
    'elapsed_ms': elapsedMs,
    'created_at_ms': 1710000000000,
    'updated_at_ms': 1710000005000,
    'completed_at_ms': 1710000010000,
    'last_error': null,
    'diagnostics': diagnostics,
  });
}

String _phaseBStateJson({
  required String batchId,
  required String phaseBStatus,
  required int eligibleAttachmentCount,
  required int processedAttachmentCount,
  required int remainingAttachmentCount,
  required int enrichedChunkCount,
  required int successDocCount,
  required int elapsedMs,
  required int phaseBElapsedMs,
}) {
  return jsonEncode(<String, Object?>{
    'batch_id': batchId,
    'batch_status': 'completed',
    'phase_b_status': phaseBStatus,
    'notes_count': successDocCount,
    'attachments_count': eligibleAttachmentCount,
    'failed_count': 0,
    'copied_bytes': 2048,
    'eligible_attachment_count': eligibleAttachmentCount,
    'processed_attachment_count': processedAttachmentCount,
    'remaining_attachment_count': remainingAttachmentCount,
    'failed_attachment_count': 0,
    'enriched_chunk_count': enrichedChunkCount,
    'success_doc_count': successDocCount,
    'attachment_ref_count': eligibleAttachmentCount,
    'created_at_ms': 1710000000000,
    'updated_at_ms': 1710000005000,
    'completed_at_ms': 1710000010000,
    'elapsed_ms': elapsedMs,
    'phase_b_started_at_ms': 1710000010000,
    'phase_b_completed_at_ms':
        phaseBStatus == 'completed' ? 1710000010000 + phaseBElapsedMs : null,
    'phase_b_elapsed_ms': phaseBElapsedMs,
    'last_error': null,
    'phase_b_last_error': null,
  });
}

class _BaseExternalImportBackend extends TestAppBackend {
  _BaseExternalImportBackend({required this.scanSummary});

  final ExternalImportScanSummary scanSummary;
  final List<String> scannedPaths = <String>[];
  List<ExternalImportBatchSummary> batches =
      const <ExternalImportBatchSummary>[];
  int listBatchesCalls = 0;

  @override
  Future<List<ExternalImportBatchSummary>> listExternalImportBatches() async {
    listBatchesCalls += 1;
    return List<ExternalImportBatchSummary>.from(batches);
  }

  @override
  Future<ExternalImportScanSummary> scanExternalImportSource({
    required String sourcePath,
  }) async {
    scannedPaths.add(sourcePath);
    return scanSummary;
  }
}

final class _ScanOnlyExternalImportBackend extends _BaseExternalImportBackend {
  _ScanOnlyExternalImportBackend({required super.scanSummary});
}

final class _CancelableExternalImportBackend
    extends _BaseExternalImportBackend {
  _CancelableExternalImportBackend({
    required super.scanSummary,
    this.requestCancelError,
  });

  final Object? requestCancelError;
  final List<String> cancelledBatchIds = <String>[];
  final StreamController<String> _importProgressController =
      StreamController<String>();
  bool _disposed = false;
  int runImportCalls = 0;

  void emitProgress({
    required String batchId,
    required String stage,
    required int done,
    required int total,
    required int failedCount,
    required String status,
  }) {
    _importProgressController.add(
      jsonEncode(<String, Object?>{
        'type': 'progress',
        'batch_id': batchId,
        'stage': stage,
        'done': done,
        'total': total,
        'failed_count': failedCount,
        'status': status,
      }),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _importProgressController.close();
  }

  @override
  Stream<String> runExternalImportProgress(
    Uint8List key, {
    required String sourcePath,
  }) {
    runImportCalls += 1;
    return _importProgressController.stream;
  }

  @override
  Future<void> requestExternalImportCancel({required String batchId}) async {
    cancelledBatchIds.add(batchId);
    if (requestCancelError != null) {
      throw requestCancelError!;
    }
  }
}

final class _CompletingExternalImportBackend
    extends _BaseExternalImportBackend {
  _CompletingExternalImportBackend({
    required super.scanSummary,
    this.deleteError,
    Map<String, String>? batchReportJsonById,
  }) : batchReportJsonById = batchReportJsonById ?? <String, String>{};

  final Object? deleteError;
  final Map<String, String> batchReportJsonById;
  final List<String> deletedBatchIds = <String>[];
  final List<String> reportBatchIds = <String>[];
  final StreamController<String> _importProgressController =
      StreamController<String>();
  bool _disposed = false;
  int runImportCalls = 0;

  void completeImport(ExternalImportBatchSummary summary) {
    batches = <ExternalImportBatchSummary>[summary];
    _importProgressController.add(
      jsonEncode(<String, Object?>{
        'type': 'progress',
        'batch_id': summary.batchId,
        'stage': 'completed',
        'done': 1,
        'total': 1,
        'failed_count': summary.failedCount,
        'status': 'completed',
      }),
    );
    _importProgressController.add(
      jsonEncode(<String, Object?>{
        'type': 'result',
        'batch_id': summary.batchId,
        'status': summary.status,
      }),
    );
    _importProgressController.close();
    _disposed = true;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _importProgressController.close();
  }

  @override
  Stream<String> runExternalImportProgress(
    Uint8List key, {
    required String sourcePath,
  }) {
    runImportCalls += 1;
    return _importProgressController.stream;
  }

  @override
  Future<void> deleteExternalImportBatch({required String batchId}) async {
    deletedBatchIds.add(batchId);
    if (deleteError != null) {
      throw deleteError!;
    }
    batches = batches.where((batch) => batch.batchId != batchId).toList();
  }

  @override
  Future<String> readExternalImportBatchReport(
      {required String batchId}) async {
    reportBatchIds.add(batchId);
    final report = batchReportJsonById[batchId];
    if (report == null) {
      throw StateError('missing_batch_report_$batchId');
    }
    return report;
  }
}

final class _PhaseBExternalImportBackend extends _BaseExternalImportBackend {
  _PhaseBExternalImportBackend({
    required super.scanSummary,
    required this.phaseBStateJson,
    required this.phaseBEstimateJson,
  });

  final String phaseBStateJson;
  final String phaseBEstimateJson;
  final List<String> phaseBStateBatchIds = <String>[];
  final List<String> phaseBEstimateBatchIds = <String>[];
  final List<String> phaseBRunBatchIds = <String>[];

  @override
  Future<String> readExternalImportPhaseBState(
      {required String batchId}) async {
    phaseBStateBatchIds.add(batchId);
    return phaseBStateJson;
  }

  @override
  Future<String> estimateExternalImportPhaseB({required String batchId}) async {
    phaseBEstimateBatchIds.add(batchId);
    return phaseBEstimateJson;
  }

  @override
  Stream<String> runExternalImportPhaseBProgress(
    Uint8List key, {
    required String batchId,
  }) {
    phaseBRunBatchIds.add(batchId);
    return Stream<String>.fromIterable(<String>[
      jsonEncode(<String, Object?>{
        'type': 'progress',
        'batch_id': batchId,
        'stage': 'indexing_phase_b',
        'done': 1,
        'total': 1,
        'failed_count': 0,
        'status': 'in_progress',
      }),
      jsonEncode(<String, Object?>{
        'type': 'phase_b_result',
        'batch_id': batchId,
      }),
    ]);
  }
}

final class _ScanFailingExternalImportBackend
    extends _BaseExternalImportBackend {
  _ScanFailingExternalImportBackend({
    required super.scanSummary,
    required this.scanError,
  });

  final Object scanError;

  @override
  Future<ExternalImportScanSummary> scanExternalImportSource({
    required String sourcePath,
  }) async {
    scannedPaths.add(sourcePath);
    throw scanError;
  }
}

final class _ListFailingExternalImportBackend extends TestAppBackend {
  _ListFailingExternalImportBackend({required this.listError});

  final Object listError;

  @override
  Future<List<ExternalImportBatchSummary>> listExternalImportBatches() async {
    throw listError;
  }
}

final class _ImportFailingExternalImportBackend
    extends _BaseExternalImportBackend {
  _ImportFailingExternalImportBackend({
    required super.scanSummary,
    required this.importError,
  });

  final Object importError;
  int runImportCalls = 0;

  @override
  Stream<String> runExternalImportProgress(
    Uint8List key, {
    required String sourcePath,
  }) async* {
    runImportCalls += 1;
    throw importError;
  }
}

final class _TestExternalImportFilePicker extends FilePicker {
  _TestExternalImportFilePicker({
    this.directoryPath,
    this.pickedFilePath,
  });

  final String? directoryPath;
  final String? pickedFilePath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async =>
      directoryPath;

  @override
  Future<FilePickerResult?> pickFiles({
    Function(FilePickerStatus)? onFileLoading,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool allowCompression = true,
    int compressionQuality = 30,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final path = pickedFilePath;
    if (path == null) return null;
    final name = path.split('/').last;
    return FilePickerResult(<PlatformFile>[
      PlatformFile(
        name: name,
        path: path,
        size: 0,
      ),
    ]);
  }
}
