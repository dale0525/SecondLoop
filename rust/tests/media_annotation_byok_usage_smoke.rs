use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use secondloop_rust::api::{core, media_annotation};
use secondloop_rust::db;

fn start_one_shot_server(
    body: String,
    content_type: &'static str,
) -> (String, mpsc::Receiver<String>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (tx, rx) = mpsc::channel::<String>();

    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let mut buf = [0u8; 8192];
        let n = stream.read(&mut buf).unwrap_or(0);
        let _ = tx.send(String::from_utf8_lossy(&buf[..n]).to_string());

        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(resp.as_bytes()).expect("write response");
    });

    (format!("http://{}/v1", addr), rx, handle)
}

#[test]
fn byok_media_annotation_records_usage() {
    let response_body = serde_json::json!({
        "choices": [{
            "message": {
                "content": "{\"summary\":\"hello\",\"tag\":[],\"full_text\":\"\"}"
            }
        }],
        "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 5,
            "total_tokens": 15
        }
    })
    .to_string();

    let (base_url, req_rx, handle) = start_one_shot_server(response_body, "application/json");

    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir_str = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir_str.clone(), "pw".to_string())
        .expect("init master password");

    let profile = core::db_create_llm_profile(
        app_dir_str.clone(),
        key.clone(),
        "Vision".to_string(),
        "openai-compatible".to_string(),
        Some(base_url.clone()),
        Some("sk-test".to_string()),
        "gpt-4o-mini".to_string(),
        true,
    )
    .expect("create profile");

    let local_day = "2026-02-04".to_string();
    let payload = media_annotation::media_annotation_byok_profile(
        app_dir_str.clone(),
        key.clone(),
        profile.id.clone(),
        local_day.clone(),
        "en".to_string(),
        "image/jpeg".to_string(),
        b"img".to_vec(),
    )
    .expect("annotate");
    assert!(payload.contains("\"summary\""));
    assert!(payload.contains("\"full_text\""));
    assert!(payload.contains("\"tag\""));

    handle.join().expect("join server thread");

    let req = req_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("receive request");
    let req_lower = req.to_ascii_lowercase();
    assert!(req_lower.contains("post /v1/chat/completions"));
    assert!(req_lower.contains("authorization: bearer sk-test"));
    assert!(req_lower.contains("\"type\":\"image_url\""));
    assert!(req_lower.contains("data:image/jpeg;base64,"));
    assert!(req_lower.contains("summary (string)"));
    assert!(req_lower.contains("full_text (string)"));
    assert!(req_lower.contains("tag (array of strings)"));
    assert!(req_lower.contains("\"stream\":true"));

    let conn = db::open(std::path::Path::new(&app_dir_str)).expect("open db");
    let row: (i64, i64, i64, i64, i64) = conn
        .query_row(
            r#"SELECT requests, requests_with_usage, input_tokens, output_tokens, total_tokens
               FROM llm_usage_daily
               WHERE day = ?1 AND profile_id = ?2 AND purpose = 'media_annotation'"#,
            [&local_day, &profile.id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .expect("usage row");
    assert_eq!(row.0, 1);
    assert_eq!(row.1, 1);
    assert_eq!(row.2, 10);
    assert_eq!(row.3, 5);
    assert_eq!(row.4, 15);
}
