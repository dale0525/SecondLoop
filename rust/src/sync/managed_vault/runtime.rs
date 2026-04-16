use anyhow::{anyhow, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64_URL;
use base64::Engine as _;

#[cfg(not(target_family = "wasm"))]
pub(super) use reqwest::blocking::Client;

#[cfg(not(target_family = "wasm"))]
use std::sync::OnceLock;

#[cfg(target_family = "wasm")]
use js_sys::{Reflect, Uint8Array};

#[cfg(target_family = "wasm")]
use serde::Serialize;

#[cfg(target_family = "wasm")]
use serde::de::DeserializeOwned;

#[cfg(target_family = "wasm")]
use web_sys::{XmlHttpRequest, XmlHttpRequestResponseType};

#[cfg(target_family = "wasm")]
#[derive(Clone, Debug, Default)]
pub(super) struct Client;

#[cfg(target_family = "wasm")]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct StatusCode(u16);

#[cfg(target_family = "wasm")]
impl StatusCode {
    pub(super) fn as_u16(self) -> u16 {
        self.0
    }

    pub(super) fn is_success(self) -> bool {
        (200..300).contains(&self.0)
    }

    pub(super) fn is_server_error(self) -> bool {
        (500..600).contains(&self.0)
    }
}

#[cfg(target_family = "wasm")]
impl std::fmt::Display for StatusCode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[cfg(target_family = "wasm")]
#[derive(Clone, Debug)]
pub(super) struct Response {
    status: StatusCode,
    body: Vec<u8>,
}

#[cfg(target_family = "wasm")]
impl Response {
    pub(super) fn status(&self) -> StatusCode {
        self.status
    }

    pub(super) fn text(self) -> Result<String> {
        Ok(String::from_utf8(self.body)
            .unwrap_or_else(|error| String::from_utf8_lossy(error.as_bytes()).to_string()))
    }

    pub(super) fn bytes(self) -> Result<Vec<u8>> {
        Ok(self.body)
    }

    pub(super) fn json<T: DeserializeOwned>(self) -> Result<T> {
        serde_json::from_slice(&self.body)
            .map_err(|error| anyhow!("invalid managed-vault json response: {error}"))
    }
}

#[cfg(target_family = "wasm")]
#[derive(Clone, Debug)]
pub(super) struct RequestBuilder {
    method: String,
    url: String,
    headers: Vec<(String, String)>,
    body: Option<Vec<u8>>,
}

#[cfg(target_family = "wasm")]
impl Client {
    pub(super) fn new() -> Self {
        Self
    }

    pub(super) fn post(&self, url: impl AsRef<str>) -> RequestBuilder {
        RequestBuilder::new("POST", url.as_ref())
    }

    pub(super) fn get(&self, url: impl AsRef<str>) -> RequestBuilder {
        RequestBuilder::new("GET", url.as_ref())
    }

    pub(super) fn put(&self, url: impl AsRef<str>) -> RequestBuilder {
        RequestBuilder::new("PUT", url.as_ref())
    }

    pub(super) fn delete(&self, url: impl AsRef<str>) -> RequestBuilder {
        RequestBuilder::new("DELETE", url.as_ref())
    }

    pub(super) fn head(&self, url: impl AsRef<str>) -> RequestBuilder {
        RequestBuilder::new("HEAD", url.as_ref())
    }
}

#[cfg(target_family = "wasm")]
impl RequestBuilder {
    fn new(method: &str, url: &str) -> Self {
        Self {
            method: method.to_string(),
            url: url.to_string(),
            headers: Vec::new(),
            body: None,
        }
    }

    pub(super) fn bearer_auth(mut self, token: &str) -> Self {
        self.headers.push((
            "authorization".to_string(),
            format!("Bearer {}", token.trim()),
        ));
        self
    }

    pub(super) fn json<T: Serialize>(mut self, value: &T) -> Self {
        self.headers
            .push(("content-type".to_string(), "application/json".to_string()));
        self.body = Some(
            serde_json::to_vec(value).expect("managed-vault request payload should serialize"),
        );
        self
    }

    pub(super) fn header(mut self, key: impl ToString, value: impl ToString) -> Self {
        self.headers.push((key.to_string(), value.to_string()));
        self
    }

    pub(super) fn body(mut self, body: Vec<u8>) -> Self {
        self.body = Some(body);
        self
    }

    pub(super) fn send(self) -> Result<Response> {
        // This sync XHR client is only used from the dedicated web worker path
        // that fronts OPFS/SQLite access. Calling it on the main browser thread
        // would block rendering, so wasm managed-vault callers must stay in that
        // worker-backed execution context.
        let global = js_sys::global();
        let is_main_thread_window = Reflect::has(&global, &"document".into())
            .map_err(|error| anyhow!("inspect wasm execution context failed: {error:?}"))?;
        if is_main_thread_window {
            return Err(anyhow!(
                "managed-vault sync XHR must run in a dedicated web worker"
            ));
        }
        let xhr = XmlHttpRequest::new()
            .map_err(|error| anyhow!("create XMLHttpRequest failed: {error:?}"))?;
        xhr.open_with_async(&self.method, &self.url, false)
            .map_err(|error| anyhow!("open XMLHttpRequest failed: {error:?}"))?;
        xhr.set_response_type(XmlHttpRequestResponseType::Arraybuffer);

        for (key, value) in &self.headers {
            xhr.set_request_header(key, value)
                .map_err(|error| anyhow!("set request header failed: {key}: {error:?}"))?;
        }

        match self.body {
            Some(body) => {
                let js_body = Uint8Array::new_with_length(body.len() as u32);
                js_body.copy_from(body.as_slice());
                xhr.send_with_opt_js_u8_array(Some(&js_body))
                    .map_err(|error| anyhow!("send XMLHttpRequest failed: {error:?}"))?
            }
            None => xhr
                .send()
                .map_err(|error| anyhow!("send XMLHttpRequest failed: {error:?}"))?,
        }

        let status = StatusCode(
            xhr.status()
                .map_err(|error| anyhow!("read XMLHttpRequest status failed: {error:?}"))?,
        );
        let response = xhr
            .response()
            .map_err(|error| anyhow!("read XMLHttpRequest response failed: {error:?}"))?;
        let body = if response.is_null() || response.is_undefined() {
            Vec::new()
        } else {
            Uint8Array::new(&response).to_vec()
        };

        Ok(Response { status, body })
    }
}

pub(super) fn scope_id(base_url: &str, vault_id: &str) -> String {
    let raw = format!("managed_vault|{}|{}", base_url.trim(), vault_id.trim());
    B64_URL.encode(raw.as_bytes())
}

pub(super) fn client() -> Result<Client> {
    #[cfg(not(target_family = "wasm"))]
    {
        static CLIENT: OnceLock<Client> = OnceLock::new();
        Ok(CLIENT.get_or_init(Client::new).clone())
    }

    #[cfg(target_family = "wasm")]
    {
        Ok(Client::new())
    }
}

pub(super) fn url(base_url: &str, path: &str) -> Result<String> {
    let base = base_url.trim_end_matches('/');
    if base.is_empty() {
        return Err(anyhow!("missing_base_url"));
    }
    Ok(format!("{base}{path}"))
}

use super::{RegisterDeviceRequest, RegisterDeviceResponse};

pub(super) fn ensure_device_registered(
    http: &Client,
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    device_id: &str,
) -> Result<String> {
    let request = RegisterDeviceRequest {
        platform: "unknown",
        device_id: Some(device_id),
    };

    let endpoint = url(base_url, &format!("/v1/vaults/{vault_id}/devices"))?;
    let resp = http
        .post(endpoint)
        .bearer_auth(id_token)
        .json(&request)
        .send()?;

    let status = resp.status();
    let text = resp.text().unwrap_or_default();
    if !status.is_success() {
        return Err(anyhow!(
            "managed-vault register-device failed: HTTP {status} {text}"
        ));
    }

    let parsed: RegisterDeviceResponse = serde_json::from_str(&text)?;
    Ok(parsed.device_id)
}
