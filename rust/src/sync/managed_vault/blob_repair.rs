use anyhow::Result;

use super::attachments::AttachmentUploadContext;

pub(super) fn process_pending_blob_repairs(
    ctx: &AttachmentUploadContext<'_>,
    limit: usize,
) -> Result<crate::sync::blob_repair::BlobRepairProcessStats> {
    let scope_id = super::runtime::scope_id(ctx.base_url, ctx.vault_id);
    crate::sync::blob_repair::process_blob_repairs(ctx.conn, &scope_id, limit, |item| {
        let outcome = match &item.kind {
            crate::sync::blob_repair::BlobRepairKind::DownloadAttachment { sha256 } => {
                match super::attachments::download_attachment_bytes(
                    ctx.conn,
                    ctx.db_key,
                    ctx.sync_key,
                    ctx.base_url,
                    ctx.vault_id,
                    ctx.id_token,
                    sha256,
                ) {
                    Ok(()) => crate::sync::blob_repair::RepairAttemptOutcome::Done,
                    Err(error) if error.is::<super::super::NotFound>() => {
                        crate::sync::blob_repair::RepairAttemptOutcome::RetryLater
                    }
                    Err(error) => {
                        crate::sync::blob_repair::record_blob_repair_error(
                            ctx.conn,
                            &scope_id,
                            &error.to_string(),
                        )?;
                        crate::sync::blob_repair::RepairAttemptOutcome::StopProcessing
                    }
                }
            }
            crate::sync::blob_repair::BlobRepairKind::DownloadArtifact { blob_ref } => {
                let outcome = super::artifacts::download_embedding_artifact_blobs_by_refs(
                    ctx,
                    &[blob_ref.clone()],
                    None,
                )?;
                if outcome.missing_remote > 0 {
                    crate::sync::blob_repair::RepairAttemptOutcome::RetryLater
                } else {
                    crate::sync::blob_repair::RepairAttemptOutcome::Done
                }
            }
            crate::sync::blob_repair::BlobRepairKind::UploadAttachment { sha256 } => {
                let (mime_type, created_at_ms): (String, i64) = ctx.conn.query_row(
                    r#"SELECT mime_type, created_at FROM attachments WHERE sha256 = ?1"#,
                    rusqlite::params![sha256],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )?;
                match super::attachments::upload_attachment_bytes_if_present(
                    ctx,
                    sha256,
                    &mime_type,
                    created_at_ms,
                ) {
                    Ok(true) => crate::sync::blob_repair::RepairAttemptOutcome::Done,
                    Ok(false) => crate::sync::blob_repair::RepairAttemptOutcome::RetryLater,
                    Err(error) => {
                        crate::sync::blob_repair::record_blob_repair_error(
                            ctx.conn,
                            &scope_id,
                            &error.to_string(),
                        )?;
                        crate::sync::blob_repair::RepairAttemptOutcome::StopProcessing
                    }
                }
            }
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact { blob_ref } => {
                if super::artifacts::upload_embedding_artifact_blob_if_present(ctx, blob_ref)? {
                    crate::sync::blob_repair::RepairAttemptOutcome::Done
                } else {
                    crate::sync::blob_repair::RepairAttemptOutcome::RetryLater
                }
            }
        };
        if matches!(
            outcome,
            crate::sync::blob_repair::RepairAttemptOutcome::Done
        ) {
            crate::sync::blob_repair::clear_blob_repair_error(ctx.conn, &scope_id)?;
        }
        Ok(outcome)
    })
}
