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

  testWidgets('completed import shows terminal report fields and report action',
      (WidgetTester tester) async {
    _setLargeViewport(tester);
    _installPicker(
      tester,
      directoryPath: '/tmp/completed-import-report',
    );

    final completedBatch = _batchSummary(
      batchId: 'batch-report-1',
      sourceKind: 'obsidian',
      sourceLabel: 'completed-import-report',
      status: 'completed',
      notesCount: 8,
      attachmentsCount: 2,
      failedCount: 1,
      copiedBytes: 8192,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'completed-import-report',
        notesCount: 8,
        attachmentsCount: 2,
        estimatedDiskUsageBytes: 8192,
      ),
      batchReportJsonById: <String, String>{
        'batch-report-1': _batchReportJson(
          batchId: 'batch-report-1',
          sourceKind: 'obsidian',
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
      sourceKind: 'obsidian',
      sourceLabel: 'completed-import-report-dialog',
      status: 'completed',
      notesCount: 4,
      attachmentsCount: 1,
      failedCount: 0,
      copiedBytes: 2048,
    );
    final backend = _CompletingExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
        sourceLabel: 'completed-import-report-dialog',
        notesCount: 4,
        attachmentsCount: 1,
        estimatedDiskUsageBytes: 2048,
      ),
      batchReportJsonById: <String, String>{
        'batch-report-dialog-1': _batchReportJson(
          batchId: 'batch-report-dialog-1',
          sourceKind: 'obsidian',
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
        detectedSourceKind: 'obsidian',
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

  testWidgets(
      'first phase b run shows estimate dialog and starts after confirmation',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = _PhaseBExternalImportBackend(
      scanSummary: _scanSummary(
        detectedSourceKind: 'obsidian',
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
          sourceKind: 'obsidian',
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
        detectedSourceKind: 'obsidian',
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
          sourceKind: 'obsidian',
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
        detectedSourceKind: 'obsidian',
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
          sourceKind: 'obsidian',
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
