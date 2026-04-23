use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::OnceLock;
use std::time::Duration;

use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;
use reqwest::blocking::{Client, ClientBuilder};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::db;

type RemoteDeviceSeqMap = BTreeMap<String, i64>;
const DIAGNOSTICS_HTTP_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Debug, Deserialize)]
struct DiagnosticsV2HeadResponse {
    generation_id: String,
    remote_latest_global_seq: i64,
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
    managed_vault_v2_generation_id: Option<String>,
    managed_vault_v2_last_applied_global_seq: i64,
    managed_vault_v2_last_pushed_seq_local_device: Option<i64>,
    managed_vault_checkpoint_token_present: bool,
    managed_vault_last_route: Option<String>,
    managed_vault_last_state: Option<String>,
    blob_repair_queue_depth: u64,
    blob_repair_last_attempted_at_ms: Option<i64>,
    blob_repair_last_error: Option<String>,
    managed_vault_v2_remote_generation_id: Option<String>,
    managed_vault_v2_remote_latest_global_seq: Option<i64>,
    managed_vault_v2_remote_head_error: Option<String>,
    remote_device_seq_map: Option<RemoteDeviceSeqMap>,
    remote_device_seq_map_source: Option<String>,
    remote_probe_error: Option<String>,
}

fn client() -> Result<Client> {
    static CLIENT: OnceLock<Result<Client, String>> = OnceLock::new();
    match CLIENT.get_or_init(|| build_client(DIAGNOSTICS_HTTP_TIMEOUT).map_err(|e| e.to_string())) {
        Ok(client) => Ok(client.clone()),
        Err(err) => Err(anyhow!("create diagnostics http client failed: {err}")),
    }
}

fn build_client(timeout: Duration) -> Result<Client> {
    ClientBuilder::new()
        .connect_timeout(timeout)
        .timeout(timeout)
        .build()
        .map_err(Into::into)
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

fn probe_managed_vault_v2_head(
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<DiagnosticsV2HeadResponse> {
    let http = client()?;
    let endpoint = url(base_url, &format!("/v2/vaults/{vault_id}/sync/head"))?;
    let resp = http.get(endpoint).bearer_auth(id_token).send()?;
    let status = resp.status();
    let body = resp.bytes()?;
    if !status.is_success() {
        let text = String::from_utf8_lossy(body.as_ref()).to_string();
        return Err(anyhow!(
            "managed-vault diagnostics v2 head probe failed: HTTP {status} {text}"
        ));
    }
    serde_json::from_slice(body.as_ref()).map_err(Into::into)
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
    let managed_vault_v2_generation_id =
        kv_get_string(conn, &format!("managed_vault_v2.generation_id:{scope_id}"))?;
    let managed_vault_v2_last_applied_global_seq = kv_get_i64(
        conn,
        &format!("managed_vault_v2.last_applied_global_seq:{scope_id}"),
    )?
    .unwrap_or(0);
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
    let managed_vault_v2_last_pushed_seq_local_device = local_device_id
        .as_deref()
        .map(|device_id| {
            kv_get_i64(
                conn,
                &format!("managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"),
            )
        })
        .transpose()?
        .flatten();

    let remote_device_seq_map: Option<RemoteDeviceSeqMap> = None;
    let remote_device_seq_map_source: Option<String> = None;
    let remote_probe_error: Option<String> = Some("legacy_remote_probe_removed".to_string());
    let mut managed_vault_v2_remote_generation_id: Option<String> = None;
    let mut managed_vault_v2_remote_latest_global_seq: Option<i64> = None;
    let mut managed_vault_v2_remote_head_error: Option<String> = None;

    if let Some(id_token) = firebase_id_token.map(str::trim).filter(|v| !v.is_empty()) {
        match probe_managed_vault_v2_head(base_url, vault_id, id_token) {
            Ok(response) => {
                let generation_id = response.generation_id.trim();
                if !generation_id.is_empty() {
                    managed_vault_v2_remote_generation_id = Some(generation_id.to_string());
                }
                managed_vault_v2_remote_latest_global_seq =
                    Some(response.remote_latest_global_seq.max(0));
            }
            Err(e) => {
                managed_vault_v2_remote_head_error = Some(e.to_string());
            }
        }
    } else {
        managed_vault_v2_remote_head_error = Some("missing_id_token".to_string());
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
        managed_vault_v2_generation_id,
        managed_vault_v2_last_applied_global_seq,
        managed_vault_v2_last_pushed_seq_local_device,
        managed_vault_checkpoint_token_present,
        managed_vault_last_route,
        managed_vault_last_state,
        blob_repair_queue_depth: blob_repair.queued_count,
        blob_repair_last_attempted_at_ms: blob_repair.last_attempted_at_ms,
        blob_repair_last_error: blob_repair.last_error,
        managed_vault_v2_remote_generation_id,
        managed_vault_v2_remote_latest_global_seq,
        managed_vault_v2_remote_head_error,
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::thread;
    use std::time::{Duration, Instant};

    fn respond_json(stream: &mut TcpStream, status: &str, body: &str) {
        let response = format!(
            "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len(),
        );
        stream
            .write_all(response.as_bytes())
            .expect("write response");
    }

    fn read_http_request(stream: &mut TcpStream) -> (String, Vec<u8>) {
        let mut raw = Vec::new();
        let mut buf = [0u8; 1024];
        let mut header_end = None;
        loop {
            let n = stream.read(&mut buf).expect("read request");
            if n == 0 {
                break;
            }
            raw.extend_from_slice(&buf[..n]);
            if let Some(pos) = raw.windows(4).position(|window| window == b"\r\n\r\n") {
                header_end = Some(pos + 4);
                break;
            }
        }

        let header_end = header_end.expect("header end");
        let headers = String::from_utf8_lossy(&raw[..header_end]).to_string();
        let content_length = headers
            .lines()
            .find_map(|line| {
                let lower = line.to_ascii_lowercase();
                lower
                    .strip_prefix("content-length:")
                    .and_then(|value| value.trim().parse::<usize>().ok())
            })
            .unwrap_or(0);

        let mut body = raw[header_end..].to_vec();
        while body.len() < content_length {
            let n = stream.read(&mut buf).expect("read body");
            if n == 0 {
                break;
            }
            body.extend_from_slice(&buf[..n]);
        }
        (headers, body)
    }

    #[test]
    fn sync_managed_vault_cursor_diagnostics_reports_local_v2_state() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        let base_url = "https://service-vault.secondloop.app";
        let vault_id = "vault-a";
        let scope_id = managed_vault_scope_id(base_url, vault_id);

        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES (?1, ?2), (?3, ?4), (?5, ?6), (?7, ?8)"#,
            params![
                "device_id",
                "device-local",
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "gen-local",
                format!("managed_vault_v2.last_applied_global_seq:{scope_id}"),
                "17",
                format!("managed_vault_v2.last_pushed_seq:{scope_id}:device-local"),
                "5",
            ],
        )
        .expect("seed kv");

        let diagnostics =
            build_managed_vault_cursor_remote_diagnostics(&conn, base_url, vault_id, None)
                .expect("build diagnostics");

        assert_eq!(diagnostics.local_device_id, "device-local");
        assert_eq!(
            diagnostics.managed_vault_v2_generation_id.as_deref(),
            Some("gen-local")
        );
        assert_eq!(diagnostics.managed_vault_v2_last_applied_global_seq, 17);
        assert_eq!(
            diagnostics.managed_vault_v2_last_pushed_seq_local_device,
            Some(5)
        );
        assert_eq!(
            diagnostics.managed_vault_v2_remote_head_error.as_deref(),
            Some("missing_id_token")
        );
    }

    #[test]
    fn sync_managed_vault_cursor_diagnostics_probes_v2_remote_head() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("local addr");
        let server = thread::spawn(move || {
            for _ in 0..1 {
                let (mut stream, _) = listener.accept().expect("accept");
                let (headers, _) = read_http_request(&mut stream);
                let request_line = headers.lines().next().unwrap_or_default().to_string();
                if request_line.starts_with("GET /v2/vaults/test-vault/sync/head ") {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        r#"{"generation_id":"gen-remote","remote_latest_global_seq":23}"#,
                    );
                    continue;
                }
                respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
            }
        });

        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open");
        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES ('device_id', 'device-local')"#,
            [],
        )
        .expect("seed device id");

        let diagnostics = build_managed_vault_cursor_remote_diagnostics(
            &conn,
            &format!("http://{addr}"),
            "test-vault",
            Some("token"),
        )
        .expect("build diagnostics");

        server.join().expect("join");

        assert_eq!(
            diagnostics.managed_vault_v2_remote_generation_id.as_deref(),
            Some("gen-remote")
        );
        assert_eq!(
            diagnostics.managed_vault_v2_remote_latest_global_seq,
            Some(23)
        );
        assert_eq!(diagnostics.managed_vault_v2_remote_head_error, None);
        assert_eq!(diagnostics.remote_device_seq_map, None);
        assert_eq!(diagnostics.remote_device_seq_map_source, None);
        assert_eq!(
            diagnostics.remote_probe_error.as_deref(),
            Some("legacy_remote_probe_removed")
        );
    }

    #[test]
    fn sync_managed_vault_cursor_diagnostics_v2_head_probe_times_out_quickly() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("local addr");
        let server = thread::spawn(move || {
            let (_stream, _) = listener.accept().expect("accept");
            thread::sleep(Duration::from_secs(2));
        });

        let started = Instant::now();
        let result = probe_managed_vault_v2_head(&format!("http://{addr}"), "test-vault", "token");
        let elapsed = started.elapsed();

        server.join().expect("join");

        assert!(result.is_err());
        assert!(
            elapsed < Duration::from_millis(1500),
            "expected timeout before 1500ms, got {elapsed:?}"
        );
    }
}
