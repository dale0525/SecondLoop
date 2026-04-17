use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::{params, Connection};

use super::global_log_protocol::{
    GlobalLogHeadResponse, GlobalLogPullOp, GlobalLogPullRequest, GlobalLogPullResponse,
    GlobalLogPushErrorResponse, GlobalLogPushOp, GlobalLogPushRequest, GlobalLogPushResponse,
    GlobalLogResetResponse,
};
use super::runtime::Client;
use crate::crypto::{decrypt_bytes, encrypt_bytes};

const PUSH_LIMIT: i64 = 500;
const PULL_LIMIT: i64 = 500;

pub(super) enum GlobalLogRouteResult<T> {
    Parsed(T),
    Unsupported,
}

pub(super) enum GlobalLogPushRouteResult {
    Parsed(GlobalLogPushResponse),
    Unsupported,
    GenerationMismatch(GlobalLogPushErrorResponse),
    GenerationRequired(GlobalLogPushErrorResponse),
}

fn unsupported_status(status_code: u16) -> bool {
    matches!(status_code, 404 | 405)
}

fn fetch_push(
    http: &Client,
    endpoint: &str,
    id_token: &str,
    request: &GlobalLogPushRequest<'_>,
) -> Result<GlobalLogPushRouteResult> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    if unsupported_status(status.as_u16()) {
        return Ok(GlobalLogPushRouteResult::Unsupported);
    }
    if status.as_u16() == 409 {
        let text = resp.text().unwrap_or_default();
        let parsed: GlobalLogPushErrorResponse = serde_json::from_str(&text)?;
        if parsed.error == "generation_mismatch" {
            return Ok(GlobalLogPushRouteResult::GenerationMismatch(parsed));
        }
        if parsed.error == "generation_required" {
            return Ok(GlobalLogPushRouteResult::GenerationRequired(parsed));
        }
        return Err(anyhow!(
            "managed-vault v2 push failed: HTTP {status} {text}"
        ));
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault v2 push failed: HTTP {status} {text}"
        ));
    }
    Ok(GlobalLogPushRouteResult::Parsed(resp.json()?))
}

fn fetch_pull(
    http: &Client,
    endpoint: &str,
    id_token: &str,
    request: &GlobalLogPullRequest,
) -> Result<GlobalLogRouteResult<GlobalLogPullResponse>> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    if unsupported_status(status.as_u16()) {
        return Ok(GlobalLogRouteResult::Unsupported);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault v2 pull failed: HTTP {status} {text}"
        ));
    }
    Ok(GlobalLogRouteResult::Parsed(resp.json()?))
}

pub(super) fn fetch_head(
    http: &Client,
    endpoint: &str,
    id_token: &str,
) -> Result<GlobalLogRouteResult<GlobalLogHeadResponse>> {
    let resp = http.get(endpoint).bearer_auth(id_token).send()?;
    let status = resp.status();
    if unsupported_status(status.as_u16()) {
        return Ok(GlobalLogRouteResult::Unsupported);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault v2 head failed: HTTP {status} {text}"
        ));
    }
    Ok(GlobalLogRouteResult::Parsed(resp.json()?))
}

pub(super) fn reset_remote_vault(
    http: &Client,
    endpoint: &str,
    id_token: &str,
) -> Result<GlobalLogRouteResult<GlobalLogResetResponse>> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&serde_json::json!({}))
        .send()?;
    let status = resp.status();
    if unsupported_status(status.as_u16()) {
        return Ok(GlobalLogRouteResult::Unsupported);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault v2 reset failed: HTTP {status} {text}"
        ));
    }
    Ok(GlobalLogRouteResult::Parsed(resp.json()?))
}

fn maybe_collect_local_push_ops(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    device_id: &str,
    last_pushed_seq: i64,
) -> Result<(Vec<GlobalLogPushOp>, i64)> {
    let mut stmt = conn.prepare(
        r#"SELECT op_id, seq, op_json
           FROM oplog
           WHERE device_id = ?1 AND seq > ?2
           ORDER BY seq ASC
           LIMIT ?3"#,
    )?;
    let mut rows = stmt.query(params![device_id, last_pushed_seq, PUSH_LIMIT])?;

    let mut ops = Vec::new();
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
        ops.push(GlobalLogPushOp {
            device_id: device_id.to_string(),
            seq,
            op_id: op_id.clone(),
            client_op_id: op_id,
            ciphertext_b64: B64_STD.encode(ciphertext),
        });
        max_seq = max_seq.max(seq);
    }

    Ok((ops, max_seq))
}

fn apply_v2_pull_ops(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    scope_id: &str,
    ops: &[GlobalLogPullOp],
) -> Result<u64> {
    let apply_scope_id = super::global_log_state::apply_scope_id(scope_id);
    let mut batch_applied = 0u64;
    super::with_immediate_transaction(conn, || {
        let mut pending = super::load_pending_apply_op_ids(conn, &apply_scope_id)?;
        for op in ops {
            let ciphertext = B64_STD
                .decode(op.ciphertext_b64.as_bytes())
                .map_err(|error| anyhow!("invalid ciphertext_b64: {error}"))?;
            let plaintext = decrypt_bytes(
                sync_key,
                &ciphertext,
                format!("sync.ops:{}:{}", op.device_id, op.seq).as_bytes(),
            )?;
            let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
            let plaintext_op_id = op_json["op_id"]
                .as_str()
                .ok_or_else(|| anyhow!("managed-vault v2 pull op missing op_id"))?;
            if plaintext_op_id != op.op_id {
                return Err(anyhow!(
                    "managed-vault v2 pull op_id mismatch: envelope={} plaintext={}",
                    op.op_id,
                    plaintext_op_id
                ));
            }

            let inserted = super::super::insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
            if !inserted {
                continue;
            }

            match super::super::apply_op(conn, db_key, &op_json) {
                Ok(_) => {
                    batch_applied += 1;
                }
                Err(error) if super::is_foreign_key_constraint_error(&error) => {
                    pending.insert(plaintext_op_id.to_string());
                    super::super::kv_set_i64(
                        conn,
                        &super::pending_apply_key(&apply_scope_id, plaintext_op_id),
                        1,
                    )?;
                }
                Err(error) => return Err(error),
            }
        }
        super::apply_pending_ops_until_stable(conn, db_key, &apply_scope_id, &mut pending)?;
        Ok(())
    })?;
    Ok(batch_applied)
}

fn pull_page_is_contiguous(ops: &[GlobalLogPullOp], after_global_seq: i64) -> bool {
    let mut expected = after_global_seq + 1;
    for op in ops {
        if op.global_seq != expected {
            return false;
        }
        expected += 1;
    }
    true
}

pub(super) fn push_v2(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    mut progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<u64> {
    let http = super::runtime::client()?;
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let device_id = super::super::get_or_create_device_id(conn)?;
    let endpoint = super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/push"))?;

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;
    crate::db::backfill_knowledge_memory_feedback_oplog_if_needed(conn, db_key)?;

    let mut total_pushed = 0u64;
    loop {
        let last_pushed_seq =
            super::global_log_state::read_last_pushed_local_seq(conn, &scope_id, &device_id)?;
        let (ops, max_seq) =
            maybe_collect_local_push_ops(conn, db_key, sync_key, &device_id, last_pushed_seq)?;
        if ops.is_empty() {
            return Ok(total_pushed);
        }

        let local_generation = super::global_log_state::read_generation_id(conn, &scope_id)?;
        let mut request = GlobalLogPushRequest {
            base_global_seq: super::global_log_state::read_last_applied_global_seq(
                conn, &scope_id,
            )?,
            generation_id: local_generation.as_deref(),
            batch_id: "",
            ops,
        };
        let batch_id = uuid::Uuid::new_v4().to_string();
        request.batch_id = batch_id.as_str();

        match fetch_push(&http, &endpoint, id_token, &request)? {
            GlobalLogPushRouteResult::Unsupported => {
                return Err(anyhow!("managed-vault v2 push route unavailable"));
            }
            GlobalLogPushRouteResult::GenerationMismatch(error) => {
                if local_generation.is_some() {
                    super::global_log_state::rebuild_local_vault(conn, &scope_id)?;
                    if let Some(progress_fn) = progress.as_deref_mut() {
                        progress_fn(0, 0);
                    }
                    return Ok(0);
                }
                return Err(anyhow!(
                    "managed-vault v2 push failed: generation mismatch remote_generation_id={:?} remote_latest_global_seq={:?}",
                    error.remote_generation_id,
                    error.remote_latest_global_seq
                ));
            }
            GlobalLogPushRouteResult::GenerationRequired(error) => {
                if local_generation.is_none() {
                    super::global_log_state::rebuild_local_vault(conn, &scope_id)?;
                    if let Some(progress_fn) = progress.as_deref_mut() {
                        progress_fn(0, 0);
                    }
                    return Ok(0);
                }
                return Err(anyhow!(
                    "managed-vault v2 push failed: generation required remote_generation_id={:?} remote_latest_global_seq={:?}",
                    error.remote_generation_id,
                    error.remote_latest_global_seq
                ));
            }
            GlobalLogPushRouteResult::Parsed(response) => {
                super::global_log_state::write_generation_id(
                    conn,
                    &scope_id,
                    &response.generation_id,
                )?;
                super::global_log_state::write_last_pushed_local_seq(
                    conn, &scope_id, &device_id, max_seq,
                )?;
                total_pushed += (max_seq - last_pushed_seq).max(0) as u64;
                if let Some(progress_fn) = progress.as_deref_mut() {
                    progress_fn(total_pushed, total_pushed);
                }
            }
        }
    }
}

pub(super) fn pull_v2(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    mut progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<u64> {
    let http = super::runtime::client()?;
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let endpoint = super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/pull"))?;
    let head_endpoint = super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/head"))?;

    let initial_last_applied =
        super::global_log_state::read_last_applied_global_seq(conn, &scope_id)?;
    let total_target = match fetch_head(&http, &head_endpoint, id_token)? {
        GlobalLogRouteResult::Unsupported => {
            return Err(anyhow!("managed-vault v2 head route unavailable"));
        }
        GlobalLogRouteResult::Parsed(head) => {
            (head.remote_latest_global_seq - initial_last_applied).max(0) as u64
        }
    };

    let mut total_applied = 0u64;
    let mut last_applied = initial_last_applied;
    loop {
        let request = GlobalLogPullRequest {
            after_global_seq: last_applied,
            limit: PULL_LIMIT,
        };
        let response = match fetch_pull(&http, &endpoint, id_token, &request)? {
            GlobalLogRouteResult::Unsupported => {
                return Err(anyhow!("managed-vault v2 pull route unavailable"));
            }
            GlobalLogRouteResult::Parsed(response) => response,
        };

        let local_generation = super::global_log_state::read_generation_id(conn, &scope_id)?;
        if let Some(existing_generation) = &local_generation {
            if existing_generation != &response.generation_id {
                super::global_log_state::rebuild_local_vault(conn, &scope_id)?;
                last_applied = 0;
                continue;
            }
        }
        super::global_log_state::write_generation_id(conn, &scope_id, &response.generation_id)?;

        if response.ops.is_empty() {
            if let Some(progress_fn) = progress.as_deref_mut() {
                progress_fn(total_applied, total_target);
            }
            return Ok(total_applied);
        }

        if !pull_page_is_contiguous(&response.ops, last_applied) {
            if local_generation.is_some() || last_applied > 0 {
                super::global_log_state::rebuild_local_vault(conn, &scope_id)?;
                total_applied = 0;
                last_applied = 0;
                if let Some(progress_fn) = progress.as_deref_mut() {
                    progress_fn(0, total_target);
                }
                continue;
            }
            return Err(anyhow!(
                "managed-vault v2 pull returned non-contiguous global_seq page after_global_seq={last_applied}"
            ));
        }

        total_applied += apply_v2_pull_ops(conn, db_key, sync_key, &scope_id, &response.ops)?;
        last_applied = response
            .ops
            .last()
            .map(|item| item.global_seq)
            .unwrap_or(last_applied);
        super::global_log_state::write_last_applied_global_seq(conn, &scope_id, last_applied)?;

        if let Some(progress_fn) = progress.as_deref_mut() {
            let done = (last_applied - initial_last_applied).max(0) as u64;
            progress_fn(done.min(total_target), total_target);
        }

        if !response.has_more {
            return Ok(total_applied);
        }
    }
}
