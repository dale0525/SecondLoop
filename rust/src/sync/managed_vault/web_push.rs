use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

const PUSH_LIMIT: i64 = 500;
const REPAIR_MEDIA_ACTION_LIMIT: usize = 8;
const EMBEDDING_ARTIFACT_MIME: &str = "application/vnd.secondloop.embedding-artifact";

#[derive(Debug, Serialize)]
struct WebPushRequest {
    base_global_seq: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    generation_id: Option<String>,
    batch_id: String,
    ops: Vec<super::global_log_protocol::GlobalLogPushOp>,
}

#[derive(Debug, Serialize)]
struct WebPushBatch {
    has_ops: bool,
    device_id: String,
    last_pushed_seq: i64,
    max_seq: i64,
    op_count: u64,
    request: Option<WebPushRequest>,
    media_actions: Vec<WebPushMediaAction>,
    media_phase: WebPushMediaPhase,
}

#[derive(Debug, Deserialize)]
struct WebPushBatchReceipt {
    has_ops: bool,
    device_id: String,
    max_seq: i64,
    op_count: u64,
    #[serde(default)]
    media_phase: WebPushMediaPhase,
}

#[derive(Debug, Serialize)]
struct WebPushApplyResult {
    accepted: u64,
    generation_id: String,
    remote_latest_global_seq: i64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum WebPushMediaPhase {
    #[default]
    None,
    Batch,
    Repairs,
    FreshDevice,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum WebPushMediaActionKind {
    AttachmentUpload,
    AttachmentDelete,
    ArtifactUpload,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct WebPushMediaAction {
    kind: WebPushMediaActionKind,
    remote_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    blob_ref: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    mime_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    created_at_ms: Option<i64>,
}

#[derive(Debug, Serialize)]
struct WebPushMediaUpload {
    has_body: bool,
    remote_id: String,
    mime_type: String,
    created_at_ms: i64,
    byte_len: u64,
    ciphertext_b64: String,
    headers: BTreeMap<String, String>,
    retryable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error_message: Option<String>,
}

fn is_not_found_io_error(error: &anyhow::Error) -> bool {
    error
        .downcast_ref::<std::io::Error>()
        .is_some_and(|io| io.kind() == std::io::ErrorKind::NotFound)
}

fn fresh_device_media_clean_key(scope_id: &str, device_id: &str) -> String {
    format!("managed_vault.web_push_fresh_device_media_clean:{scope_id}:{device_id}")
}
fn fresh_device_media_done_key(
    scope_id: &str,
    device_id: &str,
    action: &WebPushMediaAction,
) -> String {
    let kind = match action.kind {
        WebPushMediaActionKind::AttachmentUpload => "attachment_upload",
        WebPushMediaActionKind::AttachmentDelete => "attachment_delete",
        WebPushMediaActionKind::ArtifactUpload => "artifact_upload",
    };
    let identity = match action.kind {
        WebPushMediaActionKind::ArtifactUpload => action
            .blob_ref
            .as_deref()
            .unwrap_or(action.remote_id.as_str()),
        WebPushMediaActionKind::AttachmentUpload | WebPushMediaActionKind::AttachmentDelete => {
            action
                .sha256
                .as_deref()
                .unwrap_or(action.remote_id.as_str())
        }
    };
    format!(
        "managed_vault.web_push_fresh_device_media_done:{scope_id}:{device_id}:{kind}:{identity}"
    )
}
fn fresh_device_media_clean(conn: &Connection, scope_id: &str, device_id: &str) -> Result<bool> {
    Ok(
        super::super::kv_get_i64(conn, &fresh_device_media_clean_key(scope_id, device_id))?
            .unwrap_or(0)
            != 0,
    )
}
fn mark_fresh_device_media_clean(conn: &Connection, scope_id: &str, device_id: &str) -> Result<()> {
    super::super::kv_set_i64(conn, &fresh_device_media_clean_key(scope_id, device_id), 1)
}
fn fresh_device_media_done(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
    action: &WebPushMediaAction,
) -> Result<bool> {
    Ok(super::super::kv_get_i64(
        conn,
        &fresh_device_media_done_key(scope_id, device_id, action),
    )?
    .unwrap_or(0)
        != 0)
}
fn mark_fresh_device_media_done(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
    action: &WebPushMediaAction,
) -> Result<()> {
    super::super::kv_set_i64(
        conn,
        &fresh_device_media_done_key(scope_id, device_id, action),
        1,
    )
}
fn clear_fresh_device_media_done(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
    action: &WebPushMediaAction,
) -> Result<()> {
    let _ = conn.execute(
        r#"DELETE FROM kv WHERE key = ?1"#,
        params![fresh_device_media_done_key(scope_id, device_id, action)],
    )?;
    Ok(())
}
fn clear_fresh_device_media_clean(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
) -> Result<()> {
    let _ = conn.execute(
        r#"DELETE FROM kv WHERE key = ?1"#,
        params![fresh_device_media_clean_key(scope_id, device_id)],
    )?;
    Ok(())
}

fn no_body_upload(
    action: &WebPushMediaAction,
    mime_type: String,
    created_at_ms: i64,
    retryable: bool,
    error_message: Option<String>,
) -> WebPushMediaUpload {
    WebPushMediaUpload {
        has_body: false,
        remote_id: action.remote_id.clone(),
        mime_type,
        created_at_ms,
        byte_len: 0,
        ciphertext_b64: String::new(),
        headers: BTreeMap::new(),
        retryable,
        error_message,
    }
}

fn attachment_group_media_headers(
    conn: &Connection,
    attachment_sha256: &str,
) -> Result<BTreeMap<String, String>> {
    let mut headers = BTreeMap::new();
    let roots = crate::db::list_attachment_derivation_roots_by_child(conn, attachment_sha256)?;
    let Some(root_sha256) = roots.first().cloned() else {
        return Ok(headers);
    };

    let Some(role) = crate::db::attachment_derivation_role_for_root_child(
        conn,
        &root_sha256,
        attachment_sha256,
    )?
    else {
        return Ok(headers);
    };

    let root_mime_type: Option<String> = conn
        .query_row(
            r#"SELECT mime_type FROM attachments WHERE sha256 = ?1"#,
            params![root_sha256.as_str()],
            |row| row.get(0),
        )
        .optional()?;
    let group_type = match root_mime_type.as_deref() {
        Some("application/x.secondloop.video+json") => "video",
        _ => return Ok(headers),
    };

    headers.insert("x-media-root-sha256".to_string(), root_sha256);
    headers.insert("x-media-derivation-role".to_string(), role);
    headers.insert("x-media-group-type".to_string(), group_type.to_string());
    Ok(headers)
}

fn local_batch_media_actions(
    batch: &super::global_log_client::LocalPushBatch,
) -> Vec<WebPushMediaAction> {
    let mut actions = Vec::new();
    for (sha256, action) in &batch.attachment_actions {
        match action {
            super::global_log_client::PendingAttachmentAction::Upload {
                mime_type,
                created_at_ms,
            } => actions.push(WebPushMediaAction {
                kind: WebPushMediaActionKind::AttachmentUpload,
                remote_id: sha256.clone(),
                sha256: Some(sha256.clone()),
                blob_ref: None,
                mime_type: Some(mime_type.clone()),
                created_at_ms: Some(*created_at_ms),
            }),
            super::global_log_client::PendingAttachmentAction::Delete => {
                actions.push(WebPushMediaAction {
                    kind: WebPushMediaActionKind::AttachmentDelete,
                    remote_id: sha256.clone(),
                    sha256: Some(sha256.clone()),
                    blob_ref: None,
                    mime_type: None,
                    created_at_ms: None,
                });
            }
        }
    }
    for blob_ref in &batch.artifact_blob_refs {
        actions.push(WebPushMediaAction {
            kind: WebPushMediaActionKind::ArtifactUpload,
            remote_id: crate::db::embedding_artifact_blob_storage_id(blob_ref),
            sha256: None,
            blob_ref: Some(blob_ref.clone()),
            mime_type: Some(EMBEDDING_ARTIFACT_MIME.to_string()),
            created_at_ms: Some(0),
        });
    }
    actions
}

fn all_local_media_actions(conn: &Connection) -> Result<Vec<WebPushMediaAction>> {
    let mut actions = Vec::new();
    let mut stmt = conn.prepare(
        r#"SELECT sha256, mime_type, created_at
           FROM attachments
           ORDER BY created_at ASC, sha256 ASC"#,
    )?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        let mime_type: String = row.get(1)?;
        let created_at_ms: i64 = row.get(2)?;
        actions.push(WebPushMediaAction {
            kind: WebPushMediaActionKind::AttachmentUpload,
            remote_id: sha256.clone(),
            sha256: Some(sha256),
            blob_ref: None,
            mime_type: Some(mime_type),
            created_at_ms: Some(created_at_ms),
        });
    }

    for blob_ref in crate::db::list_distinct_embedding_artifact_blob_refs(conn)? {
        actions.push(WebPushMediaAction {
            kind: WebPushMediaActionKind::ArtifactUpload,
            remote_id: crate::db::embedding_artifact_blob_storage_id(&blob_ref),
            sha256: None,
            blob_ref: Some(blob_ref),
            mime_type: Some(EMBEDDING_ARTIFACT_MIME.to_string()),
            created_at_ms: Some(0),
        });
    }
    Ok(actions)
}

fn fresh_device_media_actions(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
) -> Result<Vec<WebPushMediaAction>> {
    let mut pending = Vec::new();
    for action in all_local_media_actions(conn)? {
        if !fresh_device_media_done(conn, scope_id, device_id, &action)? {
            pending.push(action);
        }
    }
    Ok(pending)
}

fn media_actions_include_attachment_upload(actions: &[WebPushMediaAction]) -> bool {
    actions
        .iter()
        .any(|action| action.kind == WebPushMediaActionKind::AttachmentUpload)
}

fn prepare_local_attachment_derivations_for_web(
    conn: &Connection,
    db_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
) -> Result<()> {
    let app_dir = super::super::app_dir_from_conn(conn)?;
    match crate::db::ensure_all_video_manifest_derivations(conn, db_key, app_dir.as_path()) {
        Ok(_) => Ok(()),
        Err(error) if is_not_found_io_error(&error) => {
            let scope_id = super::runtime::scope_id(base_url, vault_id);
            crate::sync::blob_repair::record_blob_repair_error(conn, &scope_id, &error.to_string())
        }
        Err(error) => Err(error),
    }
}

fn pending_repair_media_actions(
    conn: &Connection,
    scope_id: &str,
    limit: usize,
) -> Result<Vec<WebPushMediaAction>> {
    let mut actions = Vec::new();
    if limit == 0 {
        return Ok(actions);
    }
    for item in crate::sync::blob_repair::load_blob_repair_items(conn, scope_id)? {
        match item.kind {
            crate::sync::blob_repair::BlobRepairKind::UploadAttachment { sha256 } => {
                let maybe_attachment: Option<(String, i64)> = conn
                    .query_row(
                        r#"SELECT mime_type, created_at FROM attachments WHERE sha256 = ?1"#,
                        params![sha256.as_str()],
                        |row| Ok((row.get(0)?, row.get(1)?)),
                    )
                    .optional()?;
                actions.push(WebPushMediaAction {
                    kind: WebPushMediaActionKind::AttachmentUpload,
                    remote_id: sha256.clone(),
                    sha256: Some(sha256),
                    blob_ref: None,
                    mime_type: maybe_attachment
                        .as_ref()
                        .map(|(mime_type, _)| mime_type.clone()),
                    created_at_ms: maybe_attachment.map(|(_, created_at_ms)| created_at_ms),
                });
            }
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact { blob_ref } => {
                actions.push(WebPushMediaAction {
                    kind: WebPushMediaActionKind::ArtifactUpload,
                    remote_id: crate::db::embedding_artifact_blob_storage_id(&blob_ref),
                    sha256: None,
                    blob_ref: Some(blob_ref),
                    mime_type: Some(EMBEDDING_ARTIFACT_MIME.to_string()),
                    created_at_ms: Some(0),
                });
            }
            crate::sync::blob_repair::BlobRepairKind::DeleteAttachmentRemote { sha256 } => {
                actions.push(WebPushMediaAction {
                    kind: WebPushMediaActionKind::AttachmentDelete,
                    remote_id: sha256.clone(),
                    sha256: Some(sha256),
                    blob_ref: None,
                    mime_type: None,
                    created_at_ms: None,
                });
            }
            _ => {}
        }
        if actions.len() >= limit {
            break;
        }
    }
    Ok(actions)
}

pub fn prepare_web_push_batch(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
) -> Result<String> {
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let device_id = super::super::get_or_create_device_id(conn)?;
    let last_pushed_seq =
        super::global_log_state::read_last_pushed_local_seq(conn, &scope_id, &device_id)?;

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;
    let batch = super::global_log_client::collect_local_push_ops_for_web(
        conn,
        db_key,
        sync_key,
        &device_id,
        last_pushed_seq,
        PUSH_LIMIT,
    )?;
    if batch.ops.is_empty() {
        let mut media_actions =
            pending_repair_media_actions(conn, &scope_id, REPAIR_MEDIA_ACTION_LIMIT)?;
        let mut media_phase = if media_actions.is_empty() {
            WebPushMediaPhase::None
        } else {
            WebPushMediaPhase::Repairs
        };
        if media_actions.is_empty()
            && last_pushed_seq == 0
            && !fresh_device_media_clean(conn, &scope_id, &device_id)?
            && super::global_log_client::has_remote_device_ops(conn, &device_id)?
        {
            media_actions = fresh_device_media_actions(conn, &scope_id, &device_id)?;
            if !media_actions.is_empty() {
                media_phase = WebPushMediaPhase::FreshDevice;
            }
        }
        if media_actions_include_attachment_upload(&media_actions) {
            prepare_local_attachment_derivations_for_web(conn, db_key, base_url, vault_id)?;
        }
        return Ok(serde_json::to_string(&WebPushBatch {
            has_ops: false,
            device_id,
            last_pushed_seq,
            max_seq: batch.max_seq,
            op_count: 0,
            request: None,
            media_actions,
            media_phase,
        })?);
    }

    let media_actions = local_batch_media_actions(&batch);
    if media_actions_include_attachment_upload(&media_actions) {
        prepare_local_attachment_derivations_for_web(conn, db_key, base_url, vault_id)?;
    }
    let media_phase = if media_actions.is_empty() {
        WebPushMediaPhase::None
    } else {
        WebPushMediaPhase::Batch
    };
    let request = WebPushRequest {
        base_global_seq: super::global_log_state::read_last_applied_global_seq(conn, &scope_id)?,
        generation_id: super::global_log_state::read_generation_id(conn, &scope_id)?,
        batch_id: uuid::Uuid::new_v4().to_string(),
        ops: batch.ops,
    };
    Ok(serde_json::to_string(&WebPushBatch {
        has_ops: true,
        device_id,
        last_pushed_seq,
        max_seq: batch.max_seq,
        op_count: request.ops.len() as u64,
        request: Some(request),
        media_actions,
        media_phase,
    })?)
}

pub fn apply_web_push_response(
    conn: &Connection,
    base_url: &str,
    vault_id: &str,
    batch_json: &str,
    response_json: &str,
) -> Result<String> {
    let batch: WebPushBatchReceipt = serde_json::from_str(batch_json)?;
    if !batch.has_ops {
        return Ok(serde_json::to_string(&WebPushApplyResult {
            accepted: 0,
            generation_id: String::new(),
            remote_latest_global_seq: 0,
        })?);
    }

    let response: super::global_log_protocol::GlobalLogPushResponse =
        serde_json::from_str(response_json)?;
    super::global_log_client::ensure_complete_push_acceptance_for_count(&response, batch.op_count)?;

    let scope_id = super::runtime::scope_id(base_url, vault_id);
    super::global_log_state::write_generation_id(conn, &scope_id, &response.generation_id)?;
    super::global_log_state::write_last_pushed_local_seq(
        conn,
        &scope_id,
        &batch.device_id,
        batch.max_seq,
    )?;
    if batch.max_seq > 0 {
        clear_fresh_device_media_clean(conn, &scope_id, &batch.device_id)?;
    }
    if response.accepted > 0 {
        super::maybe_run_managed_vault_retention(conn, &scope_id)?;
    }

    Ok(serde_json::to_string(&WebPushApplyResult {
        accepted: response.accepted,
        generation_id: response.generation_id,
        remote_latest_global_seq: response.remote_latest_global_seq,
    })?)
}

fn prepare_attachment_upload(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    action: &WebPushMediaAction,
) -> Result<WebPushMediaUpload> {
    let sha256 = action
        .sha256
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(action.remote_id.as_str());
    let maybe_attachment: Option<(String, i64)> = conn
        .query_row(
            r#"SELECT mime_type, created_at FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;
    let (mime_type, created_at_ms) = match maybe_attachment {
        Some(value) => value,
        None => {
            return Ok(no_body_upload(
                action,
                action
                    .mime_type
                    .clone()
                    .unwrap_or_else(|| "application/octet-stream".to_string()),
                action.created_at_ms.unwrap_or(0),
                false,
                Some("attachment_not_found".to_string()),
            ));
        }
    };
    let app_dir = super::super::app_dir_from_conn(conn)?;
    let plaintext = match crate::db::read_attachment_bytes(conn, db_key, app_dir.as_path(), sha256)
    {
        Ok(bytes) => bytes,
        Err(error) if is_not_found_io_error(&error) => {
            let scope_id = super::runtime::scope_id(base_url, vault_id);
            crate::sync::blob_repair::enqueue_blob_repair(
                conn,
                &scope_id,
                crate::sync::blob_repair::BlobRepairKind::UploadAttachment {
                    sha256: sha256.to_string(),
                },
            )?;
            return Ok(no_body_upload(
                action,
                mime_type,
                created_at_ms,
                true,
                Some(error.to_string()),
            ));
        }
        Err(error) => return Err(error),
    };

    let aad = format!("sync.attachment.bytes:{sha256}");
    let ciphertext = crate::crypto::encrypt_bytes(sync_key, &plaintext, aad.as_bytes())?;
    let byte_len = ciphertext.len() as u64;
    Ok(WebPushMediaUpload {
        has_body: true,
        remote_id: action.remote_id.clone(),
        mime_type,
        created_at_ms,
        byte_len,
        ciphertext_b64: B64_STD.encode(ciphertext),
        headers: attachment_group_media_headers(conn, sha256)?,
        retryable: false,
        error_message: None,
    })
}

fn prepare_artifact_upload(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    action: &WebPushMediaAction,
) -> Result<WebPushMediaUpload> {
    let blob_ref = action
        .blob_ref
        .as_deref()
        .ok_or_else(|| anyhow!("missing_artifact_blob_ref"))?;
    let app_dir = super::super::app_dir_from_conn(conn)?;
    if !crate::db::has_embedding_artifact_blob(app_dir.as_path(), blob_ref) {
        let scope_id = super::runtime::scope_id(base_url, vault_id);
        crate::sync::blob_repair::enqueue_blob_repair(
            conn,
            &scope_id,
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact {
                blob_ref: blob_ref.to_string(),
            },
        )?;
        return Ok(no_body_upload(
            action,
            EMBEDDING_ARTIFACT_MIME.to_string(),
            0,
            true,
            Some("artifact_blob_not_found".to_string()),
        ));
    }

    let plaintext = crate::db::read_embedding_artifact_blob(app_dir.as_path(), db_key, blob_ref)?;
    let aad = format!("sync.embedding_artifact.blob:{blob_ref}");
    let ciphertext = crate::crypto::encrypt_bytes(sync_key, &plaintext, aad.as_bytes())?;
    let byte_len = ciphertext.len() as u64;
    Ok(WebPushMediaUpload {
        has_body: true,
        remote_id: action.remote_id.clone(),
        mime_type: EMBEDDING_ARTIFACT_MIME.to_string(),
        created_at_ms: 0,
        byte_len,
        ciphertext_b64: B64_STD.encode(ciphertext),
        headers: BTreeMap::new(),
        retryable: false,
        error_message: None,
    })
}

pub fn prepare_web_push_media_upload(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    action_json: &str,
    _media_phase: WebPushMediaPhase,
) -> Result<String> {
    let action: WebPushMediaAction = serde_json::from_str(action_json)?;
    let upload = match action.kind {
        WebPushMediaActionKind::AttachmentUpload => {
            prepare_attachment_upload(conn, db_key, sync_key, base_url, vault_id, &action)?
        }
        WebPushMediaActionKind::ArtifactUpload => {
            prepare_artifact_upload(conn, db_key, sync_key, base_url, vault_id, &action)?
        }
        WebPushMediaActionKind::AttachmentDelete => {
            return Err(anyhow!("delete_media_action_has_no_upload_body"));
        }
    };
    Ok(serde_json::to_string(&upload)?)
}

fn repair_kind_matches_action(
    kind: &crate::sync::blob_repair::BlobRepairKind,
    action: &WebPushMediaAction,
) -> bool {
    match (kind, action.kind) {
        (
            crate::sync::blob_repair::BlobRepairKind::UploadAttachment { sha256 },
            WebPushMediaActionKind::AttachmentUpload,
        ) => {
            action
                .sha256
                .as_deref()
                .unwrap_or(action.remote_id.as_str())
                == sha256
        }
        (
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact { blob_ref },
            WebPushMediaActionKind::ArtifactUpload,
        ) => action.blob_ref.as_deref() == Some(blob_ref.as_str()),
        (
            crate::sync::blob_repair::BlobRepairKind::DeleteAttachmentRemote { sha256 },
            WebPushMediaActionKind::AttachmentDelete,
        ) => {
            action
                .sha256
                .as_deref()
                .unwrap_or(action.remote_id.as_str())
                == sha256
        }
        _ => false,
    }
}

fn enqueue_repair_for_action(
    conn: &Connection,
    scope_id: &str,
    action: &WebPushMediaAction,
) -> Result<()> {
    match action.kind {
        WebPushMediaActionKind::AttachmentUpload => {
            crate::sync::blob_repair::enqueue_blob_repair(
                conn,
                scope_id,
                crate::sync::blob_repair::BlobRepairKind::UploadAttachment {
                    sha256: action
                        .sha256
                        .clone()
                        .unwrap_or_else(|| action.remote_id.clone()),
                },
            )?;
        }
        WebPushMediaActionKind::ArtifactUpload => {
            if let Some(blob_ref) = action.blob_ref.as_ref() {
                crate::sync::blob_repair::enqueue_blob_repair(
                    conn,
                    scope_id,
                    crate::sync::blob_repair::BlobRepairKind::UploadArtifact {
                        blob_ref: blob_ref.clone(),
                    },
                )?;
            }
        }
        WebPushMediaActionKind::AttachmentDelete => {
            crate::sync::blob_repair::enqueue_blob_repair(
                conn,
                scope_id,
                crate::sync::blob_repair::BlobRepairKind::DeleteAttachmentRemote {
                    sha256: action
                        .sha256
                        .clone()
                        .unwrap_or_else(|| action.remote_id.clone()),
                },
            )?;
        }
    }
    Ok(())
}

pub fn record_web_push_media_result(
    conn: &Connection,
    base_url: &str,
    vault_id: &str,
    action_json: &str,
    success: bool,
    error_message: Option<&str>,
) -> Result<bool> {
    let action: WebPushMediaAction = serde_json::from_str(action_json)?;
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let device_id = super::super::get_or_create_device_id(conn)?;
    if success {
        let stats = crate::sync::blob_repair::process_blob_repairs_matching(
            conn,
            &scope_id,
            usize::MAX,
            |item| repair_kind_matches_action(&item.kind, &action),
            |_| Ok(crate::sync::blob_repair::RepairAttemptOutcome::Done),
        )?;
        if stats.repaired > 0 {
            crate::sync::blob_repair::clear_blob_repair_error(conn, &scope_id)?;
        }
        mark_fresh_device_media_done(conn, &scope_id, &device_id, &action)?;
        return Ok(true);
    }

    clear_fresh_device_media_done(conn, &scope_id, &device_id, &action)?;
    enqueue_repair_for_action(conn, &scope_id, &action)?;
    crate::sync::blob_repair::record_blob_repair_error(
        conn,
        &scope_id,
        error_message.unwrap_or("managed-vault web media push failed"),
    )?;
    Ok(false)
}

pub fn complete_web_push_media_batch(
    conn: &Connection,
    db_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    batch_json: &str,
) -> Result<bool> {
    let batch: WebPushBatchReceipt = serde_json::from_str(batch_json)?;
    if batch.media_phase != WebPushMediaPhase::None {
        let scope_id = super::runtime::scope_id(base_url, vault_id);
        let app_dir = super::super::app_dir_from_conn(conn)?;
        super::media_state::update_v2_pull_backfill_markers(
            conn,
            db_key,
            app_dir.as_path(),
            &scope_id,
        )?;
        if batch.media_phase == WebPushMediaPhase::FreshDevice {
            mark_fresh_device_media_clean(conn, &scope_id, &batch.device_id)?;
        }
    }
    Ok(true)
}

#[cfg(test)]
#[path = "web_push_tests.rs"]
mod tests;
