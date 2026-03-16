use std::collections::BTreeMap;

use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use reqwest::header::RANGE;
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

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};
    use std::thread;
    use std::time::{Duration, Instant};

    use super::*;

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
    fn managed_remote_attachment_exists_uses_range_get_when_head_is_unsupported() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        listener.set_nonblocking(true).expect("nonblocking");
        let addr = listener.local_addr().expect("local addr");
        let state = Arc::new(Mutex::new(ServerState::default()));
        let state_clone = Arc::clone(&state);

        let handle = thread::spawn(move || {
            let started = Instant::now();
            while started.elapsed() < Duration::from_secs(2) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
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
                                break;
                            }
                            _ => {
                                respond(&mut stream, "HTTP/1.1 404 Not Found", b"");
                            }
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(e) => panic!("accept failed: {e}"),
                }
            }
        });

        let http = Client::new();
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
