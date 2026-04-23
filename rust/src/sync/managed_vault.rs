#![allow(dead_code)]

use anyhow::Result;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

mod admin;
mod apply_batch;
mod artifacts;
mod attachments;
mod blob_repair;
mod checkpoint;
mod global_log_client;
mod global_log_protocol;
mod global_log_state;
mod media_state;
mod pending_apply;
mod probe;
mod progress_metrics;
mod reseed;
mod runtime;
pub(crate) mod state_machine;
mod web_pull;

pub use admin::{clear_device, clear_vault};
pub use attachments::{download_attachment_bytes, upload_attachment_bytes};
use media_state::{
    has_missing_embedding_artifact_blobs, has_missing_local_attachment_bytes,
    should_finalize_v2_pull_blob_backfill, update_v2_pull_backfill_markers,
};
use pending_apply::{
    apply_pending_ops_until_stable, is_foreign_key_constraint_error, load_pending_apply_op_ids,
    pending_apply_key, rewind_since_for_unresolved_pending_devices, update_since_map,
};
pub use web_pull::{
    apply_web_pull_page, finalize_web_pull, read_web_pull_state, recover_web_pull_state_if_safe,
    WebPullApplyResult, WebPullPage, WebPullState,
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

pub(super) fn finalize_v2_pull_blob_backfill(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    applied_ops: u64,
) -> Result<()> {
    let scope_id = runtime::scope_id(base_url, vault_id);
    let app_dir = super::app_dir_from_conn(conn)?;
    let missing_attachments = has_missing_local_attachment_bytes(conn, db_key, app_dir.as_path())?;
    let missing_artifacts = has_missing_embedding_artifact_blobs(conn, app_dir.as_path())?;
    if !missing_attachments
        && !missing_artifacts
        && !should_finalize_v2_pull_blob_backfill(conn, &scope_id, applied_ops)?
    {
        return Ok(());
    }
    let _ = state_machine::transition(
        conn,
        &scope_id,
        state_machine::ManagedVaultSyncState::BlobBackfill,
    );

    let http = runtime::client()?;
    let download_ctx = attachments::AttachmentUploadContext {
        conn,
        db_key,
        sync_key,
        http: &http,
        base_url,
        vault_id,
        id_token,
        app_dir: app_dir.as_path(),
    };
    loop {
        let downloaded_artifacts =
            artifacts::download_missing_embedding_artifact_blobs(&download_ctx)?;
        let repair_stats = blob_repair::process_pending_download_repairs(&download_ctx, 8)?;
        let missing_attachments =
            has_missing_local_attachment_bytes(conn, db_key, app_dir.as_path())?;
        let missing_artifacts = has_missing_embedding_artifact_blobs(conn, app_dir.as_path())?;
        if !missing_attachments && !missing_artifacts {
            break;
        }
        if downloaded_artifacts == 0 && repair_stats.repaired == 0 {
            break;
        }
    }
    update_v2_pull_backfill_markers(conn, db_key, app_dir.as_path(), &scope_id)?;

    let _ = state_machine::transition(
        conn,
        &scope_id,
        state_machine::ManagedVaultSyncState::Completed,
    );
    Ok(())
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    global_log_client::push_v2(
        conn, db_key, sync_key, base_url, vault_id, id_token, true, None,
    )
}

pub fn push_with_progress(
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
        true,
        Some(progress),
    )
}

pub fn push_ops_only(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    global_log_client::push_v2(
        conn, db_key, sync_key, base_url, vault_id, id_token, false, None,
    )
}

pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    let pulled =
        global_log_client::pull_v2(conn, db_key, sync_key, base_url, vault_id, id_token, None)?;
    finalize_v2_pull_blob_backfill(conn, db_key, sync_key, base_url, vault_id, id_token, pulled)?;
    Ok(pulled)
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
    let pulled = global_log_client::pull_v2(
        conn,
        db_key,
        sync_key,
        base_url,
        vault_id,
        id_token,
        Some(progress),
    )?;
    finalize_v2_pull_blob_backfill(conn, db_key, sync_key, base_url, vault_id, id_token, pulled)?;
    Ok(pulled)
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
        false,
        Some(progress),
    )
}

fn maybe_run_managed_vault_retention(conn: &Connection, scope_id: &str) -> Result<()> {
    let _ = crate::db::run_oplog_retention_maintenance(
        conn,
        crate::db::OplogRetentionBackend::ManagedVault,
        scope_id,
    )?;
    Ok(())
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
