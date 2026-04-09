use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use secondloop_rust::api::{audio_transcribe, core};
use secondloop_rust::db;

fn read_http_request(stream: &mut std::net::TcpStream) -> String {
    stream
        .set_read_timeout(Some(Duration::from_millis(200)))
        .expect("set read timeout");

    let mut request = Vec::<u8>::new();
    let mut buf = [0u8; 8192];
    let mut expected_total_len: Option<usize> = None;

    loop {
        match stream.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                request.extend_from_slice(&buf[..n]);
                if expected_total_len.is_none() {
                    if let Some(headers_end) = request
                        .windows(4)
                        .position(|window| window == b"\r\n\r\n")
                        .map(|index| index + 4)
                    {
                        let headers = String::from_utf8_lossy(&request[..headers_end]);
                        let content_length = headers
                            .lines()
                            .find_map(|line| {
                                let (name, value) = line.split_once(':')?;
                                if !name.trim().eq_ignore_ascii_case("content-length") {
                                    return None;
                                }
                                value.trim().parse::<usize>().ok()
                            })
                            .unwrap_or(0);
                        expected_total_len = Some(headers_end + content_length);
                    }
                }

                if let Some(total_len) = expected_total_len {
                    if request.len() >= total_len {
                        break;
                    }
                }
            }
            Err(err)
                if matches!(
                    err.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) =>
            {
                if !request.is_empty() {
                    break;
                }
            }
            Err(err) => panic!("read request: {err}"),
        }
    }

    String::from_utf8_lossy(&request).to_string()
}

fn start_one_shot_server(
    body: String,
    content_type: &'static str,
) -> (String, mpsc::Receiver<String>, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");
    let (tx, rx) = mpsc::channel::<String>();

    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let _ = tx.send(read_http_request(&mut stream));

        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(resp.as_bytes()).expect("write response");
    });

    (format!("http://{}/v1", addr), rx, handle)
}

fn prepare_profile(base_url: String) -> (String, Vec<u8>, String, tempfile::TempDir) {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir_str = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir_str.clone(), "pw".to_string())
        .expect("init master password");

    let profile = core::db_create_llm_profile(
        app_dir_str.clone(),
        key.clone(),
        "Audio".to_string(),
        "openai-compatible".to_string(),
        Some(base_url),
        Some("sk-test".to_string()),
        "gpt-4o-mini".to_string(),
        true,
    )
    .expect("create profile");

    (app_dir_str, key, profile.id, temp_dir)
}

#[test]
fn byok_audio_transcribe_multimodal_streams_and_parses_sse() {
    let response_body = concat!(
        "data: {\"choices\":[{\"delta\":{\"content\":\"hello from multimodal stream\"}}]}\n\n",
        "data: {\"usage\":{\"prompt_tokens\":9,\"completion_tokens\":3,\"total_tokens\":12}}\n\n",
        "data: [DONE]\n\n"
    )
    .to_string();

    let (base_url, req_rx, handle) = start_one_shot_server(response_body, "text/event-stream");
    let (app_dir, key, profile_id, _temp_dir) = prepare_profile(base_url);

    let local_day = "2026-02-04".to_string();
    let payload = audio_transcribe::audio_transcribe_byok_profile_multimodal(
        app_dir.clone(),
        key.clone(),
        profile_id.clone(),
        local_day.clone(),
        "en".to_string(),
        "audio/mp4".to_string(),
        vec![0x00, 0x00, 0x00, 0x18],
    )
    .expect("transcribe multimodal");

    let decoded: serde_json::Value = serde_json::from_str(&payload).expect("valid payload json");
    assert_eq!(
        decoded
            .get("text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "hello from multimodal stream"
    );

    handle.join().expect("join server thread");

    let req = req_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("receive request");
    let req_lower = req.to_ascii_lowercase();
    assert!(req_lower.contains("post /v1/chat/completions"));
    assert!(req_lower.contains("authorization: bearer sk-test"));
    assert!(req_lower.contains("\"stream\":true"));
    assert!(req_lower.contains("\"stream_options\":{\"include_usage\":true}"));

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    let row: (i64, i64, i64, i64, i64) = conn
        .query_row(
            r#"SELECT requests, requests_with_usage, input_tokens, output_tokens, total_tokens
               FROM llm_usage_daily
               WHERE day = ?1 AND profile_id = ?2 AND purpose = 'audio_transcribe'"#,
            [&local_day, &profile_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .expect("usage row");
    assert_eq!(row.0, 1);
    assert_eq!(row.1, 1);
    assert_eq!(row.2, 9);
    assert_eq!(row.3, 3);
    assert_eq!(row.4, 12);
}

#[test]
fn byok_audio_transcribe_whisper_sets_stream_form_field() {
    let response_body = concat!(
        "data: {\"text\":\"hello whisper stream\",\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}\n\n",
        "data: [DONE]\n\n"
    )
    .to_string();

    let (base_url, req_rx, handle) = start_one_shot_server(response_body, "text/event-stream");
    let (app_dir, key, profile_id, _temp_dir) = prepare_profile(base_url);

    let local_day = "2026-02-05".to_string();
    let payload = audio_transcribe::audio_transcribe_byok_profile(
        app_dir.clone(),
        key.clone(),
        profile_id.clone(),
        local_day.clone(),
        "en".to_string(),
        "audio/mp4".to_string(),
        vec![0x00, 0x00, 0x00, 0x18],
    )
    .expect("transcribe whisper");

    let decoded: serde_json::Value = serde_json::from_str(&payload).expect("valid payload json");
    assert_eq!(
        decoded
            .get("text")
            .and_then(|v| v.as_str())
            .unwrap_or_default(),
        "hello whisper stream"
    );

    handle.join().expect("join server thread");

    let req = req_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("receive request");
    let req_lower = req.to_ascii_lowercase();
    assert!(req_lower.contains("post /v1/audio/transcriptions"));
    assert!(req_lower.contains("authorization: bearer sk-test"));
    assert!(req.contains("name=\"stream\""));
    assert!(req_lower.contains("\r\n\r\ntrue\r\n"));

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    let row: (i64, i64, i64, i64, i64) = conn
        .query_row(
            r#"SELECT requests, requests_with_usage, input_tokens, output_tokens, total_tokens
               FROM llm_usage_daily
               WHERE day = ?1 AND profile_id = ?2 AND purpose = 'audio_transcribe'"#,
            [&local_day, &profile_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .expect("usage row");
    assert_eq!(row.0, 1);
    assert_eq!(row.1, 1);
    assert_eq!(row.2, 5);
    assert_eq!(row.3, 2);
    assert_eq!(row.4, 7);
}
