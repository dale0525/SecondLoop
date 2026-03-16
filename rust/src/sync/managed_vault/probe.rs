use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use rusqlite::{Connection, OptionalExtension};

use super::{PullRequest, PullResponse};

fn managed_remote_attachment_exists(
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    attachment_id: &str,
) -> Result<bool> {
    let endpoint = super::runtime::url(
        base_url,
        &format!("/v1/vaults/{vault_id}/attachments/{attachment_id}"),
    )?;
    let resp = http.get(endpoint).bearer_auth(id_token).send()?;
    let status = resp.status();
    if status.as_u16() == 404 {
        return Ok(false);
    }
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault probe attachment failed: HTTP {status} {text}"
        ));
    }
    Ok(true)
}

pub(super) fn managed_remote_has_other_device_ops(
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<bool> {
    let endpoint = super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let request = PullRequest {
        device_id,
        since: BTreeMap::new(),
        limit: 1,
    };
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&request)
        .send()?;
    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault probe ops failed: HTTP {status} {text}"
        ));
    }
    let parsed: PullResponse = resp.json()?;
    Ok(!parsed.ops.is_empty() || !parsed.next.is_empty())
}

fn first_local_attachment_sha256(conn: &Connection) -> Result<Option<String>> {
    conn.query_row(
        r#"SELECT sha256 FROM attachments ORDER BY created_at ASC, sha256 ASC LIMIT 1"#,
        [],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

fn first_local_embedding_artifact_blob_ref(conn: &Connection) -> Result<Option<String>> {
    Ok(crate::db::list_distinct_embedding_artifact_blob_refs(conn)?
        .into_iter()
        .next())
}

pub(super) fn can_skip_fresh_device_full_push(
    conn: &Connection,
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<bool> {
    if !managed_remote_has_other_device_ops(http, base_url, vault_id, id_token, device_id)? {
        return Ok(false);
    }

    if let Some(sha256) = first_local_attachment_sha256(conn)? {
        if !managed_remote_attachment_exists(http, base_url, vault_id, id_token, &sha256)? {
            return Ok(false);
        }
    }

    if let Some(blob_ref) = first_local_embedding_artifact_blob_ref(conn)? {
        let artifact_id = crate::db::embedding_artifact_blob_storage_id(&blob_ref);
        if !managed_remote_attachment_exists(http, base_url, vault_id, id_token, &artifact_id)? {
            return Ok(false);
        }
    }

    Ok(true)
}
