import 'package:secondloop/core/models/app_models.dart';

bool hasManagedVaultPendingWriteWork({
  required CloudMediaBackupSummary mediaSummary,
  required int blobRepairQueueDepth,
}) {
  return mediaSummary.pending.toInt() > 0 ||
      mediaSummary.failed.toInt() > 0 ||
      blobRepairQueueDepth > 0;
}
