use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;

#[derive(Default)]
pub struct V2ServerState {
    pub generation_id: String,
    pub latest_global_seq: i64,
    pub ops: Vec<serde_json::Value>,
    pub attachments: BTreeMap<String, Vec<u8>>,
    pub requests: Vec<String>,
    pub require_generation_for_push_without_id: bool,
    pub invalid_batch_once: bool,
    pub partial_accept_count_once: Option<usize>,
    pub gap_pull_once_after_global_seq: Option<i64>,
    pub reset_required_once_after_global_seq: Option<i64>,
    pub pull_page_size: Option<usize>,
    pub switch_generation_once_after_global_seq: Option<i64>,
    pub switch_generation_id: Option<String>,
    pub switch_generation_latest_global_seq: Option<i64>,
    pub switch_generation_ops: Vec<serde_json::Value>,
}

fn read_request(stream: &mut TcpStream) -> (String, String, String, Vec<u8>) {
    let mut buf = Vec::<u8>::new();
    let mut header_end = None;
    let mut tmp = [0u8; 4096];

    while header_end.is_none() {
        let n = stream.read(&mut tmp).expect("read");
        assert!(n > 0, "unexpected EOF");
        buf.extend_from_slice(&tmp[..n]);
        header_end = buf.windows(4).position(|w| w == b"\r\n\r\n").map(|p| p + 4);
    }

    let header_end = header_end.expect("header end");
    let (headers, rest) = buf.split_at(header_end);
    let headers_str = String::from_utf8_lossy(headers).to_string();

    let mut lines = headers_str.lines();
    let request_line = lines.next().expect("request line");
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("").to_string();

    let mut content_length = 0usize;
    for line in lines {
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-length") {
                content_length = value.trim().parse::<usize>().unwrap_or(0);
            }
        }
    }

    let mut body = rest.to_vec();
    while body.len() < content_length {
        let n = stream.read(&mut tmp).expect("read body");
        assert!(n > 0, "unexpected eof body");
        body.extend_from_slice(&tmp[..n]);
    }
    body.truncate(content_length);

    (headers_str, method, path, body)
}

fn write_json_response(stream: &mut TcpStream, status: u16, body: serde_json::Value) {
    let body_str = body.to_string();
    let status_text = match status {
        200 => "OK",
        404 => "Not Found",
        _ => "OK",
    };
    let response = format!(
        "HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    stream
        .write_all(response.as_bytes())
        .expect("write response");
}

pub fn start_mock_v2_server() -> (
    String,
    mpsc::Sender<()>,
    Arc<Mutex<V2ServerState>>,
    thread::JoinHandle<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    listener.set_nonblocking(true).expect("nonblocking");
    let addr = listener.local_addr().expect("local addr");

    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let state = Arc::new(Mutex::new(V2ServerState {
        generation_id: "generation-a".to_string(),
        ..V2ServerState::default()
    }));
    let state_clone = Arc::clone(&state);

    let handle = thread::spawn(move || loop {
        if stop_rx.try_recv().is_ok() {
            break;
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_nonblocking(false).expect("blocking stream");
                let (raw_headers, method, path, body) = read_request(&mut stream);
                state_clone
                    .lock()
                    .expect("lock")
                    .requests
                    .push(format!("{raw_headers}{}", String::from_utf8_lossy(&body)));

                match (method.as_str(), path.as_str()) {
                    ("GET", "/v2/vaults/v1/sync/head") => {
                        let state = state_clone.lock().expect("lock");
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": state.latest_global_seq,
                            }),
                        );
                    }
                    ("POST", "/v2/vaults/v1/sync/push") => {
                        let decoded: serde_json::Value =
                            serde_json::from_slice(&body).expect("push json");
                        let incoming = decoded["ops"].as_array().cloned().expect("ops array");
                        let mut state = state_clone.lock().expect("lock");
                        let client_generation = decoded["generation_id"]
                            .as_str()
                            .unwrap_or("")
                            .trim()
                            .to_string();
                        if state.invalid_batch_once {
                            state.invalid_batch_once = false;
                            write_json_response(
                                &mut stream,
                                400,
                                serde_json::json!({
                                    "error": "invalid_batch",
                                    "reason": "malformed_op",
                                }),
                            );
                            continue;
                        }
                        let partial_accept_count = state
                            .partial_accept_count_once
                            .take()
                            .map(|count| count.min(incoming.len()));
                        if client_generation.is_empty()
                            && state.require_generation_for_push_without_id
                        {
                            write_json_response(
                                &mut stream,
                                409,
                                serde_json::json!({
                                    "error": "generation_required",
                                    "remote_generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq,
                                }),
                            );
                            continue;
                        }
                        if !client_generation.is_empty() && client_generation != state.generation_id
                        {
                            write_json_response(
                                &mut stream,
                                409,
                                serde_json::json!({
                                    "error": "generation_mismatch",
                                    "remote_generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq,
                                }),
                            );
                            continue;
                        }
                        let from_seq = state.latest_global_seq + 1;
                        let accepted_ops = partial_accept_count.unwrap_or(incoming.len());
                        for op in incoming.into_iter().take(accepted_ops) {
                            state.latest_global_seq += 1;
                            let mut value = op;
                            value["global_seq"] = serde_json::Value::from(state.latest_global_seq);
                            state.ops.push(value);
                        }
                        let committed_to_seq = if accepted_ops > 0 {
                            Some(state.latest_global_seq)
                        } else {
                            None
                        };
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "accepted": accepted_ops,
                                "committed_from_seq": if accepted_ops > 0 { Some(from_seq) } else { None },
                                "committed_to_seq": committed_to_seq,
                                "remote_latest_global_seq": state.latest_global_seq,
                            }),
                        );
                    }
                    ("POST", "/v2/vaults/v1/sync/reset") => {
                        let mut state = state_clone.lock().expect("lock");
                        state.generation_id = "generation-reset".to_string();
                        state.latest_global_seq = 0;
                        state.ops.clear();
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": 0,
                                "deleted_meta": 0,
                                "deleted_blobs": 0,
                            }),
                        );
                    }
                    ("POST", "/v2/vaults/v1/sync/pull") => {
                        let decoded: serde_json::Value =
                            serde_json::from_slice(&body).expect("pull json");
                        let after = decoded["after_global_seq"].as_i64().unwrap_or(0);
                        let limit = decoded["limit"].as_u64().unwrap_or(100) as usize;
                        let mut state = state_clone.lock().expect("lock");
                        if state.reset_required_once_after_global_seq == Some(after) {
                            state.reset_required_once_after_global_seq = None;
                            write_json_response(
                                &mut stream,
                                409,
                                serde_json::json!({
                                    "error": "reset_required",
                                    "reason": "global_log_gap",
                                    "remote_generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq,
                                }),
                            );
                            continue;
                        }
                        if state.gap_pull_once_after_global_seq == Some(after) {
                            state.gap_pull_once_after_global_seq = None;
                            let gap_ops = state
                                .ops
                                .iter()
                                .filter(|item| item["global_seq"].as_i64().unwrap_or(0) > after)
                                .map(|item| {
                                    let mut value = item.clone();
                                    let current = value["global_seq"].as_i64().unwrap_or(0);
                                    value["global_seq"] = serde_json::Value::from(current + 1);
                                    value
                                })
                                .collect::<Vec<_>>();
                            write_json_response(
                                &mut stream,
                                200,
                                serde_json::json!({
                                    "generation_id": state.generation_id,
                                    "remote_latest_global_seq": state.latest_global_seq + 1,
                                    "has_more": false,
                                    "ops": gap_ops,
                                }),
                            );
                            continue;
                        }
                        if state.switch_generation_once_after_global_seq == Some(after) {
                            state.switch_generation_once_after_global_seq = None;
                            state.generation_id =
                                state.switch_generation_id.take().unwrap_or_default();
                            state.latest_global_seq = state
                                .switch_generation_latest_global_seq
                                .take()
                                .unwrap_or(0);
                            state.ops = std::mem::take(&mut state.switch_generation_ops);
                        }
                        let page_size = state.pull_page_size.unwrap_or(limit).max(1);
                        let all_ops: Vec<serde_json::Value> = state
                            .ops
                            .iter()
                            .filter(|item| item["global_seq"].as_i64().unwrap_or(0) > after)
                            .cloned()
                            .collect();
                        let has_more = all_ops.len() > page_size;
                        let ops: Vec<serde_json::Value> =
                            all_ops.into_iter().take(page_size).collect();
                        write_json_response(
                            &mut stream,
                            200,
                            serde_json::json!({
                                "generation_id": state.generation_id,
                                "remote_latest_global_seq": state.latest_global_seq,
                                "has_more": has_more,
                                "ops": ops,
                            }),
                        );
                    }
                    ("GET", path) if path.starts_with("/v1/vaults/v1/attachments/") => {
                        let artifact_id = path
                            .strip_prefix("/v1/vaults/v1/attachments/")
                            .unwrap_or_default()
                            .to_string();
                        let state = state_clone.lock().expect("lock");
                        if let Some(bytes) = state.attachments.get(&artifact_id) {
                            let response = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                bytes.len()
                            );
                            stream
                                .write_all(response.as_bytes())
                                .expect("write headers");
                            stream.write_all(bytes).expect("write body");
                        } else {
                            write_json_response(
                                &mut stream,
                                404,
                                serde_json::json!({ "error": "not_found" }),
                            );
                        }
                    }
                    ("PUT", path) if path.starts_with("/v1/vaults/v1/attachments/") => {
                        let artifact_id = path
                            .strip_prefix("/v1/vaults/v1/attachments/")
                            .unwrap_or_default()
                            .to_string();
                        let mut state = state_clone.lock().expect("lock");
                        state.attachments.insert(artifact_id, body);
                        write_json_response(&mut stream, 200, serde_json::json!({}));
                    }
                    ("DELETE", path) if path.starts_with("/v1/vaults/v1/attachments/") => {
                        let artifact_id = path
                            .strip_prefix("/v1/vaults/v1/attachments/")
                            .unwrap_or_default()
                            .to_string();
                        let mut state = state_clone.lock().expect("lock");
                        state.attachments.remove(&artifact_id);
                        write_json_response(&mut stream, 200, serde_json::json!({}));
                    }
                    _ => write_json_response(
                        &mut stream,
                        404,
                        serde_json::json!({ "error": "not_found" }),
                    ),
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(5));
            }
            Err(error) => panic!("accept failed: {error}"),
        }
    });

    (format!("http://{addr}"), stop_tx, state, handle)
}

pub fn managed_vault_v2_scope_id(base_url: &str, vault_id: &str) -> String {
    B64_URL.encode(format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim()).as_bytes())
}
