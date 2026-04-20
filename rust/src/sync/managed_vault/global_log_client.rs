use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::{params, Connection};
use std::collections::{BTreeMap, BTreeSet, HashSet};

use super::global_log_protocol::{
    GlobalLogPullErrorResponse, GlobalLogPullOp, GlobalLogPullRequest, GlobalLogPullResponse,
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
    InvalidBatch(GlobalLogPushErrorResponse),
    GenerationMismatch(GlobalLogPushErrorResponse),
    GenerationRequired(GlobalLogPushErrorResponse),
}

pub(super) enum GlobalLogPullRouteResult {
    Parsed(GlobalLogPullResponse),
    Unsupported,
    ResetRequired(GlobalLogPullErrorResponse),
}

enum PendingAttachmentAction {
    Upload {
        mime_type: String,
        created_at_ms: i64,
    },
    Delete,
}

struct LocalPushBatch {
    ops: Vec<GlobalLogPushOp>,
    max_seq: i64,
    attachment_actions: BTreeMap<String, PendingAttachmentAction>,
    artifact_blob_refs: BTreeSet<String>,
}

fn ensure_complete_push_acceptance_from_explicit_seqs(
    response: &GlobalLogPushResponse,
    requested: u64,
    committed_global_seqs: &[i64],
) -> Result<()> {
    if committed_global_seqs.len() as u64 != requested {
        return Err(anyhow!(
            "managed-vault v2 push returned inconsistent explicit seq list: accepted {} of {} ops with {} committed seqs",
            response.accepted,
            requested,
            committed_global_seqs.len(),
        ));
    }

    let mut seen = HashSet::with_capacity(committed_global_seqs.len());
    for seq in committed_global_seqs {
        if *seq <= 0 || !seen.insert(*seq) {
            return Err(anyhow!(
                "managed-vault v2 push returned invalid committed_global_seqs: {:?}",
                committed_global_seqs,
            ));
        }
    }
    Ok(())
}

fn ensure_complete_push_acceptance(
    response: &GlobalLogPushResponse,
    batch: &LocalPushBatch,
) -> Result<()> {
    let requested = batch.ops.len() as u64;
    if response.accepted == 0 {
        if requested > 0 {
            return Err(anyhow!(
                "managed-vault v2 push returned inconsistent retry response: accepted=0 for {} requested ops",
                requested,
            ));
        }
        if response.committed_from_seq.is_some() || response.committed_to_seq.is_some() {
            return Err(anyhow!(
                "managed-vault v2 push returned inconsistent retry response: accepted=0 committed_from_seq={:?} committed_to_seq={:?}",
                response.committed_from_seq,
                response.committed_to_seq,
            ));
        }
        if response
            .committed_global_seqs
            .as_ref()
            .is_some_and(|seqs| !seqs.is_empty())
        {
            return Err(anyhow!(
                "managed-vault v2 push returned inconsistent retry response: accepted=0 committed_global_seqs={:?}",
                response.committed_global_seqs,
            ));
        }
        return Ok(());
    }

    if response.accepted != requested {
        return Err(anyhow!(
            "managed-vault v2 push returned partial acceptance: accepted {} of {} ops",
            response.accepted,
            requested,
        ));
    }

    if let Some(committed_global_seqs) = response.committed_global_seqs.as_ref() {
        return ensure_complete_push_acceptance_from_explicit_seqs(
            response,
            requested,
            committed_global_seqs,
        );
    }

    let committed_from_seq = response.committed_from_seq.ok_or_else(|| {
        anyhow!(
            "managed-vault v2 push returned inconsistent response: missing committed_from_seq for {} accepted ops",
            response.accepted,
        )
    })?;
    let committed_to_seq = response.committed_to_seq.ok_or_else(|| {
        anyhow!(
            "managed-vault v2 push returned inconsistent response: missing committed_to_seq for {} accepted ops",
            response.accepted,
        )
    })?;

    if committed_to_seq < committed_from_seq {
        return Err(anyhow!(
            "managed-vault v2 push returned invalid committed range: {}..{}",
            committed_from_seq,
            committed_to_seq,
        ));
    }

    let committed_count = (committed_to_seq - committed_from_seq + 1) as u64;
    if committed_count != requested {
        return Err(anyhow!(
            "managed-vault v2 push returned inconsistent committed range: accepted {} of {} ops with committed range {}..{}",
            response.accepted,
            requested,
            committed_from_seq,
            committed_to_seq,
        ));
    }

    Ok(())
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
    if status.as_u16() == 400 {
        let text = resp.text().unwrap_or_default();
        let parsed: GlobalLogPushErrorResponse = serde_json::from_str(&text)?;
        if parsed.error == "invalid_batch" {
            return Ok(GlobalLogPushRouteResult::InvalidBatch(parsed));
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
) -> Result<GlobalLogPullRouteResult> {
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(request)
        .send()?;
    let status = resp.status();
    if unsupported_status(status.as_u16()) {
        return Ok(GlobalLogPullRouteResult::Unsupported);
    }
    if status.as_u16() == 409 {
        let text = resp.text().unwrap_or_default();
        let parsed: GlobalLogPullErrorResponse = serde_json::from_str(&text)?;
        if parsed.error == "reset_required" {
            return Ok(GlobalLogPullRouteResult::ResetRequired(parsed));
        }
        return Err(anyhow!(
            "managed-vault v2 pull failed: HTTP {status} {text}"
        ));
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault v2 pull failed: HTTP {status} {text}"
        ));
    }
    Ok(GlobalLogPullRouteResult::Parsed(resp.json()?))
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
) -> Result<LocalPushBatch> {
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
    let mut attachment_actions = BTreeMap::new();
    let mut artifact_blob_refs = BTreeSet::new();
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
            if op_json["type"].as_str() == Some("attachment.upsert.v1") {
                if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                    let mime_type = op_json["payload"]["mime_type"]
                        .as_str()
                        .unwrap_or("application/octet-stream");
                    let created_at_ms = op_json["payload"]["created_at_ms"].as_i64().unwrap_or(0);
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
                    attachment_actions.insert(sha256.to_string(), PendingAttachmentAction::Delete);
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
        ops.push(GlobalLogPushOp {
            device_id: device_id.to_string(),
            seq,
            op_id: op_id.clone(),
            client_op_id: op_id,
            ciphertext_b64: B64_STD.encode(ciphertext),
        });
        max_seq = max_seq.max(seq);
    }

    Ok(LocalPushBatch {
        ops,
        max_seq,
        attachment_actions,
        artifact_blob_refs,
    })
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

fn format_push_route_error(error: &GlobalLogPushErrorResponse) -> Result<anyhow::Error> {
    let body = serde_json::to_string(error)?;
    Ok(anyhow!("managed-vault v2 push failed: HTTP 409 {body}"))
}

fn format_invalid_batch_error(error: &GlobalLogPushErrorResponse) -> Result<anyhow::Error> {
    let body = serde_json::to_string(error)?;
    Ok(anyhow!(
        "managed-vault v2 push rejected local batch: HTTP 400 {body}"
    ))
}

fn has_local_unpushed_changes(conn: &Connection, scope_id: &str) -> Result<bool> {
    let device_id = super::super::get_or_create_device_id(conn)?;
    let last_pushed_seq =
        super::global_log_state::read_last_pushed_local_seq(conn, scope_id, &device_id)?;
    conn.query_row(
        r#"SELECT EXISTS(
               SELECT 1
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               LIMIT 1
           )"#,
        params![device_id, last_pushed_seq],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn rebuild_local_vault_if_safe(
    conn: &Connection,
    db_key: &[u8; 32],
    scope_id: &str,
    base_url: &str,
    vault_id: &str,
) -> Result<()> {
    if super::full_push_requires_legacy_media_sync(conn, db_key, base_url, vault_id)? {
        return Err(anyhow!(
            "managed-vault v2 recovery blocked: local_media_backfill_pending"
        ));
    }
    if has_local_unpushed_changes(conn, scope_id)? {
        return Err(anyhow!(
            "managed-vault v2 recovery blocked: local_unpushed_changes"
        ));
    }
    super::global_log_state::rebuild_local_vault(conn, scope_id)
}

fn enqueue_attachment_upload_repair(conn: &Connection, scope_id: &str, sha256: &str) -> Result<()> {
    super::super::blob_repair::enqueue_blob_repair(
        conn,
        scope_id,
        super::super::blob_repair::BlobRepairKind::UploadAttachment {
            sha256: sha256.to_string(),
        },
    )
}

fn enqueue_artifact_upload_repair(conn: &Connection, scope_id: &str, blob_ref: &str) -> Result<()> {
    super::super::blob_repair::enqueue_blob_repair(
        conn,
        scope_id,
        super::super::blob_repair::BlobRepairKind::UploadArtifact {
            blob_ref: blob_ref.to_string(),
        },
    )
}

fn enqueue_attachment_delete_repair(conn: &Connection, scope_id: &str, sha256: &str) -> Result<()> {
    super::super::blob_repair::enqueue_blob_repair(
        conn,
        scope_id,
        super::super::blob_repair::BlobRepairKind::DeleteAttachmentRemote {
            sha256: sha256.to_string(),
        },
    )
}

fn record_blob_side_effect_error(
    conn: &Connection,
    scope_id: &str,
    error: &anyhow::Error,
) -> Result<()> {
    super::super::blob_repair::record_blob_repair_error(conn, scope_id, &error.to_string())
}

fn run_post_commit_blob_side_effects(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    http: &Client,
    app_dir: &std::path::Path,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    scope_id: &str,
    batch: &LocalPushBatch,
) -> Result<()> {
    let upload_ctx = super::attachments::AttachmentUploadContext {
        conn,
        db_key,
        sync_key,
        http,
        base_url,
        vault_id,
        id_token,
        app_dir,
    };

    if batch
        .attachment_actions
        .values()
        .any(|action| matches!(action, PendingAttachmentAction::Upload { .. }))
    {
        if let Err(error) = super::attachments::prepare_local_attachment_uploads(&upload_ctx) {
            for (sha256, action) in &batch.attachment_actions {
                if matches!(action, PendingAttachmentAction::Upload { .. }) {
                    enqueue_attachment_upload_repair(conn, scope_id, sha256)?;
                }
            }
            record_blob_side_effect_error(conn, scope_id, &error)?;
        }
    }

    for (sha256, action) in &batch.attachment_actions {
        match action {
            PendingAttachmentAction::Upload {
                mime_type,
                created_at_ms,
            } => match super::attachments::upload_attachment_bytes_if_present(
                &upload_ctx,
                sha256,
                mime_type,
                *created_at_ms,
            ) {
                Ok(_) => {}
                Err(error) => {
                    enqueue_attachment_upload_repair(conn, scope_id, sha256)?;
                    record_blob_side_effect_error(conn, scope_id, &error)?;
                }
            },
            PendingAttachmentAction::Delete => {
                if let Err(error) =
                    super::attachments::delete_remote_attachment_bytes(&upload_ctx, sha256)
                {
                    enqueue_attachment_delete_repair(conn, scope_id, sha256)?;
                    record_blob_side_effect_error(conn, scope_id, &error)?;
                }
            }
        }
    }

    for blob_ref in &batch.artifact_blob_refs {
        match super::artifacts::upload_embedding_artifact_blob_if_present(&upload_ctx, blob_ref) {
            Ok(_) => {}
            Err(error) => {
                enqueue_artifact_upload_repair(conn, scope_id, blob_ref)?;
                record_blob_side_effect_error(conn, scope_id, &error)?;
            }
        }
    }

    Ok(())
}

pub(super) fn push_v2(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    upload_attachment_bytes: bool,
    mut progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<u64> {
    let http = super::runtime::client()?;
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let device_id = super::super::get_or_create_device_id(conn)?;
    let endpoint = super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/push"))?;

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;
    crate::db::backfill_knowledge_memory_feedback_oplog_if_needed(conn, db_key)?;
    let app_dir = if upload_attachment_bytes {
        Some(super::super::app_dir_from_conn(conn)?)
    } else {
        None
    };

    let mut total_pushed = 0u64;
    loop {
        let last_pushed_seq =
            super::global_log_state::read_last_pushed_local_seq(conn, &scope_id, &device_id)?;
        let batch =
            maybe_collect_local_push_ops(conn, db_key, sync_key, &device_id, last_pushed_seq)?;
        if batch.ops.is_empty() {
            if upload_attachment_bytes {
                let upload_ctx = super::attachments::AttachmentUploadContext {
                    conn,
                    db_key,
                    sync_key,
                    http: &http,
                    base_url,
                    vault_id,
                    id_token,
                    app_dir: app_dir.as_ref().expect("managed-vault app_dir").as_path(),
                };
                let _ = super::blob_repair::process_pending_blob_repairs(&upload_ctx, 8)?;
            }
            if total_pushed > 0 {
                super::maybe_run_managed_vault_retention(conn, &scope_id)?;
            }
            return Ok(total_pushed);
        }

        let local_generation = super::global_log_state::read_generation_id(conn, &scope_id)?;
        let mut request = GlobalLogPushRequest {
            base_global_seq: super::global_log_state::read_last_applied_global_seq(
                conn, &scope_id,
            )?,
            generation_id: local_generation.as_deref(),
            batch_id: "",
            ops: batch.ops.clone(),
        };
        let batch_id = uuid::Uuid::new_v4().to_string();
        request.batch_id = batch_id.as_str();

        match fetch_push(&http, &endpoint, id_token, &request)? {
            GlobalLogPushRouteResult::Unsupported => {
                return Err(anyhow!("managed-vault v2 push route unavailable"));
            }
            GlobalLogPushRouteResult::InvalidBatch(error) => {
                return Err(format_invalid_batch_error(&error)?);
            }
            GlobalLogPushRouteResult::GenerationMismatch(error) => {
                return Err(format_push_route_error(&error)?);
            }
            GlobalLogPushRouteResult::GenerationRequired(error) => {
                return Err(format_push_route_error(&error)?);
            }
            GlobalLogPushRouteResult::Parsed(response) => {
                ensure_complete_push_acceptance(&response, &batch)?;
                super::global_log_state::write_generation_id(
                    conn,
                    &scope_id,
                    &response.generation_id,
                )?;
                super::global_log_state::write_last_pushed_local_seq(
                    conn,
                    &scope_id,
                    &device_id,
                    batch.max_seq,
                )?;
                if upload_attachment_bytes {
                    run_post_commit_blob_side_effects(
                        conn,
                        db_key,
                        sync_key,
                        &http,
                        app_dir.as_ref().expect("managed-vault app_dir").as_path(),
                        base_url,
                        vault_id,
                        id_token,
                        &scope_id,
                        &batch,
                    )?;
                }
                total_pushed += (batch.max_seq - last_pushed_seq).max(0) as u64;
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

    let initial_last_applied =
        super::global_log_state::read_last_applied_global_seq(conn, &scope_id)?;
    let mut progress_baseline = initial_last_applied;
    let mut total_target: Option<u64> = None;

    let mut total_applied = 0u64;
    let mut last_applied = initial_last_applied;
    let mut reset_recovered = false;
    let mut generation_recovered = false;
    let mut progress_reset_pending = false;
    loop {
        let request = GlobalLogPullRequest {
            after_global_seq: last_applied,
            limit: PULL_LIMIT,
        };
        let response = match fetch_pull(&http, &endpoint, id_token, &request)? {
            GlobalLogPullRouteResult::Unsupported => {
                return Err(anyhow!("managed-vault v2 pull route unavailable"));
            }
            GlobalLogPullRouteResult::ResetRequired(error) => {
                if reset_recovered {
                    return Err(anyhow!(
                        "managed-vault v2 pull reset_required persisted after local rebuild: reason={:?} remote_generation_id={:?} remote_latest_global_seq={:?}",
                        error.reason,
                        error.remote_generation_id,
                        error.remote_latest_global_seq
                    ));
                }
                rebuild_local_vault_if_safe(conn, db_key, &scope_id, base_url, vault_id)?;
                total_applied = 0;
                last_applied = 0;
                progress_baseline = 0;
                total_target = None;
                reset_recovered = true;
                progress_reset_pending = true;
                if let Some(progress_fn) = progress.as_deref_mut() {
                    progress_fn(0, total_target.unwrap_or(0));
                }
                continue;
            }
            GlobalLogPullRouteResult::Parsed(response) => response,
        };

        let effective_total_target = *total_target.get_or_insert_with(|| {
            (response.remote_latest_global_seq - progress_baseline).max(0) as u64
        });
        if progress_reset_pending {
            if let Some(progress_fn) = progress.as_deref_mut() {
                progress_fn(0, effective_total_target);
            }
            progress_reset_pending = false;
        }

        let local_generation = super::global_log_state::read_generation_id(conn, &scope_id)?;
        let response_generation = response.generation_id.trim();
        if response_generation.is_empty() {
            if response.remote_latest_global_seq == 0 && response.ops.is_empty() {
                if local_generation.is_some() || last_applied > 0 {
                    rebuild_local_vault_if_safe(conn, db_key, &scope_id, base_url, vault_id)?;
                    total_applied = 0;
                    total_target = None;
                }
                if let Some(progress_fn) = progress.as_deref_mut() {
                    progress_fn(total_applied, total_target.unwrap_or(0));
                }
                return Ok(total_applied);
            }
            return Err(anyhow!(
                "managed-vault v2 pull returned an empty generation_id with remote_latest_global_seq={} ops={}",
                response.remote_latest_global_seq,
                response.ops.len()
            ));
        }
        if let Some(existing_generation) = &local_generation {
            if existing_generation != response_generation {
                if generation_recovered {
                    return Err(anyhow!(
                        "managed-vault v2 pull generation mismatch persisted after local rebuild: local_generation_id={} remote_generation_id={}",
                        existing_generation,
                        response_generation
                    ));
                }
                rebuild_local_vault_if_safe(conn, db_key, &scope_id, base_url, vault_id)?;
                total_applied = 0;
                last_applied = 0;
                progress_baseline = 0;
                total_target = None;
                generation_recovered = true;
                progress_reset_pending = true;
                continue;
            }
        }
        super::global_log_state::write_generation_id(conn, &scope_id, response_generation)?;

        if response.ops.is_empty() {
            if let Some(progress_fn) = progress.as_deref_mut() {
                progress_fn(total_applied, effective_total_target);
            }
            return Ok(total_applied);
        }

        if !pull_page_is_contiguous(&response.ops, last_applied) {
            if local_generation.is_some() || last_applied > 0 {
                rebuild_local_vault_if_safe(conn, db_key, &scope_id, base_url, vault_id)?;
                total_applied = 0;
                last_applied = 0;
                progress_baseline = 0;
                total_target = None;
                progress_reset_pending = true;
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
        reset_recovered = false;

        if let Some(progress_fn) = progress.as_deref_mut() {
            let done = (last_applied - progress_baseline).max(0) as u64;
            progress_fn(done.min(effective_total_target), effective_total_target);
        }

        if !response.has_more {
            return Ok(total_applied);
        }
    }
}
