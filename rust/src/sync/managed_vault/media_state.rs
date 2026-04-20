use anyhow::Result;
use rusqlite::{params, Connection};
use std::path::Path;

use crate::crypto::decrypt_bytes;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(super) struct PendingLocalMediaWriteWork {
    pub(super) attachments: bool,
    pub(super) artifacts: bool,
}

impl PendingLocalMediaWriteWork {
    pub(super) fn any(self) -> bool {
        self.attachments || self.artifacts
    }
}

pub(super) fn attachment_backfill_key(scope_id: &str) -> String {
    format!("managed_vault.attachments.bytes_backfilled:{scope_id}")
}

pub(super) fn artifact_backfill_key(scope_id: &str) -> String {
    format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}")
}

fn is_not_found_io_error(error: &anyhow::Error) -> bool {
    error
        .downcast_ref::<std::io::Error>()
        .is_some_and(|io| io.kind() == std::io::ErrorKind::NotFound)
}

pub(super) fn has_missing_local_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    app_dir: &Path,
) -> Result<bool> {
    let mut stmt = conn.prepare(r#"SELECT sha256 FROM attachments ORDER BY sha256 ASC"#)?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        match crate::db::read_attachment_bytes(conn, db_key, app_dir, &sha256) {
            Ok(_) => {}
            Err(error) if is_not_found_io_error(&error) => return Ok(true),
            Err(error) => return Err(error),
        }
    }
    Ok(false)
}

pub(super) fn has_missing_embedding_artifact_blobs(
    conn: &Connection,
    app_dir: &Path,
) -> Result<bool> {
    for blob_ref in crate::db::list_distinct_embedding_artifact_blob_refs(conn)? {
        if !crate::db::has_embedding_artifact_blob(app_dir, &blob_ref) {
            return Ok(true);
        }
    }
    Ok(false)
}

fn has_local_attachments(conn: &Connection) -> Result<bool> {
    conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM attachments LIMIT 1)"#,
        [],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn has_ready_embedding_artifact_blobs(conn: &Connection) -> Result<bool> {
    conn.query_row(
        r#"SELECT EXISTS(
               SELECT 1
               FROM embedding_artifact_manifests
               WHERE status = 'ready'
               LIMIT 1
           )"#,
        [],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn has_attachment_record(conn: &Connection, sha256: &str) -> Result<bool> {
    conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM attachments WHERE sha256 = ?1 LIMIT 1)"#,
        params![sha256],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn has_ready_embedding_artifact_ref(conn: &Connection, blob_ref: &str) -> Result<bool> {
    conn.query_row(
        r#"SELECT EXISTS(
               SELECT 1
               FROM embedding_artifact_manifests
               WHERE status = 'ready' AND blob_ref = ?1
               LIMIT 1
           )"#,
        params![blob_ref],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn read_last_local_media_write_seq(
    conn: &Connection,
    scope_id: &str,
    device_id: &str,
) -> Result<i64> {
    let v2 = super::global_log_state::read_last_pushed_local_seq(conn, scope_id, device_id)?;
    let legacy_per_device = super::super::kv_get_i64(
        conn,
        &format!("managed_vault.last_pushed_seq:{scope_id}:{device_id}"),
    )?
    .unwrap_or(0);
    let legacy_scope =
        super::super::kv_get_i64(conn, &format!("managed_vault.last_pushed_seq:{scope_id}"))?
            .unwrap_or(0);
    Ok(v2.max(legacy_per_device).max(legacy_scope))
}

fn pending_local_media_write_ops(
    conn: &Connection,
    db_key: &[u8; 32],
    scope_id: &str,
) -> Result<PendingLocalMediaWriteWork> {
    let device_id = super::super::get_or_create_device_id(conn)?;
    let last_pushed_seq = read_last_local_media_write_seq(conn, scope_id, &device_id)?;

    let mut work = PendingLocalMediaWriteWork::default();
    let mut stmt = conn.prepare(
        r#"SELECT op_id, op_json
           FROM oplog
           WHERE device_id = ?1 AND seq > ?2
           ORDER BY seq ASC"#,
    )?;
    let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq])?;
    while let Some(row) = rows.next()? {
        let op_id: String = row.get(0)?;
        let op_json_blob: Vec<u8> = row.get(1)?;
        let plaintext = decrypt_bytes(
            db_key,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )?;
        let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
        match op_json["type"].as_str() {
            Some("attachment.upsert.v1") | Some("attachment.delete.v1") => {
                work.attachments = true;
            }
            Some("embedding.artifact.upsert.v1") => {
                work.artifacts = true;
            }
            _ => {}
        }
        if work.any() {
            break;
        }
    }
    Ok(work)
}

fn pending_local_media_write_repairs(
    conn: &Connection,
    scope_id: &str,
) -> Result<PendingLocalMediaWriteWork> {
    let mut work = PendingLocalMediaWriteWork::default();
    for item in crate::sync::blob_repair::load_blob_repair_items(conn, scope_id)? {
        match item.kind {
            crate::sync::blob_repair::BlobRepairKind::UploadAttachment { sha256 } => {
                if has_attachment_record(conn, &sha256)? {
                    work.attachments = true;
                }
            }
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact { blob_ref } => {
                if has_ready_embedding_artifact_ref(conn, &blob_ref)? {
                    work.artifacts = true;
                }
            }
            crate::sync::blob_repair::BlobRepairKind::DeleteAttachmentRemote { .. } => {
                work.attachments = true;
            }
            _ => {}
        }
        if work.any() {
            break;
        }
    }
    Ok(work)
}

fn pending_local_media_write_work(
    conn: &Connection,
    db_key: &[u8; 32],
    scope_id: &str,
) -> Result<PendingLocalMediaWriteWork> {
    let mut work = pending_local_media_write_repairs(conn, scope_id)?;
    let pending_ops = pending_local_media_write_ops(conn, db_key, scope_id)?;
    let media_backup_summary = crate::db::cloud_media_backup_summary(conn, Some(scope_id))?;
    work.attachments |= pending_ops.attachments;
    work.artifacts |= pending_ops.artifacts;
    work.attachments |= media_backup_summary.pending > 0 || media_backup_summary.failed > 0;
    Ok(work)
}

pub(super) fn has_pending_local_media_write_work(
    conn: &Connection,
    db_key: &[u8; 32],
    scope_id: &str,
) -> Result<bool> {
    Ok(pending_local_media_write_work(conn, db_key, scope_id)?.any())
}

pub(super) fn update_v2_pull_backfill_markers(
    conn: &Connection,
    db_key: &[u8; 32],
    app_dir: &Path,
    scope_id: &str,
) -> Result<()> {
    let pending_work = pending_local_media_write_work(conn, db_key, scope_id)?;
    let attachment_key = attachment_backfill_key(scope_id);
    if has_local_attachments(conn)?
        && !has_missing_local_attachment_bytes(conn, db_key, app_dir)?
        && !pending_work.attachments
    {
        super::super::kv_set_i64(conn, &attachment_backfill_key(scope_id), 1)?;
    } else {
        let _ = conn.execute("DELETE FROM kv WHERE key = ?1", params![attachment_key])?;
    }

    let artifact_key = artifact_backfill_key(scope_id);
    if has_ready_embedding_artifact_blobs(conn)?
        && !has_missing_embedding_artifact_blobs(conn, app_dir)?
        && !pending_work.artifacts
    {
        super::super::kv_set_i64(conn, &artifact_backfill_key(scope_id), 1)?;
    } else {
        let _ = conn.execute("DELETE FROM kv WHERE key = ?1", params![artifact_key])?;
    }

    Ok(())
}
