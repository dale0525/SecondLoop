use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use reqwest::header::RANGE;
use rusqlite::{params, Connection};
use serde::Deserialize;

use super::runtime::Client;

#[derive(Debug, Deserialize)]
struct ProbeSyncV2PullResponse {
    remote_latest_global_seq: i64,
    ops: Vec<ProbeSyncV2PullOp>,
}

#[derive(Debug, Deserialize)]
struct ProbeSyncV2PullOp {
    device_id: String,
    seq: i64,
}

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
        let fallback = http
            .get(endpoint)
            .bearer_auth(id_token)
            .header(RANGE, "bytes=0-0")
            .send()?;
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

fn local_attachment_sha256s(conn: &Connection) -> Result<Vec<String>> {
    conn.prepare(r#"SELECT sha256 FROM attachments ORDER BY created_at ASC, sha256 ASC"#)?
        .query_map([], |row| row.get(0))?
        .collect::<rusqlite::Result<Vec<String>>>()
        .map_err(Into::into)
}

fn local_embedding_artifact_blob_refs(conn: &Connection) -> Result<Vec<String>> {
    crate::db::list_distinct_embedding_artifact_blob_refs(conn)
}

const MAX_FRESH_DEVICE_REMOTE_BYTE_PROBES: i64 = 10;

fn local_attachment_count(conn: &Connection) -> Result<i64> {
    conn.query_row(r#"SELECT count(*) FROM attachments"#, [], |row| row.get(0))
        .map_err(Into::into)
}

fn local_ready_embedding_artifact_blob_ref_count(conn: &Connection) -> Result<i64> {
    conn.query_row(
        r#"SELECT count(DISTINCT blob_ref)
           FROM embedding_artifact_manifests
           WHERE status = 'ready'"#,
        [],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn exceeds_fresh_device_remote_byte_probe_budget(conn: &Connection) -> Result<bool> {
    let attachment_count = local_attachment_count(conn)?.max(0);
    if attachment_count > MAX_FRESH_DEVICE_REMOTE_BYTE_PROBES {
        return Ok(true);
    }
    let artifact_count = local_ready_embedding_artifact_blob_ref_count(conn)?.max(0);
    Ok(attachment_count.saturating_add(artifact_count) > MAX_FRESH_DEVICE_REMOTE_BYTE_PROBES)
}

fn local_remote_op_sequences(
    conn: &Connection,
    device_id: &str,
) -> Result<BTreeMap<String, Vec<i64>>> {
    let mut out = BTreeMap::new();
    let mut stmt = conn.prepare(
        r#"SELECT device_id, seq
           FROM oplog
           WHERE device_id != ?1
           ORDER BY device_id ASC, seq ASC"#,
    )?;
    let mut rows = stmt.query(params![device_id])?;
    while let Some(row) = rows.next()? {
        let remote_device_id: String = row.get(0)?;
        let seq: i64 = row.get(1)?;
        out.entry(remote_device_id)
            .or_insert_with(Vec::new)
            .push(seq);
    }
    Ok(out)
}

pub(super) fn managed_remote_metadata_matches_local_snapshot(
    conn: &Connection,
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<bool> {
    let expected_by_device = local_remote_op_sequences(conn, device_id)?;
    if expected_by_device.is_empty() {
        return Ok(false);
    }

    let expected_total: usize = expected_by_device.values().map(Vec::len).sum();
    let limit = i64::try_from(expected_total).map_err(|_| anyhow!("too_many_expected_ops"))?;
    let endpoint = super::runtime::url(base_url, &format!("/v2/vaults/{vault_id}/sync/pull"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&serde_json::json!({
            "after_global_seq": 0,
            "limit": limit,
        }))
        .send()?;
    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().unwrap_or_default();
        return Err(anyhow!(
            "managed-vault probe metadata failed: HTTP {status} {text}"
        ));
    }
    let parsed: ProbeSyncV2PullResponse = resp.json()?;
    if parsed.remote_latest_global_seq != expected_total as i64 {
        return Ok(false);
    }
    if parsed.ops.len() != expected_total {
        return Ok(false);
    }

    let mut actual_by_device: BTreeMap<String, Vec<i64>> = BTreeMap::new();
    for op in parsed.ops {
        actual_by_device
            .entry(op.device_id)
            .or_default()
            .push(op.seq);
    }

    Ok(actual_by_device == expected_by_device)
}

pub(super) fn can_skip_fresh_device_full_push(
    conn: &Connection,
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<bool> {
    if !managed_remote_metadata_matches_local_snapshot(
        conn, http, base_url, vault_id, id_token, device_id,
    )? {
        return Ok(false);
    }
    if exceeds_fresh_device_remote_byte_probe_budget(conn)? {
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

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};
    use std::thread;
    use std::time::Duration;

    use super::*;
    use reqwest::blocking::ClientBuilder;

    #[derive(Default)]
    struct ServerState {
        saw_head: bool,
        saw_get: bool,
        saw_range: Option<String>,
    }

    fn read_http_headers(stream: &mut std::net::TcpStream) -> String {
        let mut out = Vec::new();
        let mut buf = [0u8; 1024];
        loop {
            let n = stream.read(&mut buf).unwrap_or(0);
            if n == 0 {
                break;
            }
            out.extend_from_slice(&buf[..n]);
            if out.windows(4).any(|w| w == b"\r\n\r\n") {
                break;
            }
            if out.len() > 32 * 1024 {
                break;
            }
        }
        String::from_utf8_lossy(&out).to_string()
    }

    fn respond(stream: &mut std::net::TcpStream, status_line: &str, body: &[u8]) {
        let headers = format!(
            "{status_line}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            body.len()
        );
        stream.write_all(headers.as_bytes()).expect("write headers");
        stream.write_all(body).expect("write body");
    }

    #[test]
    fn large_local_media_sets_exceed_fresh_device_probe_budget() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];

        for idx in 0..11 {
            let bytes = format!("attachment-{idx}").into_bytes();
            let _attachment =
                crate::db::insert_attachment(&conn, &db_key, dir.path(), &bytes, "image/png")
                    .expect("insert attachment");
        }

        assert!(exceeds_fresh_device_remote_byte_probe_budget(&conn).expect("probe budget"));
    }

    #[test]
    fn managed_remote_attachment_exists_uses_range_get_when_head_is_unsupported() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("local addr");
        let state = Arc::new(Mutex::new(ServerState::default()));
        let state_clone = Arc::clone(&state);

        let handle = thread::spawn(move || {
            for _ in 0..8 {
                let (mut stream, _) = listener.accept().expect("accept");
                stream
                    .set_read_timeout(Some(Duration::from_secs(30)))
                    .expect("set read timeout");
                let headers = read_http_headers(&mut stream);
                let first_line = headers.lines().next().unwrap_or("");
                let mut parts = first_line.split_whitespace();
                let method = parts.next().unwrap_or("");
                let path = parts.next().unwrap_or("");

                match (method, path) {
                    ("HEAD", "/v1/vaults/v1/attachments/abc") => {
                        state_clone.lock().expect("lock").saw_head = true;
                        respond(&mut stream, "HTTP/1.1 405 Method Not Allowed", b"");
                    }
                    ("GET", "/v1/vaults/v1/attachments/abc") => {
                        let range = headers.lines().find_map(|line| {
                            let (name, value) = line.split_once(':')?;
                            if name.eq_ignore_ascii_case("range") {
                                Some(value.trim().to_string())
                            } else {
                                None
                            }
                        });
                        let mut st = state_clone.lock().expect("lock");
                        st.saw_get = true;
                        st.saw_range = range;
                        drop(st);
                        respond(&mut stream, "HTTP/1.1 206 Partial Content", b"x");
                        return;
                    }
                    _ => {
                        respond(&mut stream, "HTTP/1.1 404 Not Found", b"");
                    }
                }
            }

            panic!("expected HEAD then GET probe requests before server loop ended");
        });

        let http = ClientBuilder::new()
            .timeout(Duration::from_secs(30))
            .pool_max_idle_per_host(0)
            .build()
            .expect("http client");
        let exists = managed_remote_attachment_exists(
            &http,
            &format!("http://{addr}"),
            "v1",
            "token",
            "abc",
        )
        .expect("exists");

        assert!(exists);
        let st = state.lock().expect("lock");
        assert!(st.saw_head);
        assert!(st.saw_get);
        assert_eq!(st.saw_range.as_deref(), Some("bytes=0-0"));
        drop(st);
        handle.join().expect("join");
    }
}
