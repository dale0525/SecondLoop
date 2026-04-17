use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

mod admin;
mod apply_batch;
mod artifacts;
mod attachments;
mod blob_repair;
mod checkpoint;
mod global_log_client;
mod global_log_protocol;
mod global_log_state;
mod pending_apply;
mod probe;
mod progress;
mod progress_metrics;
mod protocol;
mod pull_loop;
mod pull_recovery;
mod reseed;
mod runtime;
pub(crate) mod state_machine;
mod v2_client;

pub use admin::{clear_device, clear_vault};
pub use attachments::{download_attachment_bytes, upload_attachment_bytes};
use pending_apply::{
    apply_pending_ops_until_stable, has_local_oplog_for_device, is_foreign_key_constraint_error,
    load_pending_apply_op_ids, pending_apply_key, rewind_since_for_unresolved_pending_devices,
    update_since_map,
};

#[derive(Debug, Serialize)]
struct RegisterDeviceRequest<'a> {
    platform: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    device_id: Option<&'a str>,
}

#[derive(Debug, Deserialize)]
struct RegisterDeviceResponse {
    device_id: String,
}

#[derive(Debug, Serialize)]
struct PushRequest<'a> {
    device_id: &'a str,
    ops: Vec<PushOp>,
}

#[derive(Debug, Serialize)]
struct PushOp {
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
}

enum PendingAttachmentAction {
    Upload {
        mime_type: String,
        created_at_ms: i64,
    },
    Delete,
}

#[derive(Debug, Deserialize)]
struct PushResponse {
    max_seq: i64,
}

#[derive(Debug, Serialize)]
struct PullRequest<'a> {
    device_id: &'a str,
    since: BTreeMap<String, i64>,
    limit: i64,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
struct PullOp {
    device_id: String,
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
}

#[derive(Debug, Deserialize)]
struct PushErrorResponse {
    error: String,
    expected_next_seq: Option<i64>,
    conflict_kind: Option<String>,
    conflict_seq: Option<i64>,
    op_id: Option<String>,
    existing_device_id: Option<String>,
    existing_seq: Option<i64>,
}

const PULL_BIN_MAGIC_V1: &[u8; 5] = b"SLVB1";

fn load_since_map(conn: &Connection, scope_id: &str) -> Result<BTreeMap<String, i64>> {
    let prefix = format!("managed_vault.last_pulled_seq:{scope_id}:");
    let pattern = format!("{prefix}%");

    let mut stmt = conn.prepare(r#"SELECT key, value FROM kv WHERE key LIKE ?1"#)?;
    let mut rows = stmt.query(params![pattern])?;

    let mut out = BTreeMap::new();
    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let value: String = row.get(1)?;
        let Some(device_id) = key.strip_prefix(&prefix) else {
            continue;
        };
        if device_id.is_empty() {
            continue;
        }
        if let Ok(seq) = value.parse::<i64>() {
            out.insert(device_id.to_string(), seq);
        }
    }
    Ok(out)
}

fn write_local_device_id(conn: &Connection, device_id: &str) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![device_id],
    )?;
    Ok(())
}

fn try_recover_pull_forbidden_by_rotating_device_id(
    conn: &Connection,
    http: &runtime::Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    local_device_id: &str,
) -> Result<Option<String>> {
    if has_local_oplog_for_device(conn, local_device_id)? {
        return Ok(None);
    }

    let next_device_id = uuid::Uuid::new_v4().to_string();
    runtime::ensure_device_registered(http, base_url, vault_id, id_token, &next_device_id)?;
    write_local_device_id(conn, &next_device_id).map_err(|error| {
        anyhow!(
            "managed-vault device-id rotation registered a new device_id but failed to persist it locally: device_id={next_device_id}; error: {error}"
        )
    })?;
    Ok(Some(next_device_id))
}

fn should_fallback_to_json_pull(status_code: u16) -> bool {
    matches!(status_code, 404 | 408 | 429) || (500..600).contains(&status_code)
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    global_log_client::push_v2(conn, db_key, sync_key, base_url, vault_id, id_token, None)
}

pub fn push_ops_only(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    global_log_client::push_v2(conn, db_key, sync_key, base_url, vault_id, id_token, None)
}

pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    global_log_client::pull_v2(conn, db_key, sync_key, base_url, vault_id, id_token, None)
}

pub fn pull_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    global_log_client::pull_v2(
        conn,
        db_key,
        sync_key,
        base_url,
        vault_id,
        id_token,
        Some(progress),
    )
}

pub fn push_ops_only_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    global_log_client::push_v2(
        conn,
        db_key,
        sync_key,
        base_url,
        vault_id,
        id_token,
        Some(progress),
    )
}

fn push_internal(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    upload_attachment_bytes: bool,
) -> Result<u64> {
    let device_id = super::get_or_create_device_id(conn)?;
    let app_dir = super::app_dir_from_conn(conn)?;
    let app_dir_path = app_dir.as_path();

    let scope_id = runtime::scope_id(base_url, vault_id);
    let last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}:{device_id}");
    let legacy_last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}");
    if super::kv_get_i64(conn, &last_pushed_key)?.is_none() {
        let legacy = super::kv_get_i64(conn, &legacy_last_pushed_key)?.unwrap_or(0);
        super::kv_set_i64(conn, &last_pushed_key, legacy)?;
    }

    let last_pushed_seq = super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);
    let local_pending_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id.as_str(), last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;
    let has_remote_device_ops: bool = conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM oplog WHERE device_id != ?1 LIMIT 1)"#,
        params![device_id.as_str()],
        |row| row.get(0),
    )?;

    let mut registered_http = None;

    if upload_attachment_bytes
        && local_pending_ops == 0
        && last_pushed_seq == 0
        && has_remote_device_ops
    {
        let http = runtime::client()?;
        let _ = runtime::ensure_device_registered(&http, base_url, vault_id, id_token, &device_id)?;
        if probe::can_skip_fresh_device_full_push(
            conn, &http, base_url, vault_id, id_token, &device_id,
        )
        .unwrap_or(false)
        {
            return Ok(0);
        }
        registered_http = Some(http);
    }

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;
    crate::db::backfill_knowledge_memory_feedback_oplog_if_needed(conn, db_key)?;

    let local_pending_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id.as_str(), last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;
    if !upload_attachment_bytes && local_pending_ops == 0 {
        return Ok(0);
    }

    let http = match registered_http {
        Some(http) => http,
        None => {
            let http = runtime::client()?;
            let _ =
                runtime::ensure_device_registered(&http, base_url, vault_id, id_token, &device_id)?;
            http
        }
    };

    let upload_ctx = attachments::AttachmentUploadContext {
        conn,
        db_key,
        sync_key,
        http: &http,
        base_url,
        vault_id,
        id_token,
        app_dir: app_dir_path,
    };

    if upload_attachment_bytes {
        let attachment_backfill_key =
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}");
        if super::kv_get_i64(conn, &attachment_backfill_key)?.unwrap_or(0) == 0 {
            attachments::upload_all_local_attachment_bytes(&upload_ctx)?;
            super::kv_set_i64(conn, &attachment_backfill_key, 1)?;
        }

        let artifact_backfill_key =
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}");
        if super::kv_get_i64(conn, &artifact_backfill_key)?.unwrap_or(0) == 0 {
            artifacts::upload_all_local_embedding_artifact_blobs(&upload_ctx)?;
            super::kv_set_i64(conn, &artifact_backfill_key, 1)?;
        }
    }

    // Rare recovery path: if the remote has seqs this device doesn't agree with (e.g. device-id reuse),
    // we can rebase our local seqs forward based on the server's expected_next_seq and retry.
    const PUSH_LIMIT: i64 = 200;
    const MAX_REPAIR_ATTEMPTS: usize = 10;
    let mut repair_attempt = 0usize;
    let mut pushed_total = 0u64;
    loop {
        let last_pushed_seq = super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

        let mut stmt = conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC
               LIMIT ?3"#,
        )?;
        let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq, PUSH_LIMIT])?;

        let mut ops: Vec<PushOp> = Vec::new();
        let mut max_seq = last_pushed_seq;
        let mut attachment_actions: BTreeMap<String, PendingAttachmentAction> = BTreeMap::new();
        let mut artifact_blob_refs: BTreeSet<String> = BTreeSet::new();

        while let Some(row) = rows.next()? {
            let op_id: String = row.get(0)?;
            let seq: i64 = row.get(1)?;
            let op_json_blob: Vec<u8> = row.get(2)?;

            let plaintext = decrypt_bytes(
                db_key,
                &op_json_blob,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;

            if let Ok(op_json) = serde_json::from_slice::<serde_json::Value>(&plaintext) {
                if upload_attachment_bytes
                    && op_json["type"].as_str() == Some("attachment.upsert.v1")
                {
                    if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                        let mime_type = op_json["payload"]["mime_type"]
                            .as_str()
                            .unwrap_or("application/octet-stream");
                        let created_at_ms =
                            op_json["payload"]["created_at_ms"].as_i64().unwrap_or(0);
                        attachment_actions.insert(
                            sha256.to_string(),
                            PendingAttachmentAction::Upload {
                                mime_type: mime_type.to_string(),
                                created_at_ms,
                            },
                        );
                    }
                }

                if op_json["type"].as_str() == Some("attachment.delete.v1") {
                    if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                        attachment_actions
                            .insert(sha256.to_string(), PendingAttachmentAction::Delete);
                    }
                }

                if op_json["type"].as_str() == Some("embedding.artifact.upsert.v1") {
                    if let Some(blob_ref) = op_json["payload"]["blob_ref"].as_str() {
                        let blob_ref = blob_ref.trim();
                        if !blob_ref.is_empty() {
                            artifact_blob_refs.insert(blob_ref.to_string());
                        }
                    }
                }
            }

            let ciphertext = encrypt_bytes(
                sync_key,
                &plaintext,
                format!("sync.ops:{device_id}:{seq}").as_bytes(),
            )?;
            let ciphertext_b64 = B64_STD.encode(ciphertext);

            ops.push(PushOp {
                seq,
                op_id,
                ciphertext_b64,
            });
            max_seq = max_seq.max(seq);
        }

        if ops.is_empty() {
            let _ = blob_repair::process_pending_blob_repairs(&upload_ctx, 8)?;
            if pushed_total > 0 {
                maybe_run_managed_vault_retention(conn, &scope_id)?;
            }
            return Ok(pushed_total);
        }

        if attachment_actions
            .values()
            .any(|action| matches!(action, PendingAttachmentAction::Upload { .. }))
        {
            let _ =
                crate::db::ensure_all_video_manifest_derivations(conn, db_key, upload_ctx.app_dir)?;
        }

        for (sha256, action) in attachment_actions {
            match action {
                PendingAttachmentAction::Upload {
                    mime_type,
                    created_at_ms,
                } => {
                    let _ = attachments::upload_attachment_bytes_if_present(
                        &upload_ctx,
                        &sha256,
                        &mime_type,
                        created_at_ms,
                    )?;
                }
                PendingAttachmentAction::Delete => {
                    attachments::delete_remote_attachment_bytes(&upload_ctx, &sha256)?;
                }
            }
        }

        for blob_ref in artifact_blob_refs {
            let _ = artifacts::upload_embedding_artifact_blob_if_present(&upload_ctx, &blob_ref)?;
        }

        let endpoint = runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:push"))?;
        let resp = http
            .post(endpoint)
            .bearer_auth(id_token)
            .json(&PushRequest {
                device_id: device_id.as_str(),
                ops,
            })
            .send()?;

        let status = resp.status();
        let text = resp.text().unwrap_or_default();

        if status.is_success() {
            let parsed: PushResponse = serde_json::from_str(&text)?;
            if parsed.max_seq > last_pushed_seq {
                super::kv_set_i64(conn, &last_pushed_key, parsed.max_seq)?;
            }

            let pushed = max_seq.saturating_sub(last_pushed_seq) as u64;
            pushed_total += pushed;
            repair_attempt = 0;
            continue;
        }

        if status.as_u16() != 409 || repair_attempt >= MAX_REPAIR_ATTEMPTS {
            return Err(anyhow!("managed-vault push failed: HTTP {status} {text}"));
        }

        let parsed_err: PushErrorResponse = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => return Err(anyhow!("managed-vault push failed: HTTP {status} {text}")),
        };

        if parsed_err.error == "seq_gap" {
            if let Some(expected_next) = parsed_err.expected_next_seq {
                let next_last_pushed = expected_next.saturating_sub(1).max(0);
                super::kv_set_i64(conn, &last_pushed_key, next_last_pushed)?;
                // If the local oplog has holes, the server will keep asking for the missing seq.
                // We can compact the local seqs down to fill the gap and let the upload proceed.
                let min_local_pending_seq: Option<i64> = conn.query_row(
                    r#"SELECT MIN(seq) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
                    params![device_id.as_str(), next_last_pushed],
                    |row| row.get(0),
                )?;
                if let Some(min_seq) = min_local_pending_seq {
                    if min_seq > expected_next {
                        rebase_local_device_seqs(
                            conn,
                            db_key,
                            device_id.as_str(),
                            min_seq,
                            expected_next,
                        )?;
                    }
                }
                repair_attempt += 1;
                continue;
            }
        }

        if parsed_err.error == "conflict"
            && parsed_err.conflict_kind.as_deref() == Some("seq")
            && parsed_err.expected_next_seq.is_some()
            && parsed_err.conflict_seq.is_some()
        {
            let from_seq = parsed_err.conflict_seq.unwrap_or(0);
            let expected_next = parsed_err.expected_next_seq.unwrap_or(0);
            if from_seq > 0 && expected_next > from_seq {
                let next_last_pushed = from_seq - 1;
                super::kv_set_i64(
                    conn,
                    &last_pushed_key,
                    next_last_pushed.max(last_pushed_seq),
                )?;
                rebase_local_device_seqs(
                    conn,
                    db_key,
                    device_id.as_str(),
                    from_seq,
                    expected_next,
                )?;
                repair_attempt += 1;
                continue;
            }
        }

        if parsed_err.error == "conflict"
            && parsed_err.conflict_kind.as_deref() == Some("op_id")
            && parsed_err.expected_next_seq.is_some()
            && parsed_err.op_id.as_deref().is_some()
        {
            let _ = (&parsed_err.existing_device_id, &parsed_err.existing_seq);
            let conflict_op_id = parsed_err.op_id.clone().unwrap_or_default();
            if !conflict_op_id.trim().is_empty() {
                let local_conflict_seq: Option<i64> = conn
                    .query_row(
                        r#"SELECT seq FROM oplog WHERE op_id = ?1 AND device_id = ?2"#,
                        params![conflict_op_id.as_str(), device_id.as_str()],
                        |row| row.get(0),
                    )
                    .optional()?;

                if let Some(conflict_seq) = local_conflict_seq {
                    let _ = conn.execute(
                        r#"DELETE FROM oplog WHERE op_id = ?1 AND device_id = ?2"#,
                        params![conflict_op_id.as_str(), device_id.as_str()],
                    )?;

                    if conflict_seq > 0 {
                        rebase_local_device_seqs(
                            conn,
                            db_key,
                            device_id.as_str(),
                            conflict_seq + 1,
                            conflict_seq,
                        )?;
                    }

                    repair_attempt += 1;
                    continue;
                }
            }
        }

        return Err(anyhow!("managed-vault push failed: HTTP {status} {text}"));
    }
}

fn maybe_run_managed_vault_retention(conn: &Connection, scope_id: &str) -> Result<()> {
    let _ = crate::db::run_oplog_retention_maintenance(
        conn,
        crate::db::OplogRetentionBackend::ManagedVault,
        scope_id,
    )?;
    Ok(())
}

fn rebase_local_device_seqs(
    conn: &Connection,
    db_key: &[u8; 32],
    device_id: &str,
    from_seq: i64,
    new_from_seq: i64,
) -> Result<()> {
    if from_seq <= 0 {
        return Err(anyhow!("invalid from_seq"));
    }
    if new_from_seq <= 0 {
        return Err(anyhow!("invalid new_from_seq"));
    }
    let delta = new_from_seq - from_seq;
    if delta == 0 {
        return Ok(());
    }

    with_immediate_transaction(conn, || {
        let _ = conn.execute(
            r#"UPDATE messages
               SET updated_by_seq = updated_by_seq + ?1
               WHERE updated_by_device_id = ?2
                 AND updated_by_seq >= ?3"#,
            params![delta, device_id, from_seq],
        )?;
        let _ = conn.execute(
            r#"UPDATE attachment_deletions
               SET deleted_by_seq = deleted_by_seq + ?1
               WHERE deleted_by_device_id = ?2
                 AND deleted_by_seq >= ?3"#,
            params![delta, device_id, from_seq],
        )?;

        let mut stmt = conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq >= ?2
               ORDER BY seq ASC"#,
        )?;
        let mut rows = stmt.query(params![device_id, from_seq])?;

        let mut ops_to_update: Vec<(String, i64, Vec<u8>)> = Vec::new();
        while let Some(row) = rows.next()? {
            ops_to_update.push((row.get(0)?, row.get(1)?, row.get(2)?));
        }
        drop(rows);
        drop(stmt);

        // Must update in descending seq order to avoid transient unique constraint
        // violations on (device_id, seq). For negative shifts, update in ascending order.
        if delta > 0 {
            ops_to_update.sort_by(|a, b| b.1.cmp(&a.1));
        } else {
            ops_to_update.sort_by(|a, b| a.1.cmp(&b.1));
        }

        let mut update = conn.prepare_cached(
            r#"UPDATE oplog
               SET seq = ?1, op_json = ?2
               WHERE op_id = ?3"#,
        )?;

        for (op_id, old_seq, op_json_blob) in ops_to_update {
            let new_seq = old_seq + delta;

            let plaintext = decrypt_bytes(
                db_key,
                &op_json_blob,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;
            let mut op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
            op_json["seq"] = serde_json::Value::from(new_seq);
            let updated_plaintext = serde_json::to_vec(&op_json)?;
            let updated_blob = encrypt_bytes(
                db_key,
                &updated_plaintext,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;
            update.execute(params![new_seq, updated_blob, op_id])?;
        }

        Ok(())
    })
}

fn with_immediate_transaction<T>(conn: &Connection, f: impl FnOnce() -> Result<T>) -> Result<T> {
    if !conn.is_autocommit() {
        return f();
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    match f() {
        Ok(v) => {
            conn.execute_batch("COMMIT;")?;
            Ok(v)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}
