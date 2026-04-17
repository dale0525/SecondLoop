use anyhow::Result;
use rusqlite::{params, Connection};

fn generation_key(scope_id: &str) -> String {
    format!("managed_vault_v2.generation_id:{scope_id}")
}

fn last_applied_key(scope_id: &str) -> String {
    format!("managed_vault_v2.last_applied_global_seq:{scope_id}")
}

fn last_pushed_key(scope_id: &str, device_id: &str) -> String {
    format!("managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}")
}

pub(super) fn apply_scope_id(scope_id: &str) -> String {
    format!("managed_vault_v2:{scope_id}")
}

pub(super) fn read_generation_id(conn: &Connection, scope_id: &str) -> Result<Option<String>> {
    Ok(
        super::super::kv_get_string(conn, &generation_key(scope_id))?
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
    )
}

pub(super) fn write_generation_id(
    conn: &Connection,
    scope_id: &str,
    generation_id: &str,
) -> Result<()> {
    if generation_id.trim().is_empty() {
        return conn
            .execute(
                "DELETE FROM kv WHERE key = ?1",
                params![generation_key(scope_id)],
            )
            .map(|_| ())
            .map_err(Into::into);
    }
    super::super::kv_set_string(conn, &generation_key(scope_id), generation_id)
}

pub(super) fn read_last_applied_global_seq(conn: &Connection, scope_id: &str) -> Result<i64> {
    Ok(super::super::kv_get_i64(conn, &last_applied_key(scope_id))?.unwrap_or(0))
}

pub(super) fn write_last_applied_global_seq(
    conn: &Connection,
    scope_id: &str,
    seq: i64,
) -> Result<()> {
    super::super::kv_set_i64(conn, &last_applied_key(scope_id), seq.max(0))
}

pub(super) fn read_last_pushed_local_seq(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
) -> Result<i64> {
    Ok(super::super::kv_get_i64(conn, &last_pushed_key(scope_id, device_id))?.unwrap_or(0))
}

pub(super) fn write_last_pushed_local_seq(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
    seq: i64,
) -> Result<()> {
    super::super::kv_set_i64(conn, &last_pushed_key(scope_id, device_id), seq.max(0))
}

pub(super) fn clear_v2_state(conn: &Connection, scope_id: &str) -> Result<()> {
    conn.execute(
        "DELETE FROM kv WHERE key IN (?1, ?2)",
        params![generation_key(scope_id), last_applied_key(scope_id)],
    )?;
    conn.execute(
        "DELETE FROM kv WHERE key LIKE ?1",
        params![format!("managed_vault_v2.last_pushed_seq:{scope_id}:%")],
    )?;
    conn.execute(
        "DELETE FROM kv WHERE key LIKE ?1",
        params![format!(
            "managed_vault.pending_apply:{}:%",
            apply_scope_id(scope_id)
        )],
    )?;
    Ok(())
}

pub(super) fn rebuild_local_vault(conn: &Connection, scope_id: &str) -> Result<()> {
    crate::db::reset_vault_data_preserving_llm_profiles(conn)?;
    clear_v2_state(conn, scope_id)
}
