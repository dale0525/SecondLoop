use anyhow::{anyhow, Result};
use quick_xml::events::Event;
use quick_xml::Reader;
use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderValue, CACHE_CONTROL, PRAGMA};
use reqwest::Method;

pub fn join_base_url_and_path(base_url: &str, path: &str) -> String {
    format!(
        "{}/{}",
        base_url.trim_end_matches('/'),
        path.trim_start_matches('/')
    )
}

fn local_name(name: &[u8]) -> &[u8] {
    name.rsplit(|b| *b == b':').next().unwrap_or(name)
}

fn normalize_dir(path: &str) -> String {
    let trimmed = path.trim_matches('/');
    if trimmed.is_empty() {
        return "/".to_string();
    }
    format!("/{trimmed}/")
}

fn normalize_base_path(path: &str) -> String {
    normalize_dir(path)
}

fn href_to_path(href: &str) -> Result<String> {
    if href.contains("://") {
        let url = reqwest::Url::parse(href).map_err(|_| anyhow!("invalid href url"))?;
        return Ok(url.path().to_string());
    }
    Ok(href.to_string())
}

pub fn parse_propfind_multistatus(
    base_path: &str,
    requested_virtual_dir: &str,
    xml: &[u8],
) -> Result<Vec<String>> {
    let base_path = normalize_base_path(base_path);
    let requested_dir = normalize_dir(requested_virtual_dir);

    let mut reader = Reader::from_reader(xml);
    reader.trim_text(true);

    let mut buf: Vec<u8> = Vec::new();

    let mut in_response = false;
    let mut in_href = false;
    let mut current_href: Option<String> = None;
    let mut current_is_collection = false;

    let mut out: Vec<String> = Vec::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                match name {
                    b"response" => {
                        in_response = true;
                        in_href = false;
                        current_href = None;
                        current_is_collection = false;
                    }
                    b"href" if in_response => {
                        in_href = true;
                    }
                    b"collection" if in_response => {
                        current_is_collection = true;
                    }
                    _ => {}
                }
            }
            Ok(Event::Empty(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                if in_response && name == b"collection" {
                    current_is_collection = true;
                }
            }
            Ok(Event::End(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                match name {
                    b"response" if in_response => {
                        in_response = false;
                        in_href = false;

                        let Some(href) = current_href.take() else {
                            buf.clear();
                            continue;
                        };

                        let href_path = href_to_path(&href)?;
                        let Some(rest) = href_path.strip_prefix(&base_path) else {
                            buf.clear();
                            continue;
                        };
                        let rest = rest.trim_start_matches('/');
                        if rest.is_empty() {
                            buf.clear();
                            continue;
                        }

                        let mut virtual_path = format!("/{rest}");
                        if current_is_collection && !virtual_path.ends_with('/') {
                            virtual_path.push('/');
                        }
                        if !current_is_collection
                            && virtual_path.ends_with('/')
                            && virtual_path != "/"
                        {
                            virtual_path.pop();
                        }

                        if normalize_dir(&virtual_path) != requested_dir {
                            out.push(virtual_path);
                        }
                    }
                    b"href" => {
                        in_href = false;
                    }
                    _ => {}
                }
            }
            Ok(Event::Text(e)) if in_response && in_href => {
                let text = e.unescape().map_err(|_| anyhow!("invalid xml"))?;
                current_href = Some(text.to_string());
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(anyhow!("xml parse error: {e}")),
            _ => {}
        }
        buf.clear();
    }

    Ok(out)
}

pub struct WebDavRemoteStore {
    client: Client,
    target_id: String,
    base_url: String,
    base_path: String,
    username: Option<String>,
    password: Option<String>,
}

impl WebDavRemoteStore {
    pub fn new(
        base_url: String,
        username: Option<String>,
        password: Option<String>,
    ) -> Result<Self> {
        let parsed = reqwest::Url::parse(&base_url).map_err(|_| anyhow!("invalid base_url"))?;
        let mut base_path = parsed.path().to_string();
        if !base_path.ends_with('/') {
            base_path.push('/');
        }

        let mut sanitized = parsed;
        let _ = sanitized.set_username("");
        let _ = sanitized.set_password(None);
        sanitized.set_query(None);
        sanitized.set_fragment(None);
        sanitized.set_path(&base_path);
        let target_id = format!("webdav:{sanitized}");

        Ok(Self {
            client: Client::new(),
            target_id,
            base_url,
            base_path,
            username,
            password,
        })
    }

    fn request(
        &self,
        method: Method,
        virtual_path: &str,
    ) -> Result<reqwest::blocking::RequestBuilder> {
        let url = join_base_url_and_path(&self.base_url, virtual_path);
        let mut builder = self
            .client
            .request(method, url)
            .header(CACHE_CONTROL, "no-cache")
            .header(PRAGMA, "no-cache");
        if let Some(user) = &self.username {
            builder = builder.basic_auth(user, self.password.as_deref());
        }
        Ok(builder)
    }

    pub fn base_path(&self) -> &str {
        &self.base_path
    }

    pub fn ensure_dir_exists(&self, dir: &str) -> Result<()> {
        let dir = normalize_dir(dir);

        let mut headers = HeaderMap::new();
        headers.insert("Depth", HeaderValue::from_static("0"));
        headers.insert("Content-Type", HeaderValue::from_static("application/xml"));

        let body = r#"
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
  </d:prop>
</d:propfind>
"#;

        let req = self
            .request(Method::from_bytes(b"PROPFIND")?, &dir)?
            .headers(headers)
            .body(body);
        let resp = req.send()?;

        if resp.status().as_u16() == 404 {
            return Err(anyhow!("remote folder not found: {dir}"));
        }
        if !resp.status().is_success() && resp.status().as_u16() != 207 {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("PROPFIND failed: HTTP {status} {body}"));
        }

        Ok(())
    }
}

impl super::RemoteStore for WebDavRemoteStore {
    fn target_id(&self) -> &str {
        &self.target_id
    }

    fn mkdir_all(&self, path: &str) -> Result<()> {
        let dir = normalize_dir(path);
        if dir == "/" {
            return Ok(());
        }

        let mut cur = String::new();
        for part in dir.trim_matches('/').split('/') {
            if part.is_empty() {
                continue;
            }
            cur.push('/');
            cur.push_str(part);
            cur.push('/');

            let req = self.request(Method::from_bytes(b"MKCOL")?, &cur)?;
            let resp = req.send()?;
            match resp.status().as_u16() {
                200 | 201 | 204 | 405 => {}
                status => {
                    let body = resp.text().unwrap_or_default();
                    return Err(anyhow!("MKCOL failed: HTTP {status} {body}"));
                }
            }
        }
        Ok(())
    }

    fn list(&self, dir: &str) -> Result<Vec<String>> {
        let dir = normalize_dir(dir);

        let mut headers = HeaderMap::new();
        headers.insert("Depth", HeaderValue::from_static("1"));
        headers.insert("Content-Type", HeaderValue::from_static("application/xml"));

        let body = r#"
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
  </d:prop>
</d:propfind>
"#;

        let req = self
            .request(Method::from_bytes(b"PROPFIND")?, &dir)?
            .headers(headers)
            .body(body);
        let resp = req.send()?;

        if resp.status().as_u16() == 404 {
            return Ok(vec![]);
        }
        if !resp.status().is_success() && resp.status().as_u16() != 207 {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("PROPFIND failed: HTTP {status} {body}"));
        }

        let bytes = resp.bytes()?.to_vec();
        parse_propfind_multistatus(&self.base_path, &dir, &bytes)
    }

    fn get(&self, path: &str) -> Result<Vec<u8>> {
        let path = if path.ends_with('/') {
            return Err(anyhow!("GET expects file path, got dir: {path}"));
        } else {
            path.to_string()
        };

        let resp = self.request(Method::GET, &path)?.send()?;
        if resp.status().as_u16() == 404 {
            return Err(super::NotFound { path }.into());
        }
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("GET failed: HTTP {status} {body}"));
        }
        Ok(resp.bytes()?.to_vec())
    }

    fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()> {
        if path.ends_with('/') {
            return Err(anyhow!("PUT expects file path, got dir: {path}"));
        }

        let resp = self.request(Method::PUT, path)?.body(bytes).send()?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("PUT failed: HTTP {status} {body}"));
        }
        Ok(())
    }

    fn delete(&self, path: &str) -> Result<()> {
        let is_dir = path.ends_with('/');
        let path = if is_dir {
            normalize_dir(path)
        } else {
            path.to_string()
        };

        if path == "/" {
            return Err(anyhow!("refusing to delete root dir"));
        }

        let resp = self.request(Method::DELETE, &path)?.send()?;
        let status_u16 = resp.status().as_u16();
        if status_u16 == 404 {
            return Err(super::NotFound { path }.into());
        }

        if resp.status().is_success() {
            return Ok(());
        }

        // Some WebDAV servers reject deleting collections with a trailing slash URL and return
        // 405 even though they accept the same DELETE without the trailing slash.
        if is_dir && status_u16 == 405 {
            let alt_path = path.trim_end_matches('/').to_string();
            if alt_path != "/" && alt_path != path {
                let alt_resp = self.request(Method::DELETE, &alt_path)?.send()?;
                if alt_resp.status().is_success() {
                    return Ok(());
                }

                let alt_status = alt_resp.status();
                let alt_body = alt_resp.text().unwrap_or_default();
                let status = resp.status();
                let body = resp.text().unwrap_or_default();
                return Err(anyhow!(
                    "DELETE failed: HTTP {status} {body} (also tried without trailing slash: HTTP {alt_status} {alt_body})"
                ));
            }
        }

        {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!("DELETE failed: HTTP {status} {body}"));
        }
    }
}
