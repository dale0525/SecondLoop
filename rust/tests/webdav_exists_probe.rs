use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use secondloop_rust::sync::{self, webdav::WebDavRemoteStore};

#[derive(Default)]
struct ServerState {
    head_count: usize,
    get_count: usize,
    propfind_count: usize,
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

fn respond(stream: &mut std::net::TcpStream, status_line: &str) {
    let resp = format!("{status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
    let _ = stream.write_all(resp.as_bytes());
}

fn respond_xml(stream: &mut std::net::TcpStream, status_line: &str, body: &str) {
    let resp = format!(
        "{status_line}\r\nContent-Type: application/xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let _ = stream.write_all(resp.as_bytes());
}

fn start_server(
    head_status: &'static str,
    expected_requests: usize,
) -> (String, Arc<Mutex<ServerState>>, thread::JoinHandle<()>) {
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
                        ("HEAD", "/dav/SecondLoop/attachments/existing.bin") => {
                            let mut st = state_clone.lock().expect("lock");
                            st.head_count += 1;
                            drop(st);
                            respond(&mut stream, head_status);
                        }
                        ("PROPFIND", "/dav/SecondLoop/attachments/existing.bin") => {
                            let mut st = state_clone.lock().expect("lock");
                            st.propfind_count += 1;
                            drop(st);
                            let xml = r#"<?xml version="1.0" encoding="utf-8" ?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/SecondLoop/attachments/existing.bin</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
"#;
                            respond_xml(&mut stream, "HTTP/1.1 207 Multi-Status", xml);
                        }
                        ("GET", "/dav/SecondLoop/attachments/existing.bin") => {
                            let mut st = state_clone.lock().expect("lock");
                            st.get_count += 1;
                            drop(st);
                            respond(&mut stream, "HTTP/1.1 500 Unexpected GET");
                        }
                        _ => respond(&mut stream, "HTTP/1.1 404 Not Found"),
                    }

                    let st = state_clone.lock().expect("lock");
                    if st.head_count + st.propfind_count + st.get_count >= expected_requests {
                        break;
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(10));
                }
                Err(e) => panic!("accept failed: {e}"),
            }
        }
    });

    (format!("http://{addr}/dav"), state, handle)
}

#[test]
fn webdav_exists_uses_head_without_getting_body() {
    let (base_url, state, handle) = start_server("HTTP/1.1 200 OK", 1);
    let remote = WebDavRemoteStore::new(base_url, None, None).expect("remote");

    let exists = <WebDavRemoteStore as sync::RemoteStore>::exists(
        &remote,
        "/SecondLoop/attachments/existing.bin",
    )
    .expect("exists");

    assert!(exists);
    let st = state.lock().expect("lock");
    assert_eq!(st.head_count, 1);
    assert_eq!(st.propfind_count, 0);
    assert_eq!(st.get_count, 0);
    drop(st);
    handle.join().expect("join");
}

#[test]
fn webdav_exists_falls_back_to_propfind_without_getting_body() {
    let (base_url, state, handle) = start_server("HTTP/1.1 405 Method Not Allowed", 2);
    let remote = WebDavRemoteStore::new(base_url, None, None).expect("remote");

    let exists = <WebDavRemoteStore as sync::RemoteStore>::exists(
        &remote,
        "/SecondLoop/attachments/existing.bin",
    )
    .expect("exists");

    assert!(exists);
    let st = state.lock().expect("lock");
    assert_eq!(st.head_count, 1);
    assert_eq!(st.propfind_count, 1);
    assert_eq!(st.get_count, 0);
    drop(st);
    handle.join().expect("join");
}
