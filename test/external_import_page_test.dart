import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/external_import_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';
part 'external_import_page_test_support.dart';

void main() {
  testWidgets('picking a directory shows external import scan summary',
      (WidgetTester tester) async {
    _installPicker(
      tester,
      directoryPath: '/tmp/obsidian-vault',
    );

    final backend = _ScanOnlyExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'obsidian-vault',
        notesCount: 27,
        attachmentsCount: 5,
        estimatedDiskUsageBytes: 16384,
        warnings: const <String>['Unsupported block was converted to markdown'],
      ),
    );

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester);

    expect(
      _labelFinder('导入 Markdown 数据', 'Import Markdown Data'),
      findsOneWidget,
    );
    expect(
      _labelFinder(
        '只读导入通用 Markdown 数据',
        'Readonly import for generic Markdown data',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('external_import_start')), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('external_import_choose_folder')));
    await _pumpUi(tester);

    expect(backend.scannedPaths, ['/tmp/obsidian-vault']);
    expect(find.text('/tmp/obsidian-vault'), findsOneWidget);
    expect(find.byKey(const ValueKey('external_import_start')), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
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
        detectedSourceKind: 'markdown',
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
    expect(find.text('Markdown'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('scan failure shows error card', (WidgetTester tester) async {
    _installPicker(
      tester,
      directoryPath: '/tmp/broken-import',
    );

    final backend = _ScanFailingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
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
        detectedSourceKind: 'markdown',
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
        detectedSourceKind: 'markdown',
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
        detectedSourceKind: 'markdown',
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
      sourceKind: 'markdown',
      sourceLabel: 'completed-import',
      status: 'completed',
      notesCount: 8,
      attachmentsCount: 2,
      failedCount: 0,
      copiedBytes: 8192,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
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

  testWidgets('completed import shows terminal report fields and report action',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/completed-import-report',
    );

    final completedBatch = _batchSummary(
      batchId: 'batch-report-1',
      sourceKind: 'markdown',
      sourceLabel: 'completed-import-report',
      status: 'completed',
      notesCount: 8,
      attachmentsCount: 2,
      failedCount: 1,
      copiedBytes: 8192,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'completed-import-report',
        notesCount: 8,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 8192,
      ),
      batchReportJsonById: <String, String>{
        'batch-report-1': _batchReportJson(
          batchId: 'batch-report-1',
          sourceKind: 'markdown',
          sourceLabel: 'completed-import-report',
          status: 'completed',
          notesCount: 8,
          attachmentsCount: 2,
          failedCount: 1,
          copiedBytes: 8192,
          successCount: 7,
          copiedAttachmentCount: 2,
          diskUsageBytes: 8192,
          elapsedMs: 10000,
          diagnostics: const <Map<String, Object?>>[],
        ),
      },
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
    await _pumpUi(tester, times: 6);

    expect(
      find.byKey(const ValueKey('external_import_view_latest_report')),
      findsOneWidget,
    );
    expect(_labelFinder('成功数', 'Success'), findsOneWidget);
    expect(_labelFinder('已复制附件', 'Copied attachments'), findsOneWidget);
    expect(_labelFinder('总耗时', 'Elapsed'), findsWidgets);
  });

  testWidgets('view report shows diagnostics for latest batch',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/completed-import-report-dialog',
    );

    final completedBatch = _batchSummary(
      batchId: 'batch-report-dialog-1',
      sourceKind: 'markdown',
      sourceLabel: 'completed-import-report-dialog',
      status: 'completed',
      notesCount: 4,
      attachmentsCount: 1,
      failedCount: 0,
      copiedBytes: 2048,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'completed-import-report-dialog',
        notesCount: 4,
        attachmentsCount: 1,
        estimatedDiskUsageBytes: 2048,
      ),
      batchReportJsonById: <String, String>{
        'batch-report-dialog-1': _batchReportJson(
          batchId: 'batch-report-dialog-1',
          sourceKind: 'markdown',
          sourceLabel: 'completed-import-report-dialog',
          status: 'completed',
          notesCount: 4,
          attachmentsCount: 1,
          failedCount: 0,
          copiedBytes: 2048,
          successCount: 4,
          copiedAttachmentCount: 1,
          diskUsageBytes: 2048,
          elapsedMs: 5000,
          diagnostics: const <Map<String, Object?>>[
            <String, Object?>{
              'stage': 'scan',
              'severity': 'warning',
              'code': 'missing_attachment_reference',
              'message': 'missing attachment reference: assets/missing.pdf',
              'source_rel_path': 'travel/plan.md',
            },
          ],
        ),
      },
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
    await _pumpUi(tester, times: 6);

    await tester
        .tap(find.byKey(const ValueKey('external_import_view_latest_report')));
    await _pumpUi(tester, times: 4);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('missing attachment reference'), findsOneWidget);
  });

  testWidgets('blocking import overlay shows eta after progress advances',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/progress-import',
    );

    final backend = _CancelableExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'progress-import',
        notesCount: 6,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 6144,
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

    backend.emitProgress(
      batchId: 'batch-eta-1',
      stage: 'parsing',
      done: 1,
      total: 4,
      failedCount: 0,
      status: 'in_progress',
    );
    await tester.pump(const Duration(seconds: 1));

    backend.emitProgress(
      batchId: 'batch-eta-1',
      stage: 'parsing',
      done: 2,
      total: 4,
      failedCount: 0,
      status: 'in_progress',
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(_labelFinder('预计剩余', 'ETA'), findsOneWidget);
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
      sourceKind: 'markdown',
      sourceLabel: 'failed-delete-import',
      status: 'completed',
      notesCount: 4,
      attachmentsCount: 1,
      failedCount: 0,
      copiedBytes: 2048,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
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
      sourceKind: 'markdown',
      sourceLabel: 'delete-import',
      status: 'completed',
      notesCount: 5,
      attachmentsCount: 1,
      failedCount: 0,
      copiedBytes: 4096,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
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
    expect(
        _labelFinder('还没有 Markdown 导入批次。', 'No Markdown import batches yet.'),
        findsOneWidget);
  });

  testWidgets(
      'first phase b run shows estimate dialog and starts after confirmation',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _PhaseBExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'phase-b-source',
        notesCount: 2,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 4096,
      ),
      phaseBStateJson: _phaseBStateJson(
        batchId: 'batch-phase-b-1',
        phaseBStatus: 'not_started',
        eligibleAttachmentCount: 2,
        processedAttachmentCount: 0,
        remainingAttachmentCount: 2,
        enrichedChunkCount: 0,
        successDocCount: 2,
        elapsedMs: 10000,
        phaseBElapsedMs: 0,
      ),
      phaseBEstimateJson: jsonEncode(<String, Object?>{
        'batch_id': 'batch-phase-b-1',
        'eligible_attachment_count': 2,
        'remaining_attachment_count': 2,
        'estimated_runtime_seconds': 4,
        'estimated_cloud_tokens': 0,
        'estimated_local_bytes': 2048,
        'estimated_local_work_units': 2,
        'phase_b_status': 'not_started',
      }),
    )..batches = <ExternalImportBatchSummary>[
        _batchSummary(
          batchId: 'batch-phase-b-1',
          sourceKind: 'markdown',
          sourceLabel: 'phase-b-source',
          status: 'completed',
          notesCount: 2,
          attachmentsCount: 2,
          failedCount: 0,
          copiedBytes: 2048,
        ),
      ];

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester, times: 6);

    await tester.tap(
        find.byKey(const ValueKey('external_import_phase_b_start_latest')));
    await _pumpUi(tester, times: 4);

    expect(backend.phaseBEstimateBatchIds, ['batch-phase-b-1']);
    expect(
        find.byKey(const ValueKey('external_import_phase_b_confirm_estimate')),
        findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('external_import_phase_b_confirm_estimate')));
    await _pumpUi(tester, times: 4);

    expect(backend.phaseBRunBatchIds, ['batch-phase-b-1']);
  });

  testWidgets('saved phase b consent auto starts on completed batch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(
      {'external_import_phase_b_consent_v1': true},
    );
    final backend = _PhaseBExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'phase-b-auto',
        notesCount: 1,
        attachmentsCount: 1,
        estimatedDiskUsageBytes: 1024,
      ),
      phaseBStateJson: _phaseBStateJson(
        batchId: 'batch-phase-b-auto',
        phaseBStatus: 'not_started',
        eligibleAttachmentCount: 1,
        processedAttachmentCount: 0,
        remainingAttachmentCount: 1,
        enrichedChunkCount: 0,
        successDocCount: 1,
        elapsedMs: 5000,
        phaseBElapsedMs: 0,
      ),
      phaseBEstimateJson: jsonEncode(<String, Object?>{
        'batch_id': 'batch-phase-b-auto',
        'eligible_attachment_count': 1,
        'remaining_attachment_count': 1,
        'estimated_runtime_seconds': 2,
        'estimated_cloud_tokens': 0,
        'estimated_local_bytes': 1024,
        'estimated_local_work_units': 1,
        'phase_b_status': 'not_started',
      }),
    )..batches = <ExternalImportBatchSummary>[
        _batchSummary(
          batchId: 'batch-phase-b-auto',
          sourceKind: 'markdown',
          sourceLabel: 'phase-b-auto',
          status: 'completed',
          notesCount: 1,
          attachmentsCount: 1,
          failedCount: 0,
          copiedBytes: 1024,
        ),
      ];

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester, times: 8);

    expect(backend.phaseBRunBatchIds, ['batch-phase-b-auto']);
  });

  testWidgets('in-progress phase b batch auto resumes on page load',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _PhaseBExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'markdown',
        sourceLabel: 'phase-b-resume',
        notesCount: 1,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 3072,
      ),
      phaseBStateJson: _phaseBStateJson(
        batchId: 'batch-phase-b-resume',
        phaseBStatus: 'in_progress',
        eligibleAttachmentCount: 2,
        processedAttachmentCount: 1,
        remainingAttachmentCount: 1,
        enrichedChunkCount: 1,
        successDocCount: 1,
        elapsedMs: 7000,
        phaseBElapsedMs: 3000,
      ),
      phaseBEstimateJson: jsonEncode(<String, Object?>{
        'batch_id': 'batch-phase-b-resume',
        'eligible_attachment_count': 2,
        'remaining_attachment_count': 1,
        'estimated_runtime_seconds': 2,
        'estimated_cloud_tokens': 0,
        'estimated_local_bytes': 1024,
        'estimated_local_work_units': 1,
        'phase_b_status': 'in_progress',
      }),
    )..batches = <ExternalImportBatchSummary>[
        _batchSummary(
          batchId: 'batch-phase-b-resume',
          sourceKind: 'markdown',
          sourceLabel: 'phase-b-resume',
          status: 'completed',
          notesCount: 1,
          attachmentsCount: 2,
          failedCount: 0,
          copiedBytes: 3072,
        ),
      ];

    await tester.pumpWidget(_buildTestApp(backend));
    await _pumpUi(tester, times: 8);

    expect(backend.phaseBRunBatchIds, ['batch-phase-b-resume']);
  });
}
