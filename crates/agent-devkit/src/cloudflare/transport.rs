use async_trait::async_trait;
use reqwest::header::{HeaderName, HeaderValue};
use std::collections::BTreeMap;
use std::fmt;
use std::time::Duration;
use url::Url;
use zeroize::Zeroize;

const MAX_TRANSPORT_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CloudflareHttpMethod {
    Get,
    Post,
    Put,
    Delete,
}

impl CloudflareHttpMethod {
    pub fn is_mutating(self) -> bool {
        !matches!(self, Self::Get)
    }

    fn as_reqwest(self) -> reqwest::Method {
        match self {
            Self::Get => reqwest::Method::GET,
            Self::Post => reqwest::Method::POST,
            Self::Put => reqwest::Method::PUT,
            Self::Delete => reqwest::Method::DELETE,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RedirectPolicy {
    Reject,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RequestBodySensitivity {
    Public,
    Sensitive,
}

pub struct CloudflareTransportRequest {
    method: CloudflareHttpMethod,
    url: Url,
    headers: BTreeMap<String, String>,
    body: Vec<u8>,
    body_sensitivity: RequestBodySensitivity,
    redirect_policy: RedirectPolicy,
}

impl CloudflareTransportRequest {
    pub(crate) fn new(
        method: CloudflareHttpMethod,
        url: Url,
        headers: BTreeMap<String, String>,
        body: Vec<u8>,
        body_sensitivity: RequestBodySensitivity,
    ) -> Self {
        Self {
            method,
            url,
            headers,
            body,
            body_sensitivity,
            redirect_policy: RedirectPolicy::Reject,
        }
    }

    pub fn method(&self) -> CloudflareHttpMethod {
        self.method
    }

    pub fn url(&self) -> &Url {
        &self.url
    }

    /// Transport implementations require raw headers to send the request. Do not log this map.
    pub fn headers(&self) -> &BTreeMap<String, String> {
        &self.headers
    }

    /// Transport implementations require raw bytes to send the request. Do not log sensitive bodies.
    pub fn body(&self) -> &[u8] {
        &self.body
    }

    pub fn body_sensitivity(&self) -> RequestBodySensitivity {
        self.body_sensitivity
    }

    pub fn redirect_policy(&self) -> RedirectPolicy {
        self.redirect_policy
    }
}

impl fmt::Debug for CloudflareTransportRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let headers = self
            .headers
            .iter()
            .map(|(name, value)| {
                (
                    name,
                    if sensitive_header(name) {
                        "[REDACTED]"
                    } else {
                        value
                    },
                )
            })
            .collect::<BTreeMap<_, _>>();
        formatter
            .debug_struct("CloudflareTransportRequest")
            .field("method", &self.method)
            .field("url", &self.url)
            .field("headers", &headers)
            .field("body_length", &self.body.len())
            .field("body_sensitivity", &self.body_sensitivity)
            .field("redirect_policy", &self.redirect_policy)
            .finish()
    }
}

impl Drop for CloudflareTransportRequest {
    fn drop(&mut self) {
        for (name, value) in &mut self.headers {
            if sensitive_header(name) {
                value.zeroize();
            }
        }
        if self.body_sensitivity == RequestBodySensitivity::Sensitive {
            self.body.zeroize();
        }
    }
}

fn sensitive_header(name: &str) -> bool {
    name.eq_ignore_ascii_case("authorization")
        || name.eq_ignore_ascii_case("cf-access-jwt-assertion")
}

pub struct CloudflareTransportResponse {
    status: u16,
    headers: BTreeMap<String, String>,
    body: Vec<u8>,
}

impl CloudflareTransportResponse {
    pub fn new(status: u16, headers: BTreeMap<String, String>, body: Vec<u8>) -> Self {
        Self {
            status,
            headers: headers
                .into_iter()
                .map(|(name, value)| (name.to_ascii_lowercase(), value))
                .collect(),
            body,
        }
    }

    pub fn json(status: u16, value: serde_json::Value) -> Self {
        Self::new(
            status,
            BTreeMap::from([("content-type".into(), "application/json".into())]),
            serde_json::to_vec(&value).unwrap_or_default(),
        )
    }

    pub fn status(&self) -> u16 {
        self.status
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .get(&name.to_ascii_lowercase())
            .map(String::as_str)
    }

    pub fn body(&self) -> &[u8] {
        &self.body
    }
}

impl fmt::Debug for CloudflareTransportResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CloudflareTransportResponse")
            .field("status", &self.status)
            .field("headers", &self.headers.keys().collect::<Vec<_>>())
            .field("body_length", &self.body.len())
            .finish()
    }
}

impl Drop for CloudflareTransportResponse {
    fn drop(&mut self) {
        self.body.zeroize();
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CloudflareTransportFailureKind {
    Timeout,
    Connect,
    Tls,
    Protocol,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CloudflareTransportFailure {
    pub kind: CloudflareTransportFailureKind,
    /// Must be a static or sanitized message with no URL query, body, token or upstream payload.
    pub safe_message: String,
}

impl CloudflareTransportFailure {
    pub fn timeout() -> Self {
        Self {
            kind: CloudflareTransportFailureKind::Timeout,
            safe_message: "Cloudflare request timed out".into(),
        }
    }

    pub fn protocol(message: impl Into<String>) -> Self {
        Self {
            kind: CloudflareTransportFailureKind::Protocol,
            safe_message: message.into(),
        }
    }
}

#[async_trait]
pub trait CloudflareTransport: Send + Sync {
    async fn send(
        &self,
        request: CloudflareTransportRequest,
    ) -> Result<CloudflareTransportResponse, CloudflareTransportFailure>;
}

pub struct ReqwestCloudflareTransport {
    client: reqwest::Client,
}

impl ReqwestCloudflareTransport {
    pub fn new(timeout: Duration) -> Result<Self, CloudflareTransportFailure> {
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| CloudflareTransportFailure::protocol("HTTP client setup failed"))?;
        Ok(Self { client })
    }
}

#[async_trait]
impl CloudflareTransport for ReqwestCloudflareTransport {
    async fn send(
        &self,
        request: CloudflareTransportRequest,
    ) -> Result<CloudflareTransportResponse, CloudflareTransportFailure> {
        if request.redirect_policy() != RedirectPolicy::Reject {
            return Err(CloudflareTransportFailure::protocol(
                "redirect policy must reject redirects",
            ));
        }
        let mut builder = self
            .client
            .request(request.method().as_reqwest(), request.url().clone());
        for (name, value) in request.headers() {
            let name = HeaderName::from_bytes(name.as_bytes()).map_err(|_| {
                CloudflareTransportFailure::protocol("request header name is invalid")
            })?;
            let value = HeaderValue::from_str(value).map_err(|_| {
                CloudflareTransportFailure::protocol("request header value is invalid")
            })?;
            builder = builder.header(name, value);
        }
        if !request.body().is_empty() {
            builder = builder.body(request.body().to_vec());
        }
        let response = builder.send().await.map_err(|error| {
            if error.is_timeout() {
                CloudflareTransportFailure::timeout()
            } else if error.is_connect() {
                CloudflareTransportFailure {
                    kind: CloudflareTransportFailureKind::Connect,
                    safe_message: "Cloudflare connection failed".into(),
                }
            } else {
                CloudflareTransportFailure::protocol("Cloudflare HTTP request failed")
            }
        })?;
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.as_str().to_ascii_lowercase(), value.to_owned()))
            })
            .collect();
        if response
            .content_length()
            .is_some_and(|length| length > MAX_TRANSPORT_RESPONSE_BYTES as u64)
        {
            return Err(CloudflareTransportFailure::protocol(
                "Cloudflare response exceeds the size limit",
            ));
        }
        let body = response.bytes().await.map_err(|_| {
            CloudflareTransportFailure::protocol("Cloudflare response body could not be read")
        })?;
        if body.len() > MAX_TRANSPORT_RESPONSE_BYTES {
            return Err(CloudflareTransportFailure::protocol(
                "Cloudflare response exceeds the size limit",
            ));
        }
        Ok(CloudflareTransportResponse::new(
            status,
            headers,
            body.to_vec(),
        ))
    }
}
