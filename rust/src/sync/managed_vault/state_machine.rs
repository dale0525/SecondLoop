#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ManagedVaultSyncState {
    Idle,
    PullingIncremental,
    CheckpointRejected,
    ReseedRequired,
    Rebootstraping,
    BlobBackfill,
    Completed,
    FailedRecoverable,
    FailedTerminal,
}
