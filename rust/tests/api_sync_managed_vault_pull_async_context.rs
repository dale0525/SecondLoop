use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

use secondloop_rust::api::core::sync_managed_vault_pull;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};

fn read_http_request(stream: &mut TcpStream) -> (String, String, Vec<u8>) {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    let header_end = loop {
        let n = stream.read(&mut tmp).expect("read request");
        assert!(n > 0, "unexpected eof while reading request");
        buf.extend_from_slice(&tmp[..n]);
        if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            break pos + 4;
        }
    };

    let headers = String::from_utf8_lossy(&buf[..header_end]).to_string();
    let content_length = headers
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            if name.eq_ignore_ascii_case("content-length") {
                value.trim().parse::<usize>().ok()
            } else {
                None
            }
        })
        .unwrap_or(0);

    let mut body = buf[header_end..].to_vec();
    while body.len() < content_length {
        let n = stream.read(&mut tmp).expect("read request body");
        assert!(n > 0, "unexpected eof while reading request body");
        body.extend_from_slice(&tmp[..n]);
    }

    let first_line = headers.lines().next().unwrap_or("");
    let mut parts = first_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("").to_string();
    (method, path, body)
}

fn respond_json(stream: &mut TcpStream, status_line: &str, body: &str) {
    let response = format!(
        "{status_line}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream
        .write_all(response.as_bytes())
        .expect("write json response");
}

async fn run_pull_inside_async_context() {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("local addr");

    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let (method, path, _body) = read_http_request(&mut stream);
        match (method.as_str(), path.as_str()) {
            ("POST", "/v2/vaults/v1/sync/pull") => {
                respond_json(
                    &mut stream,
                    "HTTP/1.1 200 OK",
                    r#"{"generation_id":"","remote_latest_global_seq":0,"has_more":false,"ops":[]}"#,
                );
            }
            _ => panic!("unexpected request: method={method} path={path}"),
        }
    });

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key =
        auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init password");
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pulled = sync_managed_vault_pull(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        sync_key.to_vec(),
        format!("http://{addr}"),
        "v1".to_string(),
        "token".to_string(),
    )
    .await
    .expect("pull succeeds inside async context");

    assert_eq!(pulled, 0);
    handle.join().expect("join");
}

#[tokio::test(flavor = "multi_thread")]
async fn api_sync_managed_vault_pull_can_run_inside_multi_thread_async_context() {
    run_pull_inside_async_context().await;
}

#[tokio::test(flavor = "current_thread")]
async fn api_sync_managed_vault_pull_can_run_inside_current_thread_async_context() {
    run_pull_inside_async_context().await;
}
