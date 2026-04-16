use std::collections::BTreeMap;

use anyhow::Result;
use rusqlite::Connection;

pub(super) fn clear_protocol_checkpoint_state(conn: &Connection, scope_id: &str) -> Result<()> {
    super::checkpoint::clear_checkpoint_state(conn, scope_id)
}

pub(super) fn apply_history_lower_bound_reset(
    conn: &Connection,
    scope_id: &str,
    history_lower_bound: Option<&BTreeMap<String, i64>>,
    needs_reseed: Option<&BTreeMap<String, bool>>,
) -> Result<BTreeMap<String, i64>> {
    let mut next_since = BTreeMap::new();

    if let Some(bounds) = history_lower_bound {
        for (device_id, min_seq) in bounds {
            next_since.insert(device_id.clone(), (*min_seq).max(0).saturating_sub(1));
        }
    }

    if let Some(reseed_devices) = needs_reseed {
        for device_id in reseed_devices.keys() {
            next_since.entry(device_id.clone()).or_insert(0);
        }
    }

    clear_protocol_checkpoint_state(conn, scope_id)?;
    super::pending_apply::update_since_map(conn, scope_id, &next_since)?;
    Ok(next_since)
}

#[cfg(test)]
mod tests {
    use super::*;

    use rusqlite::OptionalExtension;

    #[test]
    fn apply_history_lower_bound_reset_clears_persisted_since_entries() {
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

        apply_history_lower_bound_reset(&conn, scope_id, None, None)
            .expect("apply history lower bound reset");

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

    #[test]
    fn apply_history_lower_bound_reset_stores_lower_bound_minus_one() {
        let temp = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(temp.path()).expect("open db");
        let scope_id = "managed-vault-scope";
        let mut history_lower_bound = BTreeMap::new();
        history_lower_bound.insert("remote-a".to_string(), 5);
        let mut needs_reseed = BTreeMap::new();
        needs_reseed.insert("remote-a".to_string(), true);
        needs_reseed.insert("remote-b".to_string(), true);

        let next_since = apply_history_lower_bound_reset(
            &conn,
            scope_id,
            Some(&history_lower_bound),
            Some(&needs_reseed),
        )
        .expect("apply history lower bound reset");

        assert_eq!(next_since.get("remote-a").copied(), Some(4));
        assert_eq!(next_since.get("remote-b").copied(), Some(0));
    }
}
