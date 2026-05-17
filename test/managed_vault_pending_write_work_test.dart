import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/sync/managed_vault_pending_write_work.dart';
import 'package:secondloop/core/models/app_models.dart';

void main() {
  test('blob repair queue keeps managed-vault write work pending', () {
    expect(
      hasManagedVaultPendingWriteWork(
        mediaSummary: const CloudMediaBackupSummary(
          pending: 0,
          failed: 0,
          uploaded: 0,
        ),
        blobRepairQueueDepth: 1,
      ),
      isTrue,
    );
  });

  test('empty media queue and empty repair queue clear pending state', () {
    expect(
      hasManagedVaultPendingWriteWork(
        mediaSummary: const CloudMediaBackupSummary(
          pending: 0,
          failed: 0,
          uploaded: 0,
        ),
        blobRepairQueueDepth: 0,
      ),
      isFalse,
    );
  });
}
