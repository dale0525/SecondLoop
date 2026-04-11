use anyhow::Result;
use rusqlite::Connection;

pub(super) fn clear_protocol_checkpoint_state(conn: &Connection, scope_id: &str) -> Result<()> {
    super::checkpoint::clear_checkpoint_state(conn, scope_id)
}

pub(super) fn restart_incremental_pull(conn: &Connection, scope_id: &str) -> Result<()> {
    clear_protocol_checkpoint_state(conn, scope_id)?;
    super::pending_apply::update_since_map(conn, scope_id, &std::collections::BTreeMap::new())?;
    Ok(())
}
