import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend.init cleans up interrupted external import batches',
      () async {
    final deletedBatchIds = <String>[];
    final backend = _RecoveringNativeBackend(
      batches: <ExternalImportBatchSummary>[
        _batch(batchId: 'batch-in-progress', status: 'in_progress'),
        _batch(batchId: 'batch-cancelling', status: 'cancelling'),
        _batch(batchId: 'batch-completed', status: 'completed'),
        _batch(batchId: 'batch-failed', status: 'failed'),
        _batch(batchId: 'batch-cancelled', status: 'cancelled'),
      ],
      onDelete: deletedBatchIds.add,
    );

    await backend.init();

    expect(deletedBatchIds, <String>['batch-in-progress', 'batch-cancelling']);
  });
}

final class _RecoveringNativeBackend extends NativeAppBackend {
  _RecoveringNativeBackend({
    required this.batches,
    required this.onDelete,
  }) : super(
          appDirProvider: () async => '/tmp/secondloop_test',
          rustLibInit: () async {},
        );

  final List<ExternalImportBatchSummary> batches;
  final void Function(String batchId) onDelete;

  @override
  Future<List<ExternalImportBatchSummary>> listExternalImportBatches() async {
    return List<ExternalImportBatchSummary>.from(batches);
  }

  @override
  Future<void> deleteExternalImportBatch({required String batchId}) async {
    onDelete(batchId);
  }
}

ExternalImportBatchSummary _batch({
  required String batchId,
  required String status,
}) {
  return ExternalImportBatchSummary(
    batchId: batchId,
    sourceKind: 'obsidian',
    sourceLabel: batchId,
    status: status,
    notesCount: 0,
    attachmentsCount: 0,
    failedCount: 0,
    copiedBytes: 0,
    createdAtMs: 1710000000000,
    updatedAtMs: 1710000005000,
    completedAtMs: null,
    lastError: null,
  );
}
