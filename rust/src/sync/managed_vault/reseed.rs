use anyhow::Result;
use rusqlite::Connection;

pub(super) fn clear_protocol_checkpoint_state(conn: &Connection, scope_id: &str) -> Result<()> {
    super::checkpoint::clear_checkpoint_state(conn, scope_id)
}
