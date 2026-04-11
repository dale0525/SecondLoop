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

#[cfg(test)]
mod tests {
    use super::*;

    use rusqlite::OptionalExtension;

    #[test]
    fn restart_incremental_pull_clears_persisted_since_entries() {
        let temp = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(temp.path()).expect("open db");
        let scope_id = "managed-vault-scope";

        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES (?1, ?2)"#,
            rusqlite::params![
                format!("managed_vault.last_pulled_seq:{scope_id}:remote-a"),
                "42"
            ],
        )
        .expect("seed since");
        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES (?1, ?2)"#,
            rusqlite::params![
                format!("managed_vault.checkpoint_token:{scope_id}"),
                "checkpoint-stale"
            ],
        )
        .expect("seed checkpoint");

        restart_incremental_pull(&conn, scope_id).expect("restart incremental pull");

        let persisted_since: Option<String> = conn
            .query_row(
                r#"SELECT value FROM kv WHERE key = ?1"#,
                rusqlite::params![format!("managed_vault.last_pulled_seq:{scope_id}:remote-a")],
                |row| row.get(0),
            )
            .optional()
            .expect("query since");
        assert_eq!(persisted_since, None);

        let checkpoint: Option<String> = conn
            .query_row(
                r#"SELECT value FROM kv WHERE key = ?1"#,
                rusqlite::params![format!("managed_vault.checkpoint_token:{scope_id}")],
                |row| row.get(0),
            )
            .optional()
            .expect("query checkpoint");
        assert_eq!(checkpoint, None);
    }
}
