use std::fs;
use std::path::Path;

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use rusqlite::{params, Connection, OptionalExtension};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

fn resolve_attachment_group_metadata(
    conn: &Connection,
    attachment_sha256: &str,
) -> Result<Option<(String, String, String)>> {
    let roots = crate::db::list_attachment_derivation_roots_by_child(conn, attachment_sha256)?;
    let Some(root_sha256) = roots.first().cloned() else {
        return Ok(None);
    };

    let Some(role) = crate::db::attachment_derivation_role_for_root_child(
        conn,
        &root_sha256,
        attachment_sha256,
    )?
    else {
        return Ok(None);
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
        _ => return Ok(None),
    };

    Ok(Some((root_sha256, role, group_type.to_string())))
}

pub(super) struct AttachmentUploadContext<'a> {
    pub(super) conn: &'a Connection,
    pub(super) db_key: &'a [u8; 32],
    pub(super) sync_key: &'a [u8; 32],
    pub(super) http: &'a Client,
    pub(super) base_url: &'a str,
    pub(super) vault_id: &'a str,
    pub(super) id_token: &'a str,
    pub(super) app_dir: &'a Path,
}

pub(super) fn delete_remote_attachment_bytes(
    ctx: &AttachmentUploadContext<'_>,
    sha256: &str,
) -> Result<()> {
    let endpoint = super::runtime::url(
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
    let http = super::runtime::client()?;
    let app_dir = super::super::app_dir_from_conn(conn)?;

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

    let _ = crate::db::ensure_all_video_manifest_derivations(conn, db_key, app_dir.as_path())?;

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
    let http = super::runtime::client()?;
    let app_dir = super::super::app_dir_from_conn(conn)?;

    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment not found"))?;

    let endpoint = super::runtime::url(
        base_url,
        &format!("/v1/vaults/{vault_id}/attachments/{sha256}"),
    )?;
    let resp = http.get(endpoint).bearer_auth(id_token).send()?;

    let status = resp.status();
    if status.as_u16() == 404 {
        return Err(super::super::NotFound {
            path: format!("/v1/vaults/{vault_id}/attachments/{sha256}"),
        }
        .into());
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

    if super::super::sha256_hex(&plaintext) != sha256 {
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

pub(super) fn upload_all_local_attachment_bytes(ctx: &AttachmentUploadContext<'_>) -> Result<u64> {
    let _ = crate::db::ensure_all_video_manifest_derivations(ctx.conn, ctx.db_key, ctx.app_dir)?;

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

pub(super) fn upload_attachment_bytes_if_present(
    ctx: &AttachmentUploadContext<'_>,
    sha256: &str,
    mime_type: &str,
    created_at_ms: i64,
) -> Result<bool> {
    let exists: Option<i64> = ctx
        .conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    if exists.is_none() {
        return Ok(false);
    }

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

    let endpoint = super::runtime::url(
        ctx.base_url,
        &format!("/v1/vaults/{}/attachments/{sha256}", ctx.vault_id),
    )?;
    let mut request = ctx
        .http
        .put(endpoint)
        .bearer_auth(ctx.id_token)
        .header("content-type", "application/octet-stream")
        .header("x-media-byte-len", ciphertext.len().to_string())
        .header("x-media-mime", mime_type)
        .header("x-media-created-at-ms", created_at_ms.to_string());

    if let Some((root_sha256, role, group_type)) =
        resolve_attachment_group_metadata(ctx.conn, sha256)?
    {
        request = request
            .header("x-media-root-sha256", root_sha256)
            .header("x-media-derivation-role", role)
            .header("x-media-group-type", group_type);
    }

    let resp = request.body(ciphertext).send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault put attachment failed: HTTP {status} {text}"
        ));
    }

    Ok(true)
}
