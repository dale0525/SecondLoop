use std::collections::{BTreeMap, BTreeSet};

use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};

use crate::crypto::decrypt_bytes;

pub(super) fn load_pending_apply_op_ids(
    conn: &Connection,
    scope_id: &str,
) -> Result<BTreeSet<String>> {
    let prefix = format!("managed_vault.pending_apply:{scope_id}:");
    let pattern = format!("{prefix}%");

    let mut stmt = conn.prepare(r#"SELECT key FROM kv WHERE key LIKE ?1"#)?;
    let mut rows = stmt.query(params![pattern])?;

    let mut out: BTreeSet<String> = BTreeSet::new();
    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let Some(op_id) = key.strip_prefix(&prefix) else {
            continue;
        };
        if op_id.trim().is_empty() {
            continue;
        }
        out.insert(op_id.to_string());
    }
    Ok(out)
}

pub(super) fn pending_apply_key(scope_id: &str, op_id: &str) -> String {
    format!("managed_vault.pending_apply:{scope_id}:{op_id}")
}

pub(super) fn is_foreign_key_constraint_error(err: &anyhow::Error) -> bool {
    if let Some(e) = err.downcast_ref::<rusqlite::Error>() {
        return matches!(
            e,
            rusqlite::Error::SqliteFailure(e, _) if e.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_FOREIGNKEY
        );
    }
    let msg = err.to_string().to_ascii_lowercase();
    msg.contains("foreign key constraint failed")
}

fn try_apply_pending_op(conn: &Connection, db_key: &[u8; 32], op_id: &str) -> Result<Option<bool>> {
    let op_json_blob: Option<Vec<u8>> = conn
        .query_row(
            r#"SELECT op_json FROM oplog WHERE op_id = ?1"#,
            params![op_id],
            |row| row.get(0),
        )
        .optional()?;
    let Some(op_json_blob) = op_json_blob else {
        return Ok(None);
    };

    let plaintext = decrypt_bytes(
        db_key,
        &op_json_blob,
        format!("oplog.op_json:{op_id}").as_bytes(),
    )?;
    let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;

    match super::super::apply_op(conn, db_key, &op_json) {
        Ok(_) => Ok(Some(true)),
        Err(e) if is_foreign_key_constraint_error(&e) => Ok(Some(false)),
        Err(e) => Err(e),
    }
}

pub(super) fn apply_pending_ops_until_stable(
    conn: &Connection,
    db_key: &[u8; 32],
    scope_id: &str,
    pending: &mut BTreeSet<String>,
) -> Result<()> {
    const MAX_PASSES: usize = 10;
    for _ in 0..MAX_PASSES {
        let mut progressed = false;

        let op_ids: Vec<String> = pending.iter().cloned().collect();
        for op_id in op_ids {
            match try_apply_pending_op(conn, db_key, &op_id)? {
                None => {
                    let _ = conn.execute(
                        r#"DELETE FROM kv WHERE key = ?1"#,
                        params![pending_apply_key(scope_id, &op_id)],
                    )?;
                    pending.remove(&op_id);
                    progressed = true;
                }
                Some(true) => {
                    let _ = conn.execute(
                        r#"DELETE FROM kv WHERE key = ?1"#,
                        params![pending_apply_key(scope_id, &op_id)],
                    )?;
                    pending.remove(&op_id);
                    progressed = true;
                }
                Some(false) => {}
            }
        }

        if !progressed {
            break;
        }
    }
    Ok(())
}

pub(super) fn rewind_since_for_unresolved_pending_devices(
    conn: &Connection,
    pending: &BTreeSet<String>,
    next_since: &mut BTreeMap<String, i64>,
) -> Result<()> {
    if pending.is_empty() {
        return Ok(());
    }

    let mut pending_devices: BTreeSet<String> = BTreeSet::new();
    let mut stmt = conn.prepare_cached(r#"SELECT device_id FROM oplog WHERE op_id = ?1"#)?;
    for op_id in pending {
        let device_id: Option<String> = stmt
            .query_row(params![op_id], |row| row.get(0))
            .optional()?;
        if let Some(device_id) = device_id {
            pending_devices.insert(device_id);
        }
    }

    for device_id in pending_devices {
        next_since.insert(device_id, 0);
    }

    Ok(())
}

pub(super) fn update_since_map(
    conn: &Connection,
    scope_id: &str,
    next: &BTreeMap<String, i64>,
) -> Result<()> {
    super::with_immediate_transaction(conn, || {
        let prefix = format!("managed_vault.last_pulled_seq:{scope_id}:");
        let pattern = format!("{prefix}%");
        let _ = conn.execute(r#"DELETE FROM kv WHERE key LIKE ?1"#, params![pattern])?;
        for (device_id, last_seq) in next {
            let key = format!("managed_vault.last_pulled_seq:{scope_id}:{device_id}");
            super::super::kv_set_i64(conn, &key, *last_seq)?;
        }
        Ok(())
    })
}

pub(super) fn remote_ahead_cursor_devices(
    since: &BTreeMap<String, i64>,
    remote_max: &BTreeMap<String, i64>,
    local_device_id: &str,
) -> Vec<String> {
    remote_max
        .iter()
        .filter_map(|(device_id, max_seq)| {
            if device_id == local_device_id {
                return None;
            }
            let last_pulled_seq = since.get(device_id).copied().unwrap_or(0);
            if last_pulled_seq <= 0 || *max_seq <= last_pulled_seq {
                return None;
            }
            Some(device_id.clone())
        })
        .collect()
}

pub(super) fn cursor_repair_marker_key(scope_id: &str, device_id: &str) -> String {
    format!("managed_vault.cursor_repaired:{scope_id}:{device_id}")
}

fn cursor_repair_marker_key_v2(scope_id: &str, device_id: &str) -> String {
    format!("managed_vault.cursor_repair_attempted:{scope_id}:{device_id}")
}

pub(super) fn cursor_repair_marker_attempted(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
) -> Result<bool> {
    let legacy = cursor_repair_marker_key(scope_id, device_id);
    if super::super::kv_get_i64(conn, &legacy)?.unwrap_or(0) > 0 {
        return Ok(true);
    }

    let v2 = cursor_repair_marker_key_v2(scope_id, device_id);
    Ok(super::super::kv_get_i64(conn, &v2)?.unwrap_or(0) > 0)
}

pub(super) fn mark_cursor_repair_attempted(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
) -> Result<()> {
    let legacy = cursor_repair_marker_key(scope_id, device_id);
    super::super::kv_set_i64(conn, &legacy, 1)?;

    let v2 = cursor_repair_marker_key_v2(scope_id, device_id);
    super::super::kv_set_i64(conn, &v2, 1)?;
    Ok(())
}

pub(super) fn has_local_oplog_for_device(conn: &Connection, device_id: &str) -> Result<bool> {
    let exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM oplog WHERE device_id = ?1 LIMIT 1"#,
            params![device_id],
            |row| row.get(0),
        )
        .optional()?;
    Ok(exists.is_some())
}

#[cfg(test)]
mod cursor_repair_marker_tests {
    use super::*;
    use crate::sync::{kv_get_i64, kv_set_i64};

    #[test]
    fn cursor_repair_marker_compatibility_reads_legacy_key() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");

        kv_set_i64(&conn, "managed_vault.cursor_repaired:scope-a:device-a", 1)
            .expect("set legacy marker");

        assert!(
            cursor_repair_marker_attempted(&conn, "scope-a", "device-a").expect("marker attempted")
        );
    }

    #[test]
    fn mark_cursor_repair_attempted_writes_both_marker_keys() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");

        mark_cursor_repair_attempted(&conn, "scope-b", "device-b").expect("mark attempted");

        assert_eq!(
            kv_get_i64(&conn, "managed_vault.cursor_repaired:scope-b:device-b")
                .expect("get legacy"),
            Some(1)
        );
        assert_eq!(
            kv_get_i64(
                &conn,
                "managed_vault.cursor_repair_attempted:scope-b:device-b",
            )
            .expect("get v2"),
            Some(1)
        );
    }

    #[test]
    fn update_since_map_replaces_entries_inside_existing_transaction() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");

        kv_set_i64(&conn, "managed_vault.last_pulled_seq:scope-a:device-a", 7).expect("seed a");
        kv_set_i64(&conn, "managed_vault.last_pulled_seq:scope-a:device-b", 3).expect("seed b");

        conn.execute_batch("BEGIN IMMEDIATE;").expect("begin");
        let mut next = BTreeMap::new();
        next.insert("device-c".to_string(), 11);
        update_since_map(&conn, "scope-a", &next).expect("update since");
        conn.execute_batch("COMMIT;").expect("commit");

        assert_eq!(
            kv_get_i64(&conn, "managed_vault.last_pulled_seq:scope-a:device-a")
                .expect("load old a"),
            None
        );
        assert_eq!(
            kv_get_i64(&conn, "managed_vault.last_pulled_seq:scope-a:device-b")
                .expect("load old b"),
            None
        );
        assert_eq!(
            kv_get_i64(&conn, "managed_vault.last_pulled_seq:scope-a:device-c")
                .expect("load new c"),
            Some(11)
        );
    }
}
