use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Deserialize;

use crate::crypto::{decrypt_bytes, encrypt_bytes};

#[derive(Debug, Deserialize)]
struct PullResponseWithMax {
    ops: Vec<super::PullOp>,
    next: BTreeMap<String, i64>,
    #[serde(default)]
    max: BTreeMap<String, i64>,
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
    const PULL_LIMIT: i64 = 500;

    let http = super::client()?;
    let local_device_id = super::super::get_or_create_device_id(conn)?;
    let _ = super::ensure_device_registered(&http, base_url, vault_id, id_token, &local_device_id)?;

    let scope_id = super::scope_id(base_url, vault_id);
    let mut since = super::load_since_map(conn, &scope_id)?;

    let endpoint_json = super::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let mut applied: u64 = 0;

    let mut total_ops: Option<u64> = None;
    let mut done_ops = 0u64;

    loop {
        let request = super::PullRequest {
            device_id: local_device_id.as_str(),
            since: since.clone(),
            limit: PULL_LIMIT,
        };

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
        let parsed: PullResponseWithMax = serde_json::from_slice(body.as_ref())?;

        if total_ops.is_none() {
            let mut total = 0u64;
            for (device_id, max_seq) in &parsed.max {
                let last_pulled_seq = since.get(device_id).copied().unwrap_or(0);
                if *max_seq > last_pulled_seq {
                    total += (*max_seq - last_pulled_seq) as u64;
                }
            }
            total_ops = Some(total);
            progress(0, total);
        }

        let mut next_since = since.clone();
        for (device_id, last_seq) in &parsed.next {
            next_since.insert(device_id.to_string(), *last_seq);
        }

        if next_since == since && !parsed.ops.is_empty() {
            return Err(anyhow!("managed-vault pull made no progress"));
        }

        let mut batch_applied = 0u64;
        super::with_immediate_transaction(conn, || {
            let mut pending = super::load_pending_apply_op_ids(conn, &scope_id)?;
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

                let inserted =
                    super::super::insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
                if !inserted {
                    continue;
                }

                match super::super::apply_op(conn, db_key, &op_json) {
                    Ok(_) => {
                        batch_applied += 1;
                    }
                    Err(e) if super::is_foreign_key_constraint_error(&e) => {
                        pending.insert(op_id.to_string());
                        super::super::kv_set_i64(
                            conn,
                            &super::pending_apply_key(&scope_id, op_id),
                            1,
                        )?;
                    }
                    Err(e) => return Err(e),
                }
            }

            super::apply_pending_ops_until_stable(conn, db_key, &scope_id, &mut pending)?;

            if next_since != since {
                super::update_since_map(conn, &scope_id, &next_since)?;
            }

            Ok(())
        })?;
        applied += batch_applied;

        if let Some(total) = total_ops {
            let mut delta = 0u64;
            for (device_id, next_seq) in &next_since {
                let prev = since.get(device_id).copied().unwrap_or(0);
                if *next_seq > prev {
                    delta += (*next_seq - prev) as u64;
                }
            }
            done_ops = (done_ops + delta).min(total);
            progress(done_ops, total);
        }

        since = next_since;

        if parsed.ops.len() < (PULL_LIMIT as usize) {
            break;
        }
    }

    if let Some(total) = total_ops {
        progress(done_ops, total);
    }

    Ok(applied)
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
    const PUSH_LIMIT: i64 = 200;
    const MAX_REPAIR_ATTEMPTS: usize = 10;

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;

    let http = super::client()?;
    let device_id = super::super::get_or_create_device_id(conn)?;
    let _ = super::ensure_device_registered(&http, base_url, vault_id, id_token, &device_id)?;

    let scope_id = super::scope_id(base_url, vault_id);
    let last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}:{device_id}");
    let legacy_last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}");
    if super::super::kv_get_i64(conn, &last_pushed_key)?.is_none() {
        let legacy = super::super::kv_get_i64(conn, &legacy_last_pushed_key)?.unwrap_or(0);
        super::super::kv_set_i64(conn, &last_pushed_key, legacy)?;
    }

    let initial_last_pushed_seq = super::super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);
    let total_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id.as_str(), initial_last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;

    let mut done_ops = 0u64;
    progress(0, total_ops);

    if total_ops == 0 {
        return Ok(0);
    }

    let endpoint = super::url(base_url, &format!("/v1/vaults/{vault_id}/ops:push"))?;
    let mut repair_attempt = 0usize;
    let mut pushed_total = 0u64;

    loop {
        let last_pushed_seq = super::super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

        let mut stmt = conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC
               LIMIT ?3"#,
        )?;
        let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq, PUSH_LIMIT])?;

        let mut ops: Vec<super::PushOp> = Vec::new();
        let mut max_seq = last_pushed_seq;
        while let Some(row) = rows.next()? {
            let op_id: String = row.get(0)?;
            let seq: i64 = row.get(1)?;
            let op_json_blob: Vec<u8> = row.get(2)?;

            let plaintext = decrypt_bytes(
                db_key,
                &op_json_blob,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;

            let ciphertext = encrypt_bytes(
                sync_key,
                &plaintext,
                format!("sync.ops:{device_id}:{seq}").as_bytes(),
            )?;
            let ciphertext_b64 = B64_STD.encode(ciphertext);
            ops.push(super::PushOp {
                seq,
                op_id,
                ciphertext_b64,
            });
            max_seq = max_seq.max(seq);
        }

        if ops.is_empty() {
            break;
        }

        let resp = http
            .post(&endpoint)
            .bearer_auth(id_token)
            .json(&super::PushRequest {
                device_id: device_id.as_str(),
                ops,
            })
            .send()?;

        let status = resp.status();
        let text = resp.text().unwrap_or_default();

        if status.is_success() {
            let parsed: super::PushResponse = serde_json::from_str(&text)?;
            if parsed.max_seq > last_pushed_seq {
                super::super::kv_set_i64(conn, &last_pushed_key, parsed.max_seq)?;
            }

            let pushed = max_seq.saturating_sub(last_pushed_seq) as u64;
            pushed_total += pushed;
            done_ops = (done_ops + pushed).min(total_ops);
            progress(done_ops, total_ops);

            repair_attempt = 0;
            continue;
        }

        if status.as_u16() != 409 || repair_attempt >= MAX_REPAIR_ATTEMPTS {
            return Err(anyhow!("managed-vault push failed: HTTP {status} {text}"));
        }

        let parsed_err: super::PushErrorResponse = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => return Err(anyhow!("managed-vault push failed: HTTP {status} {text}")),
        };

        if parsed_err.error == "seq_gap" {
            if let Some(expected_next) = parsed_err.expected_next_seq {
                let next_last_pushed = expected_next.saturating_sub(1).max(0);
                super::super::kv_set_i64(conn, &last_pushed_key, next_last_pushed)?;
                let min_local_pending_seq: Option<i64> = conn.query_row(
                    r#"SELECT MIN(seq) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
                    params![device_id.as_str(), next_last_pushed],
                    |row| row.get(0),
                )?;
                if let Some(min_seq) = min_local_pending_seq {
                    if min_seq > expected_next {
                        super::rebase_local_device_seqs(
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
                super::super::kv_set_i64(
                    conn,
                    &last_pushed_key,
                    next_last_pushed.max(last_pushed_seq),
                )?;
                super::rebase_local_device_seqs(
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
                        super::rebase_local_device_seqs(
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

    progress(done_ops, total_ops);
    Ok(pushed_total)
}
