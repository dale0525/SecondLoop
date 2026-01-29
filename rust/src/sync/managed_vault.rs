use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::sync::OnceLock;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::{STANDARD as B64_STD, URL_SAFE_NO_PAD as B64_URL};
use base64::Engine as _;
use reqwest::blocking::Client;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

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

#[derive(Debug, Deserialize)]
struct PullResponse {
    ops: Vec<PullOp>,
    next: BTreeMap<String, i64>,
}

#[derive(Debug, Deserialize)]
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

#[derive(Debug)]
struct PullOpBin {
    device_id: String,
    seq: i64,
    op_id: String,
    ciphertext: Vec<u8>,
}

#[derive(Debug, Serialize)]
struct ClearDeviceRequest<'a> {
    device_id: &'a str,
}

struct AttachmentUploadContext<'a> {
    conn: &'a Connection,
    db_key: &'a [u8; 32],
    sync_key: &'a [u8; 32],
    http: &'a Client,
    base_url: &'a str,
    vault_id: &'a str,
    id_token: &'a str,
    app_dir: &'a Path,
}

fn scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    B64_URL.encode(raw.as_bytes())
}

fn client() -> Result<Client> {
    static CLIENT: OnceLock<Client> = OnceLock::new();
    Ok(CLIENT.get_or_init(Client::new).clone())
}

fn url(base_url: &str, path: &str) -> Result<String> {
    let base = base_url.trim_end_matches('/');
    if base.is_empty() {
        return Err(anyhow!("missing_base_url"));
    }
    Ok(format!("{base}{path}"))
}

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

fn update_since_map(conn: &Connection, scope_id: &str, next: &BTreeMap<String, i64>) -> Result<()> {
    for (device_id, last_seq) in next {
        let key = format!("managed_vault.last_pulled_seq:{scope_id}:{device_id}");
        super::kv_set_i64(conn, &key, *last_seq)?;
    }
    Ok(())
}

fn decode_pull_bin_response(bytes: &[u8]) -> Result<Vec<PullOpBin>> {
    if bytes.len() < PULL_BIN_MAGIC_V1.len() + 4 {
        return Err(anyhow!("invalid pull_bin response: too short"));
    }
    if &bytes[..PULL_BIN_MAGIC_V1.len()] != PULL_BIN_MAGIC_V1 {
        return Err(anyhow!("invalid pull_bin response: bad magic"));
    }

    let mut cursor = PULL_BIN_MAGIC_V1.len();
    let count = u32::from_le_bytes(
        bytes[cursor..cursor + 4]
            .try_into()
            .map_err(|_| anyhow!("invalid pull_bin response: count"))?,
    ) as usize;
    cursor += 4;

    let mut out: Vec<PullOpBin> = Vec::with_capacity(count);
    for _ in 0..count {
        if cursor + 2 > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin response: truncated device_id_len"
            ));
        }
        let device_len = u16::from_le_bytes(
            bytes[cursor..cursor + 2]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: device_id_len"))?,
        ) as usize;
        cursor += 2;

        if cursor + device_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated device_id"));
        }
        let device_id = String::from_utf8(bytes[cursor..cursor + device_len].to_vec())
            .map_err(|_| anyhow!("invalid pull_bin response: device_id not utf-8"))?;
        cursor += device_len;

        if cursor + 8 > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated seq"));
        }
        let seq = i64::from_le_bytes(
            bytes[cursor..cursor + 8]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: seq"))?,
        );
        cursor += 8;

        if cursor + 2 > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated op_id_len"));
        }
        let op_id_len = u16::from_le_bytes(
            bytes[cursor..cursor + 2]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: op_id_len"))?,
        ) as usize;
        cursor += 2;

        if cursor + op_id_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated op_id"));
        }
        let op_id = String::from_utf8(bytes[cursor..cursor + op_id_len].to_vec())
            .map_err(|_| anyhow!("invalid pull_bin response: op_id not utf-8"))?;
        cursor += op_id_len;

        if cursor + 4 > bytes.len() {
            return Err(anyhow!(
                "invalid pull_bin response: truncated ciphertext_len"
            ));
        }
        let cipher_len = u32::from_le_bytes(
            bytes[cursor..cursor + 4]
                .try_into()
                .map_err(|_| anyhow!("invalid pull_bin response: ciphertext_len"))?,
        ) as usize;
        cursor += 4;

        if cursor + cipher_len > bytes.len() {
            return Err(anyhow!("invalid pull_bin response: truncated ciphertext"));
        }
        let ciphertext = bytes[cursor..cursor + cipher_len].to_vec();
        cursor += cipher_len;

        out.push(PullOpBin {
            device_id,
            seq,
            op_id,
            ciphertext,
        });
    }

    Ok(out)
}

fn ensure_device_registered(
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<String> {
    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/devices"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&RegisterDeviceRequest {
            platform: "unknown",
            device_id: Some(device_id),
        })
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault register-device failed: HTTP {status} {text}"
        ));
    }

    let parsed: RegisterDeviceResponse = serde_json::from_str(&text)?;
    Ok(parsed.device_id)
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    push_internal(conn, db_key, sync_key, base_url, vault_id, id_token, true)
}

pub fn push_ops_only(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    push_internal(conn, db_key, sync_key, base_url, vault_id, id_token, false)
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
    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;

    let http = client()?;
    let device_id = super::get_or_create_device_id(conn)?;
    let app_dir = super::app_dir_from_conn(conn)?;
    let app_dir_path = app_dir.as_path();
    let _ = ensure_device_registered(&http, base_url, vault_id, id_token, &device_id)?;

    let scope_id = scope_id(base_url, vault_id);
    let last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}:{device_id}");
    let legacy_last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}");
    if super::kv_get_i64(conn, &last_pushed_key)?.is_none() {
        let legacy = super::kv_get_i64(conn, &legacy_last_pushed_key)?.unwrap_or(0);
        super::kv_set_i64(conn, &last_pushed_key, legacy)?;
    }

    let upload_ctx = AttachmentUploadContext {
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
            upload_all_local_attachment_bytes(&upload_ctx)?;
            super::kv_set_i64(conn, &attachment_backfill_key, 1)?;
        }
    }

    // Rare recovery path: if the remote has seqs this device doesn't agree with (e.g. device-id reuse),
    // we can rebase our local seqs forward based on the server's expected_next_seq and retry.
    const MAX_REPAIR_ATTEMPTS: usize = 10;
    let mut repair_attempt = 0usize;
    loop {
        let last_pushed_seq = super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

        let mut stmt = conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC"#,
        )?;
        let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq])?;

        let mut ops: Vec<PushOp> = Vec::new();
        let mut max_seq = last_pushed_seq;
        let mut uploaded_attachments: BTreeSet<String> = BTreeSet::new();
        let mut deleted_attachments: BTreeSet<String> = BTreeSet::new();

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
                        if uploaded_attachments.insert(sha256.to_string()) {
                            let mime_type = op_json["payload"]["mime_type"]
                                .as_str()
                                .unwrap_or("application/octet-stream");
                            let created_at_ms =
                                op_json["payload"]["created_at_ms"].as_i64().unwrap_or(0);
                            let _ = upload_attachment_bytes_if_present(
                                &upload_ctx,
                                sha256,
                                mime_type,
                                created_at_ms,
                            )?;
                        }
                    }
                }

                if op_json["type"].as_str() == Some("attachment.delete.v1") {
                    if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                        if deleted_attachments.insert(sha256.to_string()) {
                            delete_remote_attachment_bytes(&upload_ctx, sha256)?;
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
            return Ok(0);
        }

        let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/ops:push"))?;
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

            let pushed = max_seq.saturating_sub(last_pushed_seq);
            return Ok(pushed as u64);
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

fn delete_remote_attachment_bytes(ctx: &AttachmentUploadContext<'_>, sha256: &str) -> Result<()> {
    let endpoint = url(
        ctx.base_url,
        &format!("/v1/vaults/{}/attachments/{sha256}", ctx.vault_id),
    )?;
    let resp = ctx.http.delete(endpoint).bearer_auth(ctx.id_token).send()?;

    let status = resp.status();
    if status.as_u16() == 404 {
        return Ok(());
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault delete attachment failed: HTTP {status} {text}"
        ));
    }
    Ok(())
}

pub fn upload_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    sha256: &str,
) -> Result<bool> {
    let http = client()?;
    let app_dir = super::app_dir_from_conn(conn)?;

    let (mime_type, created_at_ms): (String, i64) = conn.query_row(
        r#"SELECT mime_type, created_at FROM attachments WHERE sha256 = ?1"#,
        params![sha256],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    let upload_ctx = AttachmentUploadContext {
        conn,
        db_key,
        sync_key,
        http: &http,
        base_url,
        vault_id,
        id_token,
        app_dir: app_dir.as_path(),
    };

    upload_attachment_bytes_if_present(&upload_ctx, sha256, &mime_type, created_at_ms)
}

pub fn download_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    sha256: &str,
) -> Result<()> {
    let http = client()?;
    let app_dir = super::app_dir_from_conn(conn)?;

    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment not found"))?;

    let endpoint = url(
        base_url,
        &format!("/v1/vaults/{vault_id}/attachments/{sha256}"),
    )?;
    let resp = http.get(endpoint).bearer_auth(id_token).send()?;

    let status = resp.status();
    if status.as_u16() == 404 {
        return Err(anyhow!("managed-vault attachment not found"));
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault get attachment failed: HTTP {status} {text}"
        ));
    }

    let ciphertext = resp.bytes()?.to_vec();
    let aad = format!("sync.attachment.bytes:{sha256}");
    let plaintext = decrypt_bytes(sync_key, &ciphertext, aad.as_bytes())?;

    if super::sha256_hex(&plaintext) != sha256 {
        return Err(anyhow!("attachment sha256 mismatch after download"));
    }

    let local_path = app_dir.join(&stored_path);
    if let Some(parent) = local_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let local_aad = format!("attachment.bytes:{sha256}");
    let local_cipher = encrypt_bytes(db_key, &plaintext, local_aad.as_bytes())?;
    fs::write(local_path, local_cipher)?;
    Ok(())
}

fn upload_all_local_attachment_bytes(ctx: &AttachmentUploadContext<'_>) -> Result<u64> {
    let mut stmt = ctx.conn.prepare(
        r#"SELECT sha256, mime_type, created_at FROM attachments ORDER BY created_at ASC, sha256 ASC"#,
    )?;
    let mut rows = stmt.query([])?;

    let mut uploaded = 0u64;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        let mime_type: String = row.get(1)?;
        let created_at_ms: i64 = row.get(2)?;
        match upload_attachment_bytes_if_present(ctx, &sha256, &mime_type, created_at_ms) {
            Ok(true) => uploaded += 1,
            Ok(false) => {}
            Err(e) => return Err(e),
        }
    }
    Ok(uploaded)
}

fn upload_attachment_bytes_if_present(
    ctx: &AttachmentUploadContext<'_>,
    sha256: &str,
    mime_type: &str,
    created_at_ms: i64,
) -> Result<bool> {
    let plaintext =
        match crate::db::read_attachment_bytes(ctx.conn, ctx.db_key, ctx.app_dir, sha256) {
            Ok(bytes) => bytes,
            Err(e)
                if e.downcast_ref::<std::io::Error>()
                    .is_some_and(|io| io.kind() == std::io::ErrorKind::NotFound) =>
            {
                return Ok(false);
            }
            Err(e) => return Err(e),
        };

    let aad = format!("sync.attachment.bytes:{sha256}");
    let ciphertext = encrypt_bytes(ctx.sync_key, &plaintext, aad.as_bytes())?;

    let endpoint = url(
        ctx.base_url,
        &format!("/v1/vaults/{}/attachments/{sha256}", ctx.vault_id),
    )?;
    let resp = ctx
        .http
        .put(endpoint)
        .bearer_auth(ctx.id_token)
        .header("content-type", "application/octet-stream")
        .header("x-media-byte-len", ciphertext.len().to_string())
        .header("x-media-mime", mime_type)
        .header("x-media-created-at-ms", created_at_ms.to_string())
        .body(ciphertext)
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault put attachment failed: HTTP {status} {text}"
        ));
    }

    Ok(true)
}

fn with_immediate_transaction<T>(conn: &Connection, f: impl FnOnce() -> Result<T>) -> Result<T> {
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

pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    const PULL_LIMIT: i64 = 500;

    let http = client()?;
    let local_device_id = super::get_or_create_device_id(conn)?;
    let _ = ensure_device_registered(&http, base_url, vault_id, id_token, &local_device_id)?;

    let scope_id = scope_id(base_url, vault_id);
    let mut since = load_since_map(conn, &scope_id)?;

    let endpoint_json = url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let endpoint_bin = url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_bin"))?;
    let mut applied: u64 = 0;
    let mut pull_bin_supported: Option<bool> = None;
    loop {
        let request = PullRequest {
            device_id: local_device_id.as_str(),
            since: since.clone(),
            limit: PULL_LIMIT,
        };

        if pull_bin_supported != Some(false) {
            let resp = http
                .post(&endpoint_bin)
                .bearer_auth(id_token)
                .json(&request)
                .send()?;

            let status = resp.status();
            if status.as_u16() == 404 {
                pull_bin_supported = Some(false);
            } else {
                if !status.is_success() {
                    let text = resp.text().unwrap_or_default();
                    return Err(anyhow!(
                        "managed-vault pull_bin failed: HTTP {status} {text}"
                    ));
                }

                pull_bin_supported = Some(true);
                let body = resp.bytes()?;
                let ops = decode_pull_bin_response(body.as_ref())?;

                let mut next_since = since.clone();
                for op in &ops {
                    next_since
                        .entry(op.device_id.clone())
                        .and_modify(|v| *v = (*v).max(op.seq))
                        .or_insert(op.seq);
                }

                if next_since == since && !ops.is_empty() {
                    return Err(anyhow!("managed-vault pull made no progress"));
                }

                let mut batch_applied = 0u64;
                with_immediate_transaction(conn, || {
                    for op in &ops {
                        let plaintext = decrypt_bytes(
                            sync_key,
                            &op.ciphertext,
                            format!("sync.ops:{}:{}", op.device_id, op.seq).as_bytes(),
                        )?;
                        let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
                        let op_id = op_json["op_id"]
                            .as_str()
                            .ok_or_else(|| anyhow!("sync op missing op_id"))?;
                        if op_id != op.op_id.as_str() {
                            return Err(anyhow!(
                                "managed vault pull op_id mismatch: envelope={} plaintext={}",
                                op.op_id,
                                op_id
                            ));
                        }

                        let inserted =
                            super::insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
                        if !inserted {
                            continue;
                        }

                        super::apply_op(conn, db_key, &op_json)?;
                        batch_applied += 1;
                    }

                    if next_since != since {
                        update_since_map(conn, &scope_id, &next_since)?;
                    }

                    Ok(())
                })?;
                applied += batch_applied;
                since = next_since;

                if ops.len() < (PULL_LIMIT as usize) {
                    break;
                }
                continue;
            }
        }

        let resp = http
            .post(&endpoint_json)
            .bearer_auth(id_token)
            .json(&request)
            .send()?;

        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().unwrap_or_default();
            return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
        }

        let body = resp.bytes()?;
        let parsed: PullResponse = serde_json::from_slice(body.as_ref())?;

        let mut next_since = since.clone();
        for (device_id, last_seq) in &parsed.next {
            next_since.insert(device_id.to_string(), *last_seq);
        }

        if next_since == since && !parsed.ops.is_empty() {
            return Err(anyhow!("managed-vault pull made no progress"));
        }

        let mut batch_applied = 0u64;
        with_immediate_transaction(conn, || {
            for op in &parsed.ops {
                let ciphertext = B64_STD
                    .decode(op.ciphertext_b64.as_bytes())
                    .map_err(|e| anyhow!("invalid ciphertext_b64: {e}"))?;
                let plaintext = decrypt_bytes(
                    sync_key,
                    &ciphertext,
                    format!("sync.ops:{}:{}", op.device_id, op.seq).as_bytes(),
                )?;
                let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
                let op_id = op_json["op_id"]
                    .as_str()
                    .ok_or_else(|| anyhow!("sync op missing op_id"))?;
                if op_id != op.op_id.as_str() {
                    return Err(anyhow!(
                        "managed vault pull op_id mismatch: envelope={} plaintext={}",
                        op.op_id,
                        op_id
                    ));
                }

                let inserted = super::insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
                if !inserted {
                    continue;
                }

                super::apply_op(conn, db_key, &op_json)?;
                batch_applied += 1;
            }

            if next_since != since {
                update_since_map(conn, &scope_id, &next_since)?;
            }

            Ok(())
        })?;
        applied += batch_applied;
        since = next_since;

        if parsed.ops.len() < (PULL_LIMIT as usize) {
            break;
        }
    }

    Ok(applied)
}

pub fn clear_vault(base_url: &str, vault_id: &str, id_token: &str) -> Result<()> {
    let http = client()?;
    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/ops:clear"))?;
    let resp = http.post(endpoint).bearer_auth(id_token).send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!("managed-vault clear failed: HTTP {status} {text}"));
    }
    Ok(())
}

pub fn clear_device(base_url: &str, vault_id: &str, id_token: &str, device_id: &str) -> Result<()> {
    let http = client()?;
    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/ops:clear_device"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&ClearDeviceRequest { device_id })
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault clear-device failed: HTTP {status} {text}"
        ));
    }
    Ok(())
}
