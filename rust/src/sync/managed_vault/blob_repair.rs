use anyhow::Result;
use rusqlite::OptionalExtension;

use super::attachments::AttachmentUploadContext;

fn process_pending_blob_repairs_with_filter(
    ctx: &AttachmentUploadContext<'_>,
    limit: usize,
    mut filter: impl FnMut(&crate::sync::blob_repair::BlobRepairKind) -> bool,
) -> Result<crate::sync::blob_repair::BlobRepairProcessStats> {
    let scope_id = super::runtime::scope_id(ctx.base_url, ctx.vault_id);
    crate::sync::blob_repair::process_blob_repairs_matching(
        ctx.conn,
        &scope_id,
        limit,
        |item| filter(&item.kind),
        |item| {
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
                    match super::artifacts::download_embedding_artifact_blobs_by_refs(
                        ctx,
                        &[blob_ref.clone()],
                        None,
                    ) {
                        Ok(outcome) if outcome.missing_remote > 0 => {
                            crate::sync::blob_repair::RepairAttemptOutcome::RetryLater
                        }
                        Ok(_) => crate::sync::blob_repair::RepairAttemptOutcome::Done,
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
                crate::sync::blob_repair::BlobRepairKind::UploadAttachment { sha256 } => {
                    let maybe_attachment: Option<(String, i64)> = ctx
                        .conn
                        .query_row(
                            r#"SELECT mime_type, created_at FROM attachments WHERE sha256 = ?1"#,
                            rusqlite::params![sha256],
                            |row| Ok((row.get(0)?, row.get(1)?)),
                        )
                        .optional()?;
                    let Some((mime_type, created_at_ms)) = maybe_attachment else {
                        crate::sync::blob_repair::clear_blob_repair_error(ctx.conn, &scope_id)?;
                        return Ok(crate::sync::blob_repair::RepairAttemptOutcome::Done);
                    };
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
                    match super::artifacts::upload_embedding_artifact_blob_if_present(ctx, blob_ref)
                    {
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
                crate::sync::blob_repair::BlobRepairKind::DeleteAttachmentRemote { sha256 } => {
                    match super::attachments::delete_remote_attachment_bytes(ctx, sha256) {
                        Ok(()) => crate::sync::blob_repair::RepairAttemptOutcome::Done,
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
            };
            if matches!(
                outcome,
                crate::sync::blob_repair::RepairAttemptOutcome::Done
            ) {
                crate::sync::blob_repair::clear_blob_repair_error(ctx.conn, &scope_id)?;
            }
            Ok(outcome)
        },
    )
}

pub(super) fn process_pending_blob_repairs(
    ctx: &AttachmentUploadContext<'_>,
    limit: usize,
) -> Result<crate::sync::blob_repair::BlobRepairProcessStats> {
    process_pending_blob_repairs_with_filter(ctx, limit, |_| true)
}

pub(super) fn process_pending_download_repairs(
    ctx: &AttachmentUploadContext<'_>,
    limit: usize,
) -> Result<crate::sync::blob_repair::BlobRepairProcessStats> {
    process_pending_blob_repairs_with_filter(ctx, limit, |kind| {
        matches!(
            kind,
            crate::sync::blob_repair::BlobRepairKind::DownloadAttachment { .. }
                | crate::sync::blob_repair::BlobRepairKind::DownloadArtifact { .. }
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::managed_vault::runtime;

    fn test_upload_context<'a>(
        conn: &'a rusqlite::Connection,
        db_key: &'a [u8; 32],
        sync_key: &'a [u8; 32],
        http: &'a runtime::Client,
        app_dir: &'a std::path::Path,
    ) -> AttachmentUploadContext<'a> {
        AttachmentUploadContext {
            conn,
            db_key,
            sync_key,
            http,
            base_url: "://invalid-base-url",
            vault_id: "vault-a",
            id_token: "token-a",
            app_dir,
        }
    }

    #[test]
    fn upload_artifact_repairs_stop_processing_instead_of_aborting_the_queue() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let http = runtime::client().expect("client");
        let ctx = test_upload_context(&conn, &db_key, &sync_key, &http, dir.path());
        let scope_id = runtime::scope_id(ctx.base_url, ctx.vault_id);

        crate::db::write_embedding_artifact_blob(dir.path(), &db_key, "blob-a", b"blob-a")
            .expect("seed blob a");
        crate::db::write_embedding_artifact_blob(dir.path(), &db_key, "blob-b", b"blob-b")
            .expect("seed blob b");
        crate::sync::blob_repair::enqueue_blob_repair(
            &conn,
            &scope_id,
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact {
                blob_ref: "blob-a".to_string(),
            },
        )
        .expect("enqueue upload repair a");
        crate::sync::blob_repair::enqueue_blob_repair(
            &conn,
            &scope_id,
            crate::sync::blob_repair::BlobRepairKind::UploadArtifact {
                blob_ref: "blob-b".to_string(),
            },
        )
        .expect("enqueue upload repair b");

        let stats = process_pending_blob_repairs(&ctx, 8).expect("process repairs");

        assert_eq!(stats.attempted, 1);
        assert_eq!(stats.repaired, 0);
        assert_eq!(stats.remaining, 2);
        assert!(
            crate::sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
                .expect("load diagnostics")
                .last_error
                .is_some(),
            "expected upload artifact failure to be recorded on the queue"
        );
    }

    #[test]
    fn download_artifact_repairs_stop_processing_instead_of_aborting_the_queue() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let http = runtime::client().expect("client");
        let ctx = test_upload_context(&conn, &db_key, &sync_key, &http, dir.path());
        let scope_id = runtime::scope_id(ctx.base_url, ctx.vault_id);

        crate::sync::blob_repair::enqueue_blob_repair(
            &conn,
            &scope_id,
            crate::sync::blob_repair::BlobRepairKind::DownloadArtifact {
                blob_ref: "blob-a".to_string(),
            },
        )
        .expect("enqueue download repair a");
        crate::sync::blob_repair::enqueue_blob_repair(
            &conn,
            &scope_id,
            crate::sync::blob_repair::BlobRepairKind::DownloadArtifact {
                blob_ref: "blob-b".to_string(),
            },
        )
        .expect("enqueue download repair b");

        let stats = process_pending_blob_repairs(&ctx, 8).expect("process repairs");

        assert_eq!(stats.attempted, 1);
        assert_eq!(stats.repaired, 0);
        assert_eq!(stats.remaining, 2);
        assert!(
            crate::sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
                .expect("load diagnostics")
                .last_error
                .is_some(),
            "expected download artifact failure to be recorded on the queue"
        );
    }
}
