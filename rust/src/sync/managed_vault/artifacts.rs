use anyhow::{anyhow, Result};

use super::attachments::AttachmentUploadContext;
use crate::crypto::{decrypt_bytes, encrypt_bytes};

const EMBEDDING_ARTIFACT_MIME: &str = "application/vnd.secondloop.embedding-artifact";

fn remote_artifact_id(blob_ref: &str) -> String {
    crate::db::embedding_artifact_blob_storage_id(blob_ref)
}

pub(super) fn upload_all_local_embedding_artifact_blobs(
    ctx: &AttachmentUploadContext<'_>,
) -> Result<u64> {
    let mut uploaded = 0u64;
    for blob_ref in crate::db::list_distinct_embedding_artifact_blob_refs(ctx.conn)? {
        if upload_embedding_artifact_blob_if_present(ctx, &blob_ref)? {
            uploaded += 1;
        }
    }
    Ok(uploaded)
}

pub(super) fn upload_embedding_artifact_blob_if_present(
    ctx: &AttachmentUploadContext<'_>,
    blob_ref: &str,
) -> Result<bool> {
    if !crate::db::has_embedding_artifact_blob(ctx.app_dir, blob_ref) {
        return Ok(false);
    }

    let plaintext = crate::db::read_embedding_artifact_blob(ctx.app_dir, ctx.db_key, blob_ref)?;
    let aad = format!("sync.embedding_artifact.blob:{blob_ref}");
    let ciphertext = encrypt_bytes(ctx.sync_key, &plaintext, aad.as_bytes())?;

    let artifact_id = remote_artifact_id(blob_ref);
    let endpoint = super::url(
        ctx.base_url,
        &format!("/v1/vaults/{}/attachments/{artifact_id}", ctx.vault_id),
    )?;
    let resp = ctx
        .http
        .put(endpoint)
        .bearer_auth(ctx.id_token)
        .header("content-type", "application/octet-stream")
        .header("x-media-byte-len", ciphertext.len().to_string())
        .header("x-media-mime", EMBEDDING_ARTIFACT_MIME)
        .header("x-media-created-at-ms", "0")
        .body(ciphertext)
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault put embedding artifact failed: HTTP {status} {text}"
        ));
    }

    Ok(true)
}

pub(super) fn download_missing_embedding_artifact_blobs(
    ctx: &AttachmentUploadContext<'_>,
) -> Result<u64> {
    let mut downloaded = 0u64;
    for blob_ref in crate::db::list_distinct_embedding_artifact_blob_refs(ctx.conn)? {
        if crate::db::has_embedding_artifact_blob(ctx.app_dir, &blob_ref) {
            continue;
        }

        let artifact_id = remote_artifact_id(&blob_ref);
        let endpoint = super::url(
            ctx.base_url,
            &format!("/v1/vaults/{}/attachments/{artifact_id}", ctx.vault_id),
        )?;
        let resp = ctx.http.get(endpoint).bearer_auth(ctx.id_token).send()?;
        let status = resp.status();
        if status.as_u16() == 404 {
            continue;
        }
        if !status.is_success() {
            let text = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "managed-vault get embedding artifact failed: HTTP {status} {text}"
            ));
        }

        let ciphertext = resp.bytes()?;
        let aad = format!("sync.embedding_artifact.blob:{blob_ref}");
        let plaintext = decrypt_bytes(ctx.sync_key, ciphertext.as_ref(), aad.as_bytes())?;
        crate::db::write_embedding_artifact_blob(ctx.app_dir, ctx.db_key, &blob_ref, &plaintext)?;
        downloaded += 1;
    }
    Ok(downloaded)
}
