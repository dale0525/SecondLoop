use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use rusqlite::Connection;

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
    let resp = http.head(endpoint.clone()).bearer_auth(id_token).send()?;
    let status = resp.status();
    if status.as_u16() == 404 {
        return Ok(false);
    }
    if status.as_u16() == 405 || status.as_u16() == 501 {
        let fallback = http.get(endpoint).bearer_auth(id_token).send()?;
        let fallback_status = fallback.status();
        if fallback_status.as_u16() == 404 {
            return Ok(false);
        }
        if !fallback_status.is_success() {
            let text = fallback.text().unwrap_or_default();
            return Err(anyhow!(
                "managed-vault probe attachment failed: HTTP {fallback_status} {text}"
            ));
        }
        return Ok(true);
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

fn local_attachment_sha256s(conn: &Connection) -> Result<Vec<String>> {
    conn.prepare(r#"SELECT sha256 FROM attachments ORDER BY created_at ASC, sha256 ASC"#)?
        .query_map([], |row| row.get(0))?
        .collect::<rusqlite::Result<Vec<String>>>()
        .map_err(Into::into)
}

fn local_embedding_artifact_blob_refs(conn: &Connection) -> Result<Vec<String>> {
    crate::db::list_distinct_embedding_artifact_blob_refs(conn)
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

    for sha256 in local_attachment_sha256s(conn)? {
        if !managed_remote_attachment_exists(http, base_url, vault_id, id_token, &sha256)? {
            return Ok(false);
        }
    }

    for blob_ref in local_embedding_artifact_blob_refs(conn)? {
        let artifact_id = crate::db::embedding_artifact_blob_storage_id(&blob_ref);
        if !managed_remote_attachment_exists(http, base_url, vault_id, id_token, &artifact_id)? {
            return Ok(false);
        }
    }

    Ok(true)
}
