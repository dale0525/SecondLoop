use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::OnceLock;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;
use reqwest::blocking::Client;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::db;

type RemoteDeviceSeqMap = BTreeMap<String, i64>;
type RemoteDeviceSeqMapProbeResult = (Option<RemoteDeviceSeqMap>, Option<String>);

#[derive(Debug, Serialize)]
struct DiagnosticsRegisterDeviceRequest<'a> {
    platform: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    device_id: Option<&'a str>,
}

#[derive(Debug, Deserialize)]
struct DiagnosticsRegisterDeviceResponse {
    device_id: String,
}

#[derive(Debug, Serialize)]
struct PullProbeRequest<'a> {
    device_id: &'a str,
    since: BTreeMap<String, i64>,
    limit: i64,
}

#[derive(Debug, Serialize)]
struct ManagedVaultCursorRemoteDiagnostics {
    scope_id: String,
    local_device_id: String,
    local_last_pulled_seq_by_device: BTreeMap<String, i64>,
    local_last_pushed_seq_by_device: BTreeMap<String, i64>,
    local_last_pushed_seq_legacy: Option<i64>,
    local_pending_apply_op_ids: Vec<String>,
    managed_vault_protocol_version: Option<u32>,
    managed_vault_generation_id: Option<String>,
    managed_vault_checkpoint_token_present: bool,
    managed_vault_last_route: Option<String>,
    managed_vault_last_state: Option<String>,
    blob_repair_queue_depth: u64,
    blob_repair_last_attempted_at_ms: Option<i64>,
    blob_repair_last_error: Option<String>,
    remote_device_seq_map: Option<RemoteDeviceSeqMap>,
    remote_device_seq_map_source: Option<String>,
    remote_probe_error: Option<String>,
}

fn client() -> Result<Client> {
    static CLIENT: OnceLock<Client> = OnceLock::new();
    Ok(CLIENT.get_or_init(Client::new).clone())
}

fn url(base_url: &str, path: &str) -> Result<String> {
    let base = base_url.trim_end_matches('/');
    if base.is_empty() {
        return Err(anyhow!("missing_base_url"));
    }
    Ok(format!("{base}{path}"))
}

fn managed_vault_scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    B64_URL.encode(raw.as_bytes())
}

fn kv_get_i64(conn: &Connection, key: &str) -> Result<Option<i64>> {
    let value: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            params![key],
            |row| row.get(0),
        )
        .optional()?;
    Ok(value.and_then(|v| v.parse::<i64>().ok()))
}

fn kv_get_string(conn: &Connection, key: &str) -> Result<Option<String>> {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = ?1"#,
        params![key],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

fn kv_scan_i64_map_by_prefix(conn: &Connection, prefix: &str) -> Result<BTreeMap<String, i64>> {
    let pattern = format!("{prefix}%");
    let mut stmt = conn.prepare(r#"SELECT key, value FROM kv WHERE key LIKE ?1"#)?;
    let mut rows = stmt.query(params![pattern])?;

    let mut out = BTreeMap::new();
    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let value: String = row.get(1)?;
        let Some(device_id) = key.strip_prefix(prefix) else {
            continue;
        };
        if device_id.trim().is_empty() {
            continue;
        }
        if let Ok(seq) = value.parse::<i64>() {
            out.insert(device_id.to_string(), seq);
        }
    }
    Ok(out)
}

fn kv_scan_keys_by_prefix(conn: &Connection, prefix: &str) -> Result<Vec<String>> {
    let pattern = format!("{prefix}%");
    let mut stmt = conn.prepare(r#"SELECT key FROM kv WHERE key LIKE ?1"#)?;
    let mut rows = stmt.query(params![pattern])?;

    let mut out: BTreeSet<String> = BTreeSet::new();
    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let Some(tail) = key.strip_prefix(prefix) else {
            continue;
        };
        if tail.trim().is_empty() {
            continue;
        }
        out.insert(tail.to_string());
    }

    Ok(out.into_iter().collect())
}

fn read_local_device_id(conn: &Connection) -> Result<Option<String>> {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = 'device_id'"#,
        [],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

fn json_value_to_i64(value: &serde_json::Value) -> Option<i64> {
    if let Some(seq) = value.as_i64() {
        return Some(seq);
    }
    value.as_str().and_then(|v| v.parse::<i64>().ok())
}

fn parse_device_seq_map_from_payload(
    payload: &serde_json::Value,
    key: &str,
) -> Option<RemoteDeviceSeqMap> {
    let map = payload.get(key)?.as_object()?;
    let mut out = BTreeMap::new();
    for (device_id, seq_value) in map {
        if let Some(seq) = json_value_to_i64(seq_value) {
            out.insert(device_id.to_string(), seq);
        }
    }
    if out.is_empty() {
        return None;
    }
    Some(out)
}

fn probe_remote_device_seq_map(
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    local_device_id: &str,
    since: &BTreeMap<String, i64>,
) -> Result<RemoteDeviceSeqMapProbeResult> {
    let http = client()?;
    let register_endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/devices"))?;
    let register_resp = http
        .post(register_endpoint)
        .bearer_auth(id_token)
        .json(&DiagnosticsRegisterDeviceRequest {
            platform: "unknown",
            device_id: Some(local_device_id),
        })
        .send()?;

    let register_status = register_resp.status();
    let register_text = register_resp.text().unwrap_or_default();
    if !register_status.is_success() {
        return Err(anyhow!(
            "managed-vault diagnostics register-device failed: HTTP {register_status} {register_text}"
        ));
    }

    let register_parsed: DiagnosticsRegisterDeviceResponse = serde_json::from_str(&register_text)?;
    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&PullProbeRequest {
            device_id: register_parsed.device_id.as_str(),
            since: since.clone(),
            limit: 1,
        })
        .send()?;

    let status = resp.status();
    let body = resp.bytes()?;
    if !status.is_success() {
        let text = String::from_utf8_lossy(body.as_ref()).to_string();
        return Err(anyhow!(
            "managed-vault diagnostics probe failed: HTTP {status} {text}"
        ));
    }

    let payload: serde_json::Value = serde_json::from_slice(body.as_ref())?;
    if let Some(map) = parse_device_seq_map_from_payload(&payload, "max") {
        return Ok((Some(map), Some("max".to_string())));
    }
    if let Some(map) = parse_device_seq_map_from_payload(&payload, "next") {
        return Ok((Some(map), Some("next".to_string())));
    }
    Ok((None, None))
}

fn build_managed_vault_cursor_remote_diagnostics(
    conn: &Connection,
    base_url: &str,
    vault_id: &str,
    firebase_id_token: Option<&str>,
) -> Result<ManagedVaultCursorRemoteDiagnostics> {
    let scope_id = managed_vault_scope_id(base_url, vault_id);
    let last_pulled_prefix = format!("managed_vault.last_pulled_seq:{scope_id}:");
    let last_pushed_prefix = format!("managed_vault.last_pushed_seq:{scope_id}:");
    let pending_prefix = format!("managed_vault.pending_apply:{scope_id}:");
    let legacy_last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}");

    let local_last_pulled_seq_by_device = kv_scan_i64_map_by_prefix(conn, &last_pulled_prefix)?;
    let local_last_pushed_seq_by_device = kv_scan_i64_map_by_prefix(conn, &last_pushed_prefix)?;
    let local_pending_apply_op_ids = kv_scan_keys_by_prefix(conn, &pending_prefix)?;
    let local_last_pushed_seq_legacy = kv_get_i64(conn, &legacy_last_pushed_key)?;
    let managed_vault_protocol_version =
        kv_get_string(conn, &format!("managed_vault.protocol_version:{scope_id}"))?
            .and_then(|value| value.parse::<u32>().ok());
    let managed_vault_generation_id =
        kv_get_string(conn, &format!("managed_vault.generation_id:{scope_id}"))?;
    let managed_vault_checkpoint_token_present =
        kv_get_string(conn, &format!("managed_vault.checkpoint_token:{scope_id}"))?.is_some();
    let managed_vault_last_route =
        kv_get_string(conn, &format!("managed_vault.last_route:{scope_id}"))?;
    let managed_vault_last_state =
        crate::sync::managed_vault::state_machine::load_state(conn, &scope_id)?
            .map(|state| state.as_str().to_string());
    let blob_repair = crate::sync::blob_repair::load_blob_repair_diagnostics(conn, &scope_id)?;
    let local_device_id = read_local_device_id(conn)?;
    let local_device_id_for_output = local_device_id
        .clone()
        .unwrap_or_else(|| "unknown".to_string());

    let mut remote_device_seq_map: Option<RemoteDeviceSeqMap> = None;
    let mut remote_device_seq_map_source: Option<String> = None;
    let mut remote_probe_error: Option<String> = None;

    if let Some(id_token) = firebase_id_token.map(str::trim).filter(|v| !v.is_empty()) {
        if let Some(probe_device_id) = local_device_id.as_deref() {
            match probe_remote_device_seq_map(
                base_url,
                vault_id,
                id_token,
                probe_device_id,
                &local_last_pulled_seq_by_device,
            ) {
                Ok((map, source)) => {
                    remote_device_seq_map = map;
                    remote_device_seq_map_source = source;
                }
                Err(e) => {
                    remote_probe_error = Some(e.to_string());
                }
            }
        } else {
            remote_probe_error = Some("missing_local_device_id".to_string());
        }
    } else {
        remote_probe_error = Some("missing_id_token".to_string());
    }

    Ok(ManagedVaultCursorRemoteDiagnostics {
        scope_id,
        local_device_id: local_device_id_for_output,
        local_last_pulled_seq_by_device,
        local_last_pushed_seq_by_device,
        local_last_pushed_seq_legacy,
        local_pending_apply_op_ids,
        managed_vault_protocol_version,
        managed_vault_generation_id,
        managed_vault_checkpoint_token_present,
        managed_vault_last_route,
        managed_vault_last_state,
        blob_repair_queue_depth: blob_repair.queued_count,
        blob_repair_last_attempted_at_ms: blob_repair.last_attempted_at_ms,
        blob_repair_last_error: blob_repair.last_error,
        remote_device_seq_map,
        remote_device_seq_map_source,
        remote_probe_error,
    })
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_cursor_diagnostics(
    app_dir: String,
    base_url: String,
    vault_id: String,
    firebase_id_token: Option<String>,
) -> Result<String> {
    let conn = db::open(Path::new(&app_dir))?;
    let diagnostics = build_managed_vault_cursor_remote_diagnostics(
        &conn,
        &base_url,
        &vault_id,
        firebase_id_token.as_deref(),
    )?;
    serde_json::to_string(&diagnostics)
        .map_err(|e| anyhow!("serialize managed-vault cursor diagnostics failed: {e}"))
}
