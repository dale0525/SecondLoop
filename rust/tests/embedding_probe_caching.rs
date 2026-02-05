use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{api, auth, db, embedding};

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::Duration;

#[derive(Debug, Clone)]
struct CapturedEmbeddingRequest {
    inputs: Vec<String>,
}

fn read_http_request(stream: &mut TcpStream) -> (String, HashMap<String, String>, String) {
    let mut buf = [0u8; 16384];
    let n = stream.read(&mut buf).expect("read");
    let req_text = String::from_utf8_lossy(&buf[..n]).to_string();

    let (headers_text, rest) = req_text.split_once("\r\n\r\n").expect("split headers/body");
    let mut lines = headers_text.split("\r\n");
    let first_line = lines.next().expect("request line");
    let mut first_parts = first_line.split_whitespace();
    let _method = first_parts.next().unwrap_or_default();
    let path = first_parts.next().unwrap_or_default().to_string();

    let mut headers: HashMap<String, String> = HashMap::new();
    for line in lines {
        let Some((k, v)) = line.split_once(':') else {
            continue;
        };
        headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
    }

    let content_length: usize = headers
        .get("content-length")
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(0);

    let mut body_bytes = rest.as_bytes().to_vec();
    while body_bytes.len() < content_length {
        let mut tmp = [0u8; 8192];
        let m = stream.read(&mut tmp).expect("read body");
        if m == 0 {
            break;
        }
        body_bytes.extend_from_slice(&tmp[..m]);
    }
    body_bytes.truncate(content_length);
    let body = String::from_utf8_lossy(&body_bytes).to_string();

    (path, headers, body)
}

fn parse_inputs_from_body(body: &str) -> Vec<String> {
    let parsed: serde_json::Value = match serde_json::from_str(body) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };
    parsed
        .get("input")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default()
}

fn build_openai_embeddings_response(dim: usize, count: usize) -> String {
    let data: Vec<serde_json::Value> = (0..count)
        .map(|i| {
            let embedding: Vec<f32> = vec![i as f32; dim];
            serde_json::json!({
                "index": i,
                "embedding": embedding,
            })
        })
        .collect();
    serde_json::json!({ "data": data }).to_string()
}

struct EmbeddingsServer {
    base_url: String,
    stop: Arc<AtomicBool>,
    rx: mpsc::Receiver<CapturedEmbeddingRequest>,
    handle: Option<thread::JoinHandle<()>>,
}

impl EmbeddingsServer {
    fn start(expected_path: &'static str, model_id_header: &'static str, dim: usize) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        listener.set_nonblocking(true).expect("nonblocking");

        let (tx, rx) = mpsc::channel::<CapturedEmbeddingRequest>();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = stop.clone();
        let expected_path = expected_path.to_string();
        let model_id_header = model_id_header.to_string();

        let handle = thread::spawn(move || {
            while !stop2.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        let (path, _headers, body) = read_http_request(&mut stream);
                        if path != expected_path {
                            panic!("unexpected path: {path} (expected {expected_path})");
                        }

                        let inputs = parse_inputs_from_body(&body);
                        let _ = tx.send(CapturedEmbeddingRequest {
                            inputs: inputs.clone(),
                        });

                        let count = inputs.len();
                        let resp_body = build_openai_embeddings_response(dim, count);
                        let resp = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nx-secondloop-embedding-model-id: {model_id_header}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{resp_body}",
                            resp_body.len()
                        );
                        let _ = stream.write_all(resp.as_bytes());
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(5));
                    }
                    Err(_) => break,
                }
            }
        });

        Self {
            base_url: format!("http://{addr}"),
            stop,
            rx,
            handle: Some(handle),
        }
    }

    fn finish(mut self) -> Vec<CapturedEmbeddingRequest> {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
        self.rx.try_iter().collect()
    }
}

impl Drop for EmbeddingsServer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

#[test]
fn cloud_gateway_todo_thread_indexing_skips_probe_when_cached() {
    let server = EmbeddingsServer::start("/v1/embeddings", "test-embed@v1", 3);

    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    db::upsert_todo(
        &conn, &key, "todo_1", "Buy milk", None, "open", None, None, None, None,
    )
    .expect("upsert todo");
    db::append_todo_note(&conn, &key, "todo_1", "Remember oat milk", None).expect("note");

    let processed1 = api::core::db_process_pending_todo_thread_embeddings_cloud_gateway(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        32,
        64,
        server.base_url.clone(),
        "test-id-token".to_string(),
        "test-embed".to_string(),
    )
    .expect("process1");
    assert!(processed1 > 0);

    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME)
        .expect("switch active");

    let processed2 = api::core::db_process_pending_todo_thread_embeddings_cloud_gateway(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        32,
        64,
        server.base_url.clone(),
        "test-id-token".to_string(),
        "test-embed".to_string(),
    )
    .expect("process2");
    assert_eq!(processed2, 0);

    let requests = server.finish();
    let probe_count = requests
        .iter()
        .filter(|r| r.inputs.len() == 1 && r.inputs[0] == "probe")
        .count();
    assert_eq!(probe_count, 1, "requests={requests:?}");
    assert_eq!(requests.len(), 3, "requests={requests:?}");
}

#[test]
fn brok_todo_thread_indexing_skips_probe_when_dim_cached() {
    let server = EmbeddingsServer::start("/embeddings", "test-embed@v1", 3);

    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    db::create_embedding_profile(
        &conn,
        &key,
        "test",
        "openai-compatible",
        Some(&server.base_url),
        Some("test-api-key"),
        "test-embed",
        true,
    )
    .expect("create profile");

    db::upsert_todo(
        &conn, &key, "todo_1", "Buy milk", None, "open", None, None, None, None,
    )
    .expect("upsert todo");
    db::append_todo_note(&conn, &key, "todo_1", "Remember oat milk", None).expect("note");

    let processed1 = api::core::db_process_pending_todo_thread_embeddings_brok(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        32,
        64,
    )
    .expect("process1");
    assert!(processed1 > 0);

    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME)
        .expect("switch active");

    let processed2 = api::core::db_process_pending_todo_thread_embeddings_brok(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        32,
        64,
    )
    .expect("process2");
    assert_eq!(processed2, 0);

    let requests = server.finish();
    let probe_count = requests
        .iter()
        .filter(|r| r.inputs.len() == 1 && r.inputs[0] == "probe")
        .count();
    assert_eq!(probe_count, 1, "requests={requests:?}");
    assert_eq!(requests.len(), 3, "requests={requests:?}");
}
