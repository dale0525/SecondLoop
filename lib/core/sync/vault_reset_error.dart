const kVaultResetCommittedCleanupFailureCode =
    'vault_reset_committed_cleanup_failed';

bool isVaultResetCommittedCleanupFailure(Object error) {
  final message = error.toString();
  return message.contains(kVaultResetCommittedCleanupFailureCode) ||
      message.contains('filesystem cleanup failed after vault reset commit');
}
