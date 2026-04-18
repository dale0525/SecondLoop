#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ManagedVaultSyncState {
    Idle,
    PullingIncremental,
    CheckpointRejected,
    ReseedRequired,
    Rebootstrapping,
    BlobBackfill,
    Completed,
    FailedRecoverable,
    FailedTerminal,
}

impl ManagedVaultSyncState {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            ManagedVaultSyncState::Idle => "idle",
            ManagedVaultSyncState::PullingIncremental => "pulling_incremental",
            ManagedVaultSyncState::CheckpointRejected => "checkpoint_rejected",
            ManagedVaultSyncState::ReseedRequired => "reseed_required",
            ManagedVaultSyncState::Rebootstrapping => "rebootstrapping",
            ManagedVaultSyncState::BlobBackfill => "blob_backfill",
            ManagedVaultSyncState::Completed => "completed",
            ManagedVaultSyncState::FailedRecoverable => "failed_recoverable",
            ManagedVaultSyncState::FailedTerminal => "failed_terminal",
        }
    }
}

fn state_key(scope_id: &str) -> String {
    format!("managed_vault.state:{scope_id}")
}

#[cfg_attr(target_family = "wasm", allow(dead_code))]
pub(crate) fn load_state(
    conn: &rusqlite::Connection,
    scope_id: &str,
) -> anyhow::Result<Option<ManagedVaultSyncState>> {
    let value = super::super::kv_get_string(conn, &state_key(scope_id))?;
    Ok(match value.as_deref() {
        Some("idle") => Some(ManagedVaultSyncState::Idle),
        Some("pulling_incremental") => Some(ManagedVaultSyncState::PullingIncremental),
        Some("checkpoint_rejected") => Some(ManagedVaultSyncState::CheckpointRejected),
        Some("reseed_required") => Some(ManagedVaultSyncState::ReseedRequired),
        Some("rebootstrapping") | Some("rebootstraping") => {
            Some(ManagedVaultSyncState::Rebootstrapping)
        }
        Some("blob_backfill") => Some(ManagedVaultSyncState::BlobBackfill),
        Some("completed") => Some(ManagedVaultSyncState::Completed),
        Some("failed_recoverable") => Some(ManagedVaultSyncState::FailedRecoverable),
        Some("failed_terminal") => Some(ManagedVaultSyncState::FailedTerminal),
        _ => None,
    })
}

pub(crate) fn transition(
    conn: &rusqlite::Connection,
    scope_id: &str,
    next: ManagedVaultSyncState,
) -> anyhow::Result<()> {
    super::super::kv_set_string(conn, &state_key(scope_id), next.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_state_accepts_legacy_rebootstraping_value() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        super::super::super::kv_set_string(&conn, "managed_vault.state:scope-a", "rebootstraping")
            .expect("seed legacy state");

        assert_eq!(
            load_state(&conn, "scope-a").expect("load"),
            Some(ManagedVaultSyncState::Rebootstrapping)
        );
    }
}
