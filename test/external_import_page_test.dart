import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/external_import_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('picking a directory shows external import scan summary',
      (WidgetTester tester) async {
    _installPicker(
      tester,
      directoryPath: '/tmp/obsidian-vault',
    );

    final backend = _ScanOnlyExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'obsidian-vault',
        notesCount: 27,
        attachmentsCount: 5,
        estimatedDiskUsageBytes: 16384,
        warnings: const <String>['Unsupported block was converted to markdown'],
      ),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    expect(find.byKey(const ValueKey('external_import_start')), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    expect(backend.scannedPaths, ['/tmp/obsidian-vault']);
    expect(find.text('/tmp/obsidian-vault'), findsOneWidget);
    expect(find.byKey(const ValueKey('external_import_start')), findsOneWidget);
    expect(find.text('obsidian'), findsOneWidget);
    expect(find.text('obsidian-vault'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(
      find.textContaining('Unsupported block was converted to markdown'),
      findsOneWidget,
    );
  });

  testWidgets('picking a zip file shows external import scan summary',
      (WidgetTester tester) async {
    _installPicker(
      tester,
      pickedFilePath: '/tmp/markdown-export.zip',
    );

    final backend = _ScanOnlyExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'generic_markdown_export',
        sourceLabel: 'markdown-export.zip',
        notesCount: 12,
        attachmentsCount: 3,
        estimatedDiskUsageBytes: 12288,
      ),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_choose_zip')));
    await _pumpUi(tester);

    expect(backend.scannedPaths, ['/tmp/markdown-export.zip']);
    expect(find.text('/tmp/markdown-export.zip'), findsOneWidget);
    expect(find.text('generic_markdown_export'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('scan failure shows error card', (WidgetTester tester) async {
    _installPicker(
      tester,
      directoryPath: '/tmp/broken-import',
    );

    final backend = _ScanFailingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'broken-import',
        notesCount: 0,
        attachmentsCount: 0,
        estimatedDiskUsageBytes: 0,
      ),
      scanError: StateError('simulated_scan_failure'),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester, times: 4);

    expect(find.text('/tmp/broken-import'), findsOneWidget);
    expect(find.byKey(const ValueKey('external_import_start')), findsNothing);
    expect(find.textContaining('simulated_scan_failure'), findsOneWidget);
  });

  testWidgets('initial batch load failure shows error card',
      (WidgetTester tester) async {
    final backend = _ListFailingExternalImportBackend(
      listError: StateError('simulated_list_batches_failure'),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester, times: 4);

    expect(
        find.textContaining('simulated_list_batches_failure'), findsOneWidget);
  });

  testWidgets('import failure shows error card and exits blocking mode',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/import-failure',
    );

    final backend = _ImportFailingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'import-failure',
        notesCount: 7,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 7168,
      ),
      importError: StateError('simulated_import_failure'),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_start')));
    await _pumpUi(tester, times: 4);

    expect(backend.runImportCalls, 1);
    expect(find.byKey(const ValueKey('external_import_cancel')), findsNothing);
    expect(find.textContaining('simulated_import_failure'), findsOneWidget);
  });

  testWidgets('cancel import requests backend cancellation for batch',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/siyuan-export',
    );

    final backend = _CancelableExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'siyuan',
        sourceLabel: 'siyuan-export',
        notesCount: 3,
        attachmentsCount: 1,
        estimatedDiskUsageBytes: 4096,
      ),
    );
    addTearDown(backend.dispose);

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_start')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('external_import_cancel')),
      findsOneWidget,
    );

    backend.emitProgress(
      batchId: 'batch-cancel-1',
      stage: 'parsing',
      done: 1,
      total: 3,
      failedCount: 0,
      status: 'in_progress',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('external_import_cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(_labelFinder('确认取消', 'Confirm cancel'));
    await _pumpUi(tester);

    expect(backend.cancelledBatchIds, ['batch-cancel-1']);
  });

  testWidgets(
      'cancel request failure shows error card and keeps import blocked',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/cancel-failure-import',
    );

    final backend = _CancelableExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'siyuan',
        sourceLabel: 'cancel-failure-import',
        notesCount: 6,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 6144,
      ),
      requestCancelError: StateError('simulated_cancel_failure'),
    );
    addTearDown(backend.dispose);

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_start')));
    await tester.pump();

    backend.emitProgress(
      batchId: 'batch-cancel-fail-1',
      stage: 'parsing',
      done: 2,
      total: 6,
      failedCount: 0,
      status: 'in_progress',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('external_import_cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(_labelFinder('确认取消', 'Confirm cancel'));
    await _pumpUi(tester, times: 4);

    expect(backend.cancelledBatchIds, ['batch-cancel-fail-1']);
    expect(
        find.byKey(const ValueKey('external_import_cancel')), findsOneWidget);
    expect(find.textContaining('simulated_cancel_failure'), findsOneWidget);
  });

  testWidgets('completed import shows latest result summary',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/completed-import',
    );

    final completedBatch = _batchSummary(
      batchId: 'batch-complete-1',
      sourceKind: 'obsidian',
      sourceLabel: 'completed-import',
      status: 'completed',
      notesCount: 8,
      attachmentsCount: 2,
      failedCount: 0,
      copiedBytes: 8192,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'completed-import',
        notesCount: 8,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 8192,
      ),
    );
    addTearDown(backend.dispose);

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_start')));
    await tester.pump();

    backend.completeImport(completedBatch);
    await _pumpUi(tester, times: 4);

    expect(backend.runImportCalls, 1);
    expect(find.byKey(const ValueKey('external_import_delete_latest_batch')),
        findsOneWidget);
    expect(
      find.textContaining('completed-import'),
      findsWidgets,
    );
    expect(
        _labelFinder('最近一次导入：已完成', 'Latest import: completed'), findsOneWidget);
  });

  testWidgets('delete batch failure shows error card and keeps batch',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/failed-delete-import',
    );

    final batch = _batchSummary(
      batchId: 'batch-delete-fail-1',
      sourceKind: 'obsidian',
      sourceLabel: 'failed-delete-import',
      status: 'completed',
      notesCount: 4,
      attachmentsCount: 1,
      failedCount: 0,
      copiedBytes: 2048,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'failed-delete-import',
        notesCount: 4,
        attachmentsCount: 1,
        estimatedDiskUsageBytes: 2048,
      ),
      deleteError: StateError('simulated_delete_failure'),
    );
    addTearDown(backend.dispose);

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_start')));
    await tester.pump();

    backend.completeImport(batch);
    await _pumpUi(tester, times: 4);

    expect(find.byKey(const ValueKey('external_import_delete_latest_batch')),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('external_import_delete_latest_batch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final dialogFinder = find.byType(AlertDialog);
    expect(dialogFinder, findsOneWidget);
    final confirmDeleteFinder = find.descendant(
      of: dialogFinder,
      matching: _labelFinder('删除', 'Delete'),
    );
    await tester.tap(confirmDeleteFinder.first);
    await _pumpUi(tester, times: 4);

    expect(backend.deletedBatchIds, ['batch-delete-fail-1']);
    expect(find.byKey(const ValueKey('external_import_delete_latest_batch')),
        findsOneWidget);
    expect(find.textContaining('simulated_delete_failure'), findsOneWidget);
    expect(find.textContaining('failed-delete-import'), findsWidgets);
  });

  testWidgets('deleting latest import batch requests backend delete',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/delete-import',
    );

    final completedBatch = _batchSummary(
      batchId: 'batch-delete-1',
      sourceKind: 'obsidian',
      sourceLabel: 'delete-import',
      status: 'completed',
      notesCount: 5,
      attachmentsCount: 1,
      failedCount: 0,
      copiedBytes: 4096,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'delete-import',
        notesCount: 5,
        attachmentsCount: 1,
        estimatedDiskUsageBytes: 4096,
      ),
    );
    addTearDown(backend.dispose);

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    await tester.tap(find.byKey(const ValueKey('external_import_start')));
    await tester.pump();

    backend.completeImport(completedBatch);
    await _pumpUi(tester, times: 4);

    await tester
        .tap(find.byKey(const ValueKey('external_import_delete_latest_batch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final dialogFinder = find.byType(AlertDialog);
    expect(dialogFinder, findsOneWidget);
    final confirmDeleteFinder = find.descendant(
      of: dialogFinder,
      matching: _labelFinder('删除', 'Delete'),
    );
    await tester.tap(confirmDeleteFinder.first);
    await _pumpUi(tester, times: 4);

    expect(backend.deletedBatchIds, ['batch-delete-1']);
    expect(find.byKey(const ValueKey('external_import_delete_latest_batch')),
        findsNothing);
    expect(_labelFinder('还没有导入批次。', 'No import batches yet.'), findsOneWidget);
  });
}

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
  });

  final Object? deleteError;
  final List<String> deletedBatchIds = <String>[];
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
