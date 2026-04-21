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
    super::with_immediate_transaction(conn, || {
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
    })
}

fn clear_legacy_scope_state(conn: &Connection, scope_id: &str) -> Result<()> {
    conn.execute(
        "DELETE FROM kv WHERE key LIKE ?1",
        params![format!("managed_vault.last_pulled_seq:{scope_id}:%")],
    )?;
    conn.execute(
        "DELETE FROM kv WHERE key = ?1",
        params![format!("managed_vault.last_pushed_seq:{scope_id}")],
    )?;
    conn.execute(
        "DELETE FROM kv WHERE key LIKE ?1",
        params![format!("managed_vault.last_pushed_seq:{scope_id}:%")],
    )?;
    conn.execute(
        "DELETE FROM kv WHERE key IN (?1, ?2, ?3)",
        params![
            super::media_state::attachment_backfill_key(scope_id),
            super::media_state::artifact_backfill_key(scope_id),
            super::media_state::v2_pull_media_clean_key(scope_id),
        ],
    )?;
    super::checkpoint::clear_checkpoint_state(conn, scope_id)?;
    super::state_machine::clear_state(conn, scope_id)?;
    crate::sync::blob_repair::clear_blob_repairs_for_scope(conn, scope_id)?;
    Ok(())
}

pub(super) fn rebuild_local_vault(conn: &Connection, scope_id: &str) -> Result<()> {
    crate::db::reset_vault_data_preserving_llm_profiles(conn)?;
    clear_v2_state(conn, scope_id)?;
    clear_legacy_scope_state(conn, scope_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clear_v2_state_clears_v2_keys_inside_existing_transaction() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let scope_id = "scope-a";

        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES (?1, ?2), (?3, ?4), (?5, ?6), (?7, ?8)"#,
            params![
                generation_key(scope_id),
                "generation-a",
                last_applied_key(scope_id),
                "7",
                last_pushed_key(scope_id, "device-a"),
                "5",
                format!(
                    "managed_vault.pending_apply:{}:{}",
                    apply_scope_id(scope_id),
                    "op-a"
                ),
                "1",
            ],
        )
        .expect("seed v2 sync state");

        conn.execute_batch("BEGIN IMMEDIATE;").expect("begin");
        clear_v2_state(&conn, scope_id).expect("clear v2 state");
        conn.execute_batch("COMMIT;").expect("commit");

        assert_eq!(
            super::super::super::kv_get_string(&conn, &generation_key(scope_id))
                .expect("read generation"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(&conn, &last_applied_key(scope_id))
                .expect("read last applied"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(&conn, &last_pushed_key(scope_id, "device-a"))
                .expect("read last pushed"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(
                &conn,
                &format!(
                    "managed_vault.pending_apply:{}:{}",
                    apply_scope_id(scope_id),
                    "op-a"
                ),
            )
            .expect("read pending apply"),
            None,
        );
    }

    #[test]
    fn rebuild_local_vault_clears_legacy_sync_state_for_scope() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let scope_id = "scope-a";

        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES (?1, ?2), (?3, ?4), (?5, ?6), (?7, ?8), (?9, ?10)"#,
            params![
                format!("managed_vault.last_pulled_seq:{scope_id}:remote-a"),
                "7",
                format!("managed_vault.last_pushed_seq:{scope_id}:device-a"),
                "5",
                format!("managed_vault.last_pushed_seq:{scope_id}"),
                "5",
                super::super::media_state::attachment_backfill_key(scope_id),
                "1",
                super::super::media_state::artifact_backfill_key(scope_id),
                "1",
            ],
        )
        .expect("seed kv state");
        super::super::checkpoint::store_checkpoint_success(
            &conn,
            scope_id,
            "generation-a",
            Some("checkpoint-a"),
            2,
            "ops:pull_bin_v2",
        )
        .expect("seed checkpoint");
        super::super::state_machine::transition(
            &conn,
            scope_id,
            super::super::state_machine::ManagedVaultSyncState::BlobBackfill,
        )
        .expect("seed state machine");
        crate::sync::blob_repair::enqueue_blob_repair(
            &conn,
            scope_id,
            crate::sync::blob_repair::BlobRepairKind::DeleteAttachmentRemote {
                sha256: "sha-a".to_string(),
            },
        )
        .expect("seed blob repair");

        rebuild_local_vault(&conn, scope_id).expect("rebuild");

        assert_eq!(
            super::super::super::kv_get_string(
                &conn,
                &format!("managed_vault.last_pulled_seq:{scope_id}:remote-a"),
            )
            .expect("read last pulled"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(
                &conn,
                &format!("managed_vault.last_pushed_seq:{scope_id}:device-a"),
            )
            .expect("read last pushed"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(
                &conn,
                &format!("managed_vault.last_pushed_seq:{scope_id}"),
            )
            .expect("read legacy pushed"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(
                &conn,
                &super::super::media_state::attachment_backfill_key(scope_id),
            )
            .expect("read attachment backfill"),
            None,
        );
        assert_eq!(
            super::super::super::kv_get_string(
                &conn,
                &super::super::media_state::artifact_backfill_key(scope_id),
            )
            .expect("read artifact backfill"),
            None,
        );
        assert_eq!(
            super::super::checkpoint::load_checkpoint_state(&conn, scope_id)
                .expect("load checkpoint")
                .checkpoint_token,
            None,
        );
        assert_eq!(
            super::super::state_machine::load_state(&conn, scope_id).expect("load state"),
            None,
        );
        assert_eq!(
            crate::sync::blob_repair::load_blob_repair_diagnostics(&conn, scope_id)
                .expect("load blob repair")
                .queued_count,
            0,
        );
    }
}
