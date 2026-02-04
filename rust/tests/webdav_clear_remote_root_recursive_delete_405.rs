use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;
use std::time::{Duration, Instant};

use secondloop_rust::api::core::sync_webdav_clear_remote_root;

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

#[test]
fn webdav_clear_remote_root_recursively_deletes_contents_when_dir_delete_405() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let addr = listener.local_addr().unwrap();

    let server = thread::spawn(move || {
        let started = Instant::now();
        let mut handled = 0usize;
        while started.elapsed() < Duration::from_secs(2) {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let headers = read_http_headers(&mut stream);
                    let first_line = headers.lines().next().unwrap_or("");
                    let mut parts = first_line.split_whitespace();
                    let method = parts.next().unwrap_or("");
                    let path = parts.next().unwrap_or("");

                    match (method, path) {
                        ("DELETE", "/dav/SecondLoop/") => {
                            respond(&mut stream, "HTTP/1.1 405 Method Not Allowed")
                        }
                        ("DELETE", "/dav/SecondLoop") => {
                            respond(&mut stream, "HTTP/1.1 405 Method Not Allowed")
                        }
                        ("DELETE", "/dav/SecondLoop/deviceA/") => {
                            respond(&mut stream, "HTTP/1.1 405 Method Not Allowed")
                        }
                        ("DELETE", "/dav/SecondLoop/deviceA") => {
                            respond(&mut stream, "HTTP/1.1 405 Method Not Allowed")
                        }
                        ("DELETE", "/dav/SecondLoop/deviceA/ops/") => {
                            respond(&mut stream, "HTTP/1.1 405 Method Not Allowed")
                        }
                        ("DELETE", "/dav/SecondLoop/deviceA/ops") => {
                            respond(&mut stream, "HTTP/1.1 405 Method Not Allowed")
                        }
                        ("DELETE", "/dav/SecondLoop/deviceA/ops/op_1.json") => {
                            respond(&mut stream, "HTTP/1.1 204 No Content")
                        }

                        ("PROPFIND", "/dav/SecondLoop/") => {
                            let xml = r#"<?xml version="1.0" encoding="utf-8" ?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/SecondLoop/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/SecondLoop/deviceA/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
"#;
                            respond_xml(&mut stream, "HTTP/1.1 207 Multi-Status", xml)
                        }
                        ("PROPFIND", "/dav/SecondLoop/deviceA/") => {
                            let xml = r#"<?xml version="1.0" encoding="utf-8" ?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/SecondLoop/deviceA/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/SecondLoop/deviceA/ops/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
"#;
                            respond_xml(&mut stream, "HTTP/1.1 207 Multi-Status", xml)
                        }
                        ("PROPFIND", "/dav/SecondLoop/deviceA/ops/") => {
                            let xml = r#"<?xml version="1.0" encoding="utf-8" ?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/SecondLoop/deviceA/ops/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/SecondLoop/deviceA/ops/op_1.json</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
"#;
                            respond_xml(&mut stream, "HTTP/1.1 207 Multi-Status", xml)
                        }
                        _ => respond(&mut stream, "HTTP/1.1 404 Not Found"),
                    }

                    handled += 1;
                    if handled >= 12 {
                        break;
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(10));
                }
                Err(_) => break,
            }
        }
    });

    let base_url = format!("http://{addr}/dav");
    sync_webdav_clear_remote_root(base_url, None, None, "SecondLoop".to_string()).expect(
        "expected clear to succeed by deleting children even when collection DELETE is unsupported",
    );

    let _ = server.join();
}
