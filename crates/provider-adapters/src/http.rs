use agent_runtime::credential::SecretMaterial;
use async_trait::async_trait;
use reqwest::{Method, Url};
use serde_json::Value;
use std::collections::BTreeMap;
use std::time::Duration;

const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq)]
pub struct ProviderHttpRequest {
    pub method: Method,
    pub path: String,
    pub query: Vec<(String, String)>,
    pub headers: BTreeMap<String, String>,
    pub json: Option<Value>,
}

impl ProviderHttpRequest {
    pub fn get(path: impl Into<String>) -> Self {
        Self {
            method: Method::GET,
            path: path.into(),
            query: Vec::new(),
            headers: BTreeMap::new(),
            json: None,
        }
    }

    pub fn json(method: Method, path: impl Into<String>, json: Value) -> Self {
        Self {
            method,
            path: path.into(),
            query: Vec::new(),
            headers: BTreeMap::new(),
            json: Some(json),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderHttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
}

impl ProviderHttpResponse {
    pub fn json<T: serde::de::DeserializeOwned>(&self) -> anyhow::Result<T> {
        anyhow::ensure!(
            (200..300).contains(&self.status),
            "provider returned HTTP {}",
            self.status
        );
        serde_json::from_slice(&self.body).map_err(Into::into)
    }
}

#[async_trait]
pub trait ProviderHttpClient: Send + Sync {
    async fn execute(
        &self,
        request: ProviderHttpRequest,
        bearer_token: &SecretMaterial,
    ) -> anyhow::Result<ProviderHttpResponse>;
}

pub struct ReqwestProviderHttpClient {
    base_url: Url,
    client: reqwest::Client,
}

impl ReqwestProviderHttpClient {
    pub fn new(base_url: &str, allow_insecure_localhost: bool) -> anyhow::Result<Self> {
        let base_url = Url::parse(base_url)?;
        let local = matches!(
            base_url.host_str(),
            Some("127.0.0.1" | "localhost" | "[::1]")
        );
        anyhow::ensure!(
            base_url.scheme() == "https"
                || (allow_insecure_localhost && base_url.scheme() == "http" && local),
            "provider base URL must use HTTPS"
        );
        anyhow::ensure!(
            base_url.username().is_empty() && base_url.password().is_none(),
            "provider base URL cannot contain credentials"
        );
        Ok(Self {
            base_url,
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
        })
    }

    fn url(&self, request: &ProviderHttpRequest) -> anyhow::Result<Url> {
        anyhow::ensure!(
            request.path.starts_with('/') && !request.path.starts_with("//"),
            "provider request path must be absolute-path relative"
        );
        let mut url = self.base_url.join(request.path.trim_start_matches('/'))?;
        anyhow::ensure!(
            url.origin() == self.base_url.origin(),
            "provider request escaped configured origin"
        );
        url.query_pairs_mut().extend_pairs(&request.query);
        Ok(url)
    }
}

#[async_trait]
impl ProviderHttpClient for ReqwestProviderHttpClient {
    async fn execute(
        &self,
        request: ProviderHttpRequest,
        bearer_token: &SecretMaterial,
    ) -> anyhow::Result<ProviderHttpResponse> {
        let url = self.url(&request)?;
        let token = bearer_token
            .with_exposed_bytes(|bytes| std::str::from_utf8(bytes).map(str::to_owned))?;
        let mut builder = self.client.request(request.method, url).bearer_auth(token);
        for (name, value) in request.headers {
            anyhow::ensure!(
                !name.eq_ignore_ascii_case("authorization"),
                "provider request cannot override authorization"
            );
            builder = builder.header(name, value);
        }
        if let Some(body) = request.json {
            builder = builder.json(&body);
        }
        let response = builder.send().await?;
        let status = response.status().as_u16();
        let bytes = response.bytes().await?;
        anyhow::ensure!(
            bytes.len() <= MAX_RESPONSE_BYTES,
            "provider response exceeds limit"
        );
        Ok(ProviderHttpResponse {
            status,
            body: bytes.to_vec(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_rejects_insecure_and_credential_bearing_origins() {
        assert!(ReqwestProviderHttpClient::new("http://example.test/", false).is_err());
        assert!(ReqwestProviderHttpClient::new("https://user@example.test/", false).is_err());
        assert!(ReqwestProviderHttpClient::new("http://127.0.0.1:8080/", true).is_ok());
    }
}
