use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

use secondloop_rust::api::core::sync_webdav_test_connection;

fn read_http_headers(stream: &mut std::net::TcpStream) -> String {
    let mut buf = [0u8; 4096];
    let mut out: Vec<u8> = Vec::new();
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

fn respond(stream: &mut std::net::TcpStream, status_line: &str) {
    let resp = format!(
        "{status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    );
    let _ = stream.write_all(resp.as_bytes());
}

#[test]
fn webdav_test_connection_fails_if_root_still_missing_after_mkdir() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();

    let server = thread::spawn(move || {
        let mut handled = 0;
        for stream in listener.incoming() {
            let mut stream = stream.unwrap();
            let headers = read_http_headers(&mut stream);
            let first_line = headers.lines().next().unwrap_or("");
            let method = first_line.split_whitespace().next().unwrap_or("");
            match method {
                "MKCOL" => respond(&mut stream, "HTTP/1.1 405 Method Not Allowed"),
                "PROPFIND" => respond(&mut stream, "HTTP/1.1 404 Not Found"),
                _ => respond(&mut stream, "HTTP/1.1 200 OK"),
            }
            handled += 1;
            if handled >= 2 {
                break;
            }
        }
    });

    let base_url = format!("http://{addr}/dav");
    let err = sync_webdav_test_connection(base_url, None, None, "SecondLoop".to_string())
        .expect_err("expected connection test to fail when root cannot be created");
    let msg = format!("{err:#}");
    assert!(
        msg.contains("not found") || msg.contains("404"),
        "unexpected error message: {msg}"
    );

    let _ = server.join();
}

