use super::{
    CLOUDFLARE_API_BASE_URL, CloudflareHttpMethod, CloudflareTransport,
    CloudflareTransportFailureKind, CloudflareTransportRequest, RequestBodySensitivity,
};
use crate::{
    DeveloperAuthorization, DevkitError, DevkitErrorCode, DevkitResult, RemoteMutationRisk,
    SensitiveInputHandle, SensitiveInputResolver,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::Arc;
use url::Url;

const MAX_API_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq)]
pub struct CloudflareApiResult {
    pub value: Value,
    pub etag: Option<String>,
}

pub struct CloudflareRestClient<T, R> {
    api_base: Url,
    transport: Arc<T>,
    resolver: Arc<R>,
}

impl<T, R> Clone for CloudflareRestClient<T, R> {
    fn clone(&self) -> Self {
        Self {
            api_base: self.api_base.clone(),
            transport: Arc::clone(&self.transport),
            resolver: Arc::clone(&self.resolver),
        }
    }
}

impl<T, R> CloudflareRestClient<T, R>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    pub fn new(transport: Arc<T>, resolver: Arc<R>) -> DevkitResult<Self> {
        Self::with_api_base(CLOUDFLARE_API_BASE_URL, transport, resolver)
    }

    /// Supports a pinned HTTPS test emulator while retaining all production URL checks.
    pub fn with_api_base(
        api_base: &str,
        transport: Arc<T>,
        resolver: Arc<R>,
    ) -> DevkitResult<Self> {
        let api_base = secure_origin_url(api_base, true)?;
        Ok(Self {
            api_base,
            transport,
            resolver,
        })
    }

    pub fn api_origin(&self) -> String {
        self.api_base.origin().ascii_serialization()
    }

    pub async fn get_json(
        &self,
        authorization: Option<&DeveloperAuthorization>,
        relative_path: &str,
    ) -> DevkitResult<CloudflareApiResult> {
        self.execute_json(
            authorization,
            CloudflareHttpMethod::Get,
            relative_path,
            None,
        )
        .await
    }

    pub(crate) async fn get_json_with_query(
        &self,
        authorization: Option<&DeveloperAuthorization>,
        relative_path: &str,
        query: &BTreeMap<String, String>,
    ) -> DevkitResult<CloudflareApiResult> {
        if query.len() > 32
            || query.iter().any(|(name, value)| {
                name.is_empty()
                    || name.len() > 128
                    || value.len() > 4096
                    || name.chars().any(char::is_control)
                    || value.chars().any(char::is_control)
            })
        {
            return Err(DevkitError::invalid_configuration(
                "Cloudflare request query is invalid",
            ));
        }
        let mut url = pinned_relative_url(&self.api_base, relative_path)?;
        {
            let mut pairs = url.query_pairs_mut();
            for (name, value) in query {
                pairs.append_pair(name, value);
            }
        }
        self.execute_url_bytes(
            authorization,
            CloudflareHttpMethod::Get,
            url,
            Vec::new(),
            RequestBodySensitivity::Public,
            None,
        )
        .await
    }

    pub async fn execute_json(
        &self,
        authorization: Option<&DeveloperAuthorization>,
        method: CloudflareHttpMethod,
        relative_path: &str,
        body: Option<&Value>,
    ) -> DevkitResult<CloudflareApiResult> {
        let bytes = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| {
                DevkitError::new(
                    DevkitErrorCode::InvalidConfiguration,
                    "Cloudflare request body could not be encoded",
                )
            })?
            .unwrap_or_default();
        self.execute_bytes(
            authorization,
            method,
            relative_path,
            bytes,
            RequestBodySensitivity::Public,
            Some("application/json"),
        )
        .await
    }

    pub async fn put_secret(
        &self,
        authorization: &DeveloperAuthorization,
        relative_path: &str,
        binding_name: &str,
        value_handle: &SensitiveInputHandle,
    ) -> DevkitResult<CloudflareApiResult> {
        #[derive(Serialize)]
        struct SecretBody<'a> {
            name: &'a str,
            text: &'a str,
            r#type: &'static str,
        }

        if binding_name.is_empty() || binding_name.len() > 128 {
            return Err(DevkitError::invalid_configuration(
                "Cloudflare secret binding name is invalid",
            ));
        }
        let value = self.resolver.resolve(value_handle).await?;
        let body = value.expose(|bytes| {
            let text = std::str::from_utf8(bytes).map_err(|_| {
                DevkitError::new(
                    DevkitErrorCode::InvalidConfiguration,
                    "Cloudflare secret must be valid UTF-8",
                )
            })?;
            serde_json::to_vec(&SecretBody {
                name: binding_name,
                text,
                r#type: "secret_text",
            })
            .map_err(|_| {
                DevkitError::new(
                    DevkitErrorCode::Internal,
                    "Cloudflare secret request could not be encoded",
                )
            })
        })?;
        self.execute_bytes(
            Some(authorization),
            CloudflareHttpMethod::Put,
            relative_path,
            body,
            RequestBodySensitivity::Sensitive,
            Some("application/json"),
        )
        .await
    }

    /// Calls the versioned gateway health endpoint with a one-time end-user identity.
    ///
    /// The endpoint is pinned to the URL carried by verified deployment facts. Redirects remain
    /// disabled so the disposable identity cannot be forwarded to another origin.
    pub async fn test_gateway_health(
        &self,
        health_url: &str,
        one_time_identity: &SensitiveInputHandle,
    ) -> DevkitResult<Value> {
        let url = secure_origin_url(health_url, false)?;
        if url.path() != "/.well-known/agentweave/gateway-health" {
            return Err(DevkitError::new(
                DevkitErrorCode::OriginRejected,
                "gateway health URL does not use the versioned AgentWeave health path",
            ));
        }
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase", deny_unknown_fields)]
        struct OneTimeGatewayIdentity {
            schema_version: u32,
            header: String,
            token: String,
        }

        impl Drop for OneTimeGatewayIdentity {
            fn drop(&mut self) {
                use zeroize::Zeroize;
                self.token.zeroize();
            }
        }

        let identity = self.resolver.resolve(one_time_identity).await?;
        let mut identity = identity.expose(|bytes| {
            if bytes.first() == Some(&b'{') {
                serde_json::from_slice::<OneTimeGatewayIdentity>(bytes).map_err(|_| {
                    DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        "one-time gateway identity envelope is invalid",
                    )
                })
            } else {
                let token = std::str::from_utf8(bytes).map_err(|_| {
                    DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        "one-time gateway identity is not valid UTF-8",
                    )
                })?;
                Ok(OneTimeGatewayIdentity {
                    schema_version: 1,
                    header: "authorization".into(),
                    token: token.into(),
                })
            }
        })?;
        let header = identity.header.to_ascii_lowercase();
        if identity.schema_version != 1
            || !matches!(header.as_str(), "authorization" | "cf-access-jwt-assertion")
            || identity.token.is_empty()
            || identity.token.len() > 16 * 1024
            || identity.token.contains(['\r', '\n'])
        {
            return Err(DevkitError::new(
                DevkitErrorCode::SensitiveInputUnavailable,
                "one-time gateway identity is invalid",
            ));
        }
        let token = zeroize::Zeroizing::new(std::mem::take(&mut identity.token));
        let value = if header == "authorization" {
            format!("Bearer {}", token.as_str())
        } else {
            token.as_str().to_owned()
        };
        let request = CloudflareTransportRequest::new(
            CloudflareHttpMethod::Get,
            url,
            BTreeMap::from([
                ("accept".into(), "application/json".into()),
                (header, value),
            ]),
            Vec::new(),
            RequestBodySensitivity::Public,
        );
        let response = self.transport.send(request).await.map_err(|failure| {
            let (code, message) = match failure.kind {
                CloudflareTransportFailureKind::Timeout => {
                    (DevkitErrorCode::Timeout, "gateway health request timed out")
                }
                CloudflareTransportFailureKind::Connect | CloudflareTransportFailureKind::Tls => (
                    DevkitErrorCode::Unavailable,
                    "gateway health connection failed",
                ),
                CloudflareTransportFailureKind::Protocol => (
                    DevkitErrorCode::RemoteProtocol,
                    "gateway health transport failed",
                ),
            };
            DevkitError::new(code, message)
        })?;
        if (300..400).contains(&response.status()) {
            return Err(DevkitError::new(
                DevkitErrorCode::RedirectRejected,
                "gateway health redirects are not permitted",
            ));
        }
        if response.status() == 429 {
            let wait = response
                .header("retry-after")
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or(1)
                .saturating_mul(1_000)
                .min(86_400_000);
            return Err(DevkitError::new(
                DevkitErrorCode::RateLimited,
                "gateway health rate limit was reached",
            )
            .retry_after(wait));
        }
        if !(200..300).contains(&response.status()) {
            return Err(DevkitError::new(
                DevkitErrorCode::VerificationFailed,
                format!("gateway health returned HTTP {}", response.status()),
            ));
        }
        if response.body().len() > MAX_API_RESPONSE_BYTES {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "gateway health response exceeds the size limit",
            ));
        }
        serde_json::from_slice(response.body()).map_err(|_| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "gateway health returned an invalid response",
            )
        })
    }

    /// Calls the public entitlement Worker health endpoint without forwarding credentials.
    pub async fn test_entitlement_health(&self, health_url: &str) -> DevkitResult<Value> {
        let url = secure_origin_url(health_url, false)?;
        if url.path() != "/healthz" || url.query().is_some() {
            return Err(DevkitError::new(
                DevkitErrorCode::OriginRejected,
                "entitlement health URL does not use the pinned health path",
            ));
        }
        let request = CloudflareTransportRequest::new(
            CloudflareHttpMethod::Get,
            url,
            BTreeMap::from([("accept".into(), "application/json".into())]),
            Vec::new(),
            RequestBodySensitivity::Public,
        );
        let response = self.transport.send(request).await.map_err(|failure| {
            let (code, message) = match failure.kind {
                CloudflareTransportFailureKind::Timeout => (
                    DevkitErrorCode::Timeout,
                    "entitlement health request timed out",
                ),
                CloudflareTransportFailureKind::Connect | CloudflareTransportFailureKind::Tls => (
                    DevkitErrorCode::Unavailable,
                    "entitlement health connection failed",
                ),
                CloudflareTransportFailureKind::Protocol => (
                    DevkitErrorCode::RemoteProtocol,
                    "entitlement health transport failed",
                ),
            };
            DevkitError::new(code, message)
        })?;
        if (300..400).contains(&response.status()) {
            return Err(DevkitError::new(
                DevkitErrorCode::RedirectRejected,
                "entitlement health redirects are not permitted",
            ));
        }
        if response.status() == 429 {
            let wait = response
                .header("retry-after")
                .and_then(|value| value.parse::<u64>().ok())
                .unwrap_or(1)
                .saturating_mul(1_000)
                .min(86_400_000);
            return Err(DevkitError::new(
                DevkitErrorCode::RateLimited,
                "entitlement health rate limit was reached",
            )
            .retry_after(wait));
        }
        if !(200..300).contains(&response.status()) {
            return Err(DevkitError::new(
                DevkitErrorCode::VerificationFailed,
                format!("entitlement health returned HTTP {}", response.status()),
            ));
        }
        if response.body().len() > MAX_API_RESPONSE_BYTES {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "entitlement health response exceeds the size limit",
            ));
        }
        serde_json::from_slice(response.body()).map_err(|_| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "entitlement health returned an invalid response",
            )
        })
    }

    pub(crate) async fn execute_bytes(
        &self,
        authorization: Option<&DeveloperAuthorization>,
        method: CloudflareHttpMethod,
        relative_path: &str,
        body: Vec<u8>,
        body_sensitivity: RequestBodySensitivity,
        content_type: Option<&str>,
    ) -> DevkitResult<CloudflareApiResult> {
        let url = pinned_relative_url(&self.api_base, relative_path)?;
        self.execute_url_bytes(
            authorization,
            method,
            url,
            body,
            body_sensitivity,
            content_type,
        )
        .await
    }

    async fn execute_url_bytes(
        &self,
        authorization: Option<&DeveloperAuthorization>,
        method: CloudflareHttpMethod,
        url: Url,
        body: Vec<u8>,
        body_sensitivity: RequestBodySensitivity,
        content_type: Option<&str>,
    ) -> DevkitResult<CloudflareApiResult> {
        let mut headers = BTreeMap::from([("accept".into(), "application/json".into())]);
        if let Some(content_type) = content_type {
            headers.insert("content-type".into(), content_type.into());
        }
        if let Some(authorization) = authorization {
            let token = self.resolver.resolve(authorization.token_handle()).await?;
            let bearer = token.expose(|bytes| {
                let token = std::str::from_utf8(bytes).map_err(|_| {
                    DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        "developer authorization token is not valid UTF-8",
                    )
                })?;
                if token.contains(['\r', '\n']) {
                    return Err(DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        "developer authorization token is invalid",
                    ));
                }
                Ok(format!("Bearer {token}"))
            })?;
            headers.insert("authorization".into(), bearer);
        }
        let request = CloudflareTransportRequest::new(method, url, headers, body, body_sensitivity);
        let response = self.transport.send(request).await.map_err(|failure| {
            let (code, message) = match failure.kind {
                CloudflareTransportFailureKind::Timeout => {
                    (DevkitErrorCode::Timeout, "Cloudflare API request timed out")
                }
                CloudflareTransportFailureKind::Connect | CloudflareTransportFailureKind::Tls => (
                    DevkitErrorCode::Unavailable,
                    "Cloudflare API connection failed",
                ),
                CloudflareTransportFailureKind::Protocol => (
                    DevkitErrorCode::RemoteProtocol,
                    "Cloudflare API transport failed",
                ),
            };
            DevkitError::new(code, message).with_remote_mutation_risk(if method.is_mutating() {
                RemoteMutationRisk::Possible
            } else {
                RemoteMutationRisk::None
            })
        })?;
        decode_api_response(method, response)
    }
}

pub(crate) fn secure_origin_url(value: &str, require_trailing_slash: bool) -> DevkitResult<Url> {
    let url = Url::parse(value).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::OriginRejected,
            "Cloudflare endpoint URL is invalid",
        )
    })?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || (require_trailing_slash && !url.path().ends_with('/'))
    {
        return Err(DevkitError::new(
            DevkitErrorCode::OriginRejected,
            "Cloudflare endpoints must be credential-free HTTPS URLs",
        ));
    }
    Ok(url)
}

pub(crate) fn pinned_relative_url(base: &Url, relative_path: &str) -> DevkitResult<Url> {
    let valid = !relative_path.is_empty()
        && !relative_path.starts_with('/')
        && !relative_path.contains(['\\', '?', '#'])
        && !relative_path.contains("://")
        && relative_path
            .split('/')
            .all(|segment| !segment.is_empty() && segment != "." && segment != "..");
    if !valid {
        return Err(DevkitError::new(
            DevkitErrorCode::OriginRejected,
            "Cloudflare request path is not origin-relative",
        ));
    }
    let url = base.join(relative_path).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::OriginRejected,
            "Cloudflare request URL could not be constructed",
        )
    })?;
    if url.origin() != base.origin() || !url.path().starts_with(base.path()) {
        return Err(DevkitError::new(
            DevkitErrorCode::OriginRejected,
            "Cloudflare request escaped its pinned origin",
        ));
    }
    Ok(url)
}

fn decode_api_response(
    method: CloudflareHttpMethod,
    response: super::CloudflareTransportResponse,
) -> DevkitResult<CloudflareApiResult> {
    let status = response.status();
    if (300..400).contains(&status) {
        return Err(DevkitError::new(
            DevkitErrorCode::RedirectRejected,
            "Cloudflare API redirects are not permitted",
        )
        .with_remote_mutation_risk(if method.is_mutating() {
            RemoteMutationRisk::Possible
        } else {
            RemoteMutationRisk::None
        }));
    }
    if status == 429 {
        let retry_after_ms = response
            .header("retry-after")
            .and_then(|value| value.parse::<u64>().ok())
            .map(|seconds| seconds.saturating_mul(1_000).min(86_400_000))
            .unwrap_or(1_000);
        return Err(DevkitError::new(
            DevkitErrorCode::RateLimited,
            "Cloudflare API rate limit was reached",
        )
        .retry_after(retry_after_ms));
    }
    if status == 404 {
        return Err(DevkitError::new(
            DevkitErrorCode::NotFound,
            "Cloudflare resource was not found",
        ));
    }
    if status == 401 || status == 403 {
        return Err(DevkitError::new(
            DevkitErrorCode::PermissionInsufficient,
            "Cloudflare authorization was rejected",
        ));
    }
    if !(200..300).contains(&status) {
        return Err(DevkitError::new(
            DevkitErrorCode::Unavailable,
            format!("Cloudflare API returned HTTP {status}"),
        )
        .with_remote_mutation_risk(if method.is_mutating() {
            RemoteMutationRisk::Possible
        } else {
            RemoteMutationRisk::None
        }));
    }
    if response.body().len() > MAX_API_RESPONSE_BYTES {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare API response exceeds the size limit",
        ));
    }
    let envelope: Value = serde_json::from_slice(response.body()).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare API returned an invalid response",
        )
    })?;
    if envelope.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare API rejected the request",
        )
        .with_remote_mutation_risk(if method.is_mutating() {
            RemoteMutationRisk::Possible
        } else {
            RemoteMutationRisk::None
        }));
    }
    Ok(CloudflareApiResult {
        value: envelope.get("result").cloned().unwrap_or(Value::Null),
        etag: response.header("etag").map(str::to_owned),
    })
}
