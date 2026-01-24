use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::{STANDARD as B64_STD, URL_SAFE_NO_PAD as B64_URL};
use base64::Engine as _;
use reqwest::blocking::Client;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::crypto::{decrypt_bytes, encrypt_bytes};

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

#[derive(Debug, Serialize)]
struct PushRequest<'a> {
    device_id: &'a str,
    ops: Vec<PushOp>,
}

#[derive(Debug, Serialize)]
struct PushOp {
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
}

#[derive(Debug, Deserialize)]
struct PushResponse {
    max_seq: i64,
}

#[derive(Debug, Serialize)]
struct PullRequest<'a> {
    device_id: &'a str,
    since: BTreeMap<String, i64>,
    limit: i64,
}

#[derive(Debug, Deserialize)]
struct PullResponse {
    ops: Vec<PullOp>,
    next: BTreeMap<String, i64>,
}

#[derive(Debug, Deserialize)]
struct PullOp {
    device_id: String,
    seq: i64,
    op_id: String,
    ciphertext_b64: String,
}

fn scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    B64_URL.encode(raw.as_bytes())
}

fn client() -> Result<Client> {
    Ok(Client::builder().build()?)
}

fn url(base_url: &str, path: &str) -> Result<String> {
    let base = base_url.trim_end_matches('/');
    if base.is_empty() {
        return Err(anyhow!("missing_base_url"));
    }
    Ok(format!("{base}{path}"))
}

fn load_since_map(conn: &Connection, scope_id: &str) -> Result<BTreeMap<String, i64>> {
    let prefix = format!("managed_vault.last_pulled_seq:{scope_id}:");
    let pattern = format!("{prefix}%");

    let mut stmt = conn.prepare(r#"SELECT key, value FROM kv WHERE key LIKE ?1"#)?;
    let mut rows = stmt.query(params![pattern])?;

    let mut out = BTreeMap::new();
    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let value: String = row.get(1)?;
        let Some(device_id) = key.strip_prefix(&prefix) else {
            continue;
        };
        if device_id.is_empty() {
            continue;
        }
        if let Ok(seq) = value.parse::<i64>() {
            out.insert(device_id.to_string(), seq);
        }
    }
    Ok(out)
}

fn update_since_map(conn: &Connection, scope_id: &str, next: &BTreeMap<String, i64>) -> Result<()> {
    for (device_id, last_seq) in next {
        let key = format!("managed_vault.last_pulled_seq:{scope_id}:{device_id}");
        super::kv_set_i64(conn, &key, *last_seq)?;
    }
    Ok(())
}

fn ensure_device_registered(
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<String> {
    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/devices"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&RegisterDeviceRequest {
            platform: "unknown",
            device_id: Some(device_id),
        })
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault register-device failed: HTTP {status} {text}"
        ));
    }

    let parsed: RegisterDeviceResponse = serde_json::from_str(&text)?;
    Ok(parsed.device_id)
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    let http = client()?;
    let device_id = super::get_or_create_device_id(conn)?;
    let _ = ensure_device_registered(&http, base_url, vault_id, id_token, &device_id)?;

    let scope_id = scope_id(base_url, vault_id);
    let last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}");
    let last_pushed_seq = super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

    let mut stmt = conn.prepare(
        r#"SELECT op_id, seq, op_json
           FROM oplog
           WHERE device_id = ?1 AND seq > ?2
           ORDER BY seq ASC"#,
    )?;
    let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq])?;

    let mut ops: Vec<PushOp> = Vec::new();
    let mut max_seq = last_pushed_seq;

    while let Some(row) = rows.next()? {
        let op_id: String = row.get(0)?;
        let seq: i64 = row.get(1)?;
        let op_json_blob: Vec<u8> = row.get(2)?;

        let plaintext = decrypt_bytes(
            db_key,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )?;
        let ciphertext = encrypt_bytes(
            sync_key,
            &plaintext,
            format!("sync.ops:{device_id}:{seq}").as_bytes(),
        )?;
        let ciphertext_b64 = B64_STD.encode(ciphertext);

        ops.push(PushOp {
            seq,
            op_id,
            ciphertext_b64,
        });
        max_seq = max_seq.max(seq);
    }

    if ops.is_empty() {
        return Ok(0);
    }

    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/ops:push"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&PushRequest {
            device_id: device_id.as_str(),
            ops,
        })
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();

    if !status.is_success() {
        return Err(anyhow!("managed-vault push failed: HTTP {status} {text}"));
    }

    let parsed: PushResponse = serde_json::from_str(&text)?;
    if parsed.max_seq > last_pushed_seq {
        super::kv_set_i64(conn, &last_pushed_key, parsed.max_seq)?;
    }

    let pushed = max_seq.saturating_sub(last_pushed_seq);
    Ok(pushed as u64)
}

pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    let http = client()?;
    let local_device_id = super::get_or_create_device_id(conn)?;
    let _ = ensure_device_registered(&http, base_url, vault_id, id_token, &local_device_id)?;

    let scope_id = scope_id(base_url, vault_id);
    let since = load_since_map(conn, &scope_id)?;

    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&PullRequest {
            device_id: local_device_id.as_str(),
            since,
            limit: 500,
        })
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
    }

    let parsed: PullResponse = serde_json::from_str(&text)?;

    let mut applied: u64 = 0;
    for op in &parsed.ops {
        let ciphertext = B64_STD
            .decode(op.ciphertext_b64.as_bytes())
            .map_err(|e| anyhow!("invalid ciphertext_b64: {e}"))?;
        let plaintext = decrypt_bytes(
            sync_key,
            &ciphertext,
            format!("sync.ops:{}:{}", op.device_id, op.seq).as_bytes(),
        )?;
        let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
        let op_id = op_json["op_id"]
            .as_str()
            .ok_or_else(|| anyhow!("sync op missing op_id"))?
            .to_string();
        if op_id != op.op_id {
            return Err(anyhow!(
                "managed vault pull op_id mismatch: envelope={} plaintext={}",
                op.op_id,
                op_id
            ));
        }

        let seen: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM oplog WHERE op_id = ?1"#,
                params![op_id.as_str()],
                |row| row.get(0),
            )
            .optional()?;
        if seen.is_some() {
            continue;
        }

        super::apply_op(conn, db_key, &op_json)?;
        super::insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
        applied += 1;
    }

    update_since_map(conn, &scope_id, &parsed.next)?;
    Ok(applied)
}
