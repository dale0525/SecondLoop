use crate::{
    EntitlementProviderConfigurationError, HTTP_ENTITLEMENT_PROVIDER_ID, valid_opaque_reference,
};
use agent_runtime::entitlement::{
    EntitlementCommitRequest, EntitlementProvider, EntitlementProviderError,
    EntitlementProviderErrorCode, EntitlementReleaseRequest, EntitlementReservationDecision,
    EntitlementReservationRequest, EntitlementSettlementReceipt, EntitlementSettlementState,
};
use agent_runtime::identity::SecurityContext;
use async_trait::async_trait;
use chrono::{Duration as ChronoDuration, Utc};
use futures_util::StreamExt;
use reqwest::header::{
    ACCEPT, AUTHORIZATION, CONTENT_LENGTH, CONTENT_TYPE, HeaderValue, USER_AGENT,
};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use sha2::{Digest, Sha256};
use std::fmt;
use std::sync::Arc;
use std::time::Duration;
use url::{Host, Url};
use zeroize::Zeroize;

const HTTP_PROTOCOL_SCHEMA_VERSION: u32 = 1;
const MAX_REQUEST_BYTES: usize = 256 * 1024;
const MAX_CLOCK_SKEW_SECONDS: i64 = 300;

fn default_timeout_milliseconds() -> u64 {
    10_000
}

fn default_max_response_bytes() -> usize {
    64 * 1024
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HttpEntitlementConfig {
    pub base_url: String,
    /// Opaque reference resolved by the host vault. This is never a credential value.
    pub service_secret_id: String,
    #[serde(default = "default_timeout_milliseconds")]
    pub timeout_milliseconds: u64,
    #[serde(default = "default_max_response_bytes")]
    pub max_response_bytes: usize,
}

impl HttpEntitlementConfig {
    pub fn validate(&self) -> Result<(), EntitlementProviderConfigurationError> {
        validate_origin(&self.base_url)?;
        if !(100..=60_000).contains(&self.timeout_milliseconds) {
            return Err(EntitlementProviderConfigurationError::InvalidHttpTimeout);
        }
        if !(256..=1024 * 1024).contains(&self.max_response_bytes) {
            return Err(EntitlementProviderConfigurationError::InvalidHttpResponseLimit);
        }
        if !valid_opaque_reference(&self.service_secret_id) {
            return Err(EntitlementProviderConfigurationError::InvalidSecretReference);
        }
        Ok(())
    }
}

/// Short-lived secret material obtained from a host-owned vault.
///
/// Debug output is always redacted and the backing bytes are zeroized on drop.
pub struct ServiceSecret {
    bytes: Vec<u8>,
}

impl ServiceSecret {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Result<Self, ServiceSecretError> {
        let bytes = bytes.into();
        if bytes.is_empty() || bytes.len() > 8192 {
            return Err(ServiceSecretError);
        }
        Ok(Self { bytes })
    }

    /// Deliberate exposure boundary for a trusted transport implementation.
    pub fn with_exposed_bytes<T>(&self, use_secret: impl FnOnce(&[u8]) -> T) -> T {
        use_secret(&self.bytes)
    }
}

impl fmt::Debug for ServiceSecret {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("ServiceSecret(<redacted>)")
    }
}

impl Drop for ServiceSecret {
    fn drop(&mut self) {
        self.bytes.zeroize();
    }
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
#[error("service secret material is invalid")]
pub struct ServiceSecretError;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ServiceSecretResolveErrorCode {
    NotFound,
    Unavailable,
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
#[error("service secret resolution failed: {code:?}")]
pub struct ServiceSecretResolveError {
    pub code: ServiceSecretResolveErrorCode,
}

impl ServiceSecretResolveError {
    pub fn new(code: ServiceSecretResolveErrorCode) -> Self {
        Self { code }
    }
}

#[async_trait]
pub trait ServiceSecretResolver: Send + Sync {
    async fn resolve(&self, secret_id: &str) -> Result<ServiceSecret, ServiceSecretResolveError>;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HttpEntitlementOperation {
    Reserve,
    Commit,
    Release,
}

impl HttpEntitlementOperation {
    fn path(self) -> &'static str {
        match self {
            Self::Reserve => "agentweave/entitlements/v1/reserve",
            Self::Commit => "agentweave/entitlements/v1/commit",
            Self::Release => "agentweave/entitlements/v1/release",
        }
    }

    fn idempotency_domain(self) -> &'static str {
        match self {
            Self::Reserve => "reserve",
            Self::Commit => "commit",
            Self::Release => "release",
        }
    }
}

pub struct HttpEntitlementTransportRequest {
    operation: HttpEntitlementOperation,
    endpoint: Url,
    idempotency_key: String,
    body: Vec<u8>,
    service_secret: ServiceSecret,
    timeout: Duration,
    max_response_bytes: usize,
}

impl HttpEntitlementTransportRequest {
    pub fn operation(&self) -> HttpEntitlementOperation {
        self.operation
    }

    pub fn endpoint(&self) -> &Url {
        &self.endpoint
    }

    pub fn idempotency_key(&self) -> &str {
        &self.idempotency_key
    }

    pub fn body(&self) -> &[u8] {
        &self.body
    }

    pub fn timeout(&self) -> Duration {
        self.timeout
    }

    pub fn max_response_bytes(&self) -> usize {
        self.max_response_bytes
    }

    pub fn with_service_secret<T>(&self, use_secret: impl FnOnce(&[u8]) -> T) -> T {
        self.service_secret.with_exposed_bytes(use_secret)
    }
}

impl fmt::Debug for HttpEntitlementTransportRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpEntitlementTransportRequest")
            .field("operation", &self.operation)
            .field("endpoint", &self.endpoint)
            .field("idempotency_key", &self.idempotency_key)
            .field("body_bytes", &self.body.len())
            .field("service_secret", &"<redacted>")
            .field("timeout", &self.timeout)
            .field("max_response_bytes", &self.max_response_bytes)
            .finish()
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct HttpEntitlementTransportResponse {
    pub status: u16,
    pub final_url: Url,
    pub content_type: Option<String>,
    pub body: Vec<u8>,
}

impl fmt::Debug for HttpEntitlementTransportResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpEntitlementTransportResponse")
            .field("status", &self.status)
            .field("final_url", &self.final_url)
            .field("content_type", &self.content_type)
            .field("body_bytes", &self.body.len())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HttpEntitlementTransportErrorCode {
    Timeout,
    Connection,
    ResponseTooLarge,
    InvalidCredential,
    Protocol,
}

#[derive(Clone, Copy, Debug, thiserror::Error, PartialEq, Eq)]
#[error("HTTP entitlement transport failed: {code:?}")]
pub struct HttpEntitlementTransportError {
    pub code: HttpEntitlementTransportErrorCode,
}

impl HttpEntitlementTransportError {
    pub fn new(code: HttpEntitlementTransportErrorCode) -> Self {
        Self { code }
    }
}

#[async_trait]
pub trait HttpEntitlementTransport: Send + Sync {
    async fn execute(
        &self,
        request: HttpEntitlementTransportRequest,
    ) -> Result<HttpEntitlementTransportResponse, HttpEntitlementTransportError>;
}

pub struct ReqwestEntitlementTransport {
    client: reqwest::Client,
}

impl ReqwestEntitlementTransport {
    pub fn new() -> Result<Self, HttpEntitlementTransportError> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| transport_error(HttpEntitlementTransportErrorCode::Protocol))?;
        Ok(Self { client })
    }
}

impl fmt::Debug for ReqwestEntitlementTransport {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ReqwestEntitlementTransport")
            .finish_non_exhaustive()
    }
}

#[async_trait]
impl HttpEntitlementTransport for ReqwestEntitlementTransport {
    async fn execute(
        &self,
        request: HttpEntitlementTransportRequest,
    ) -> Result<HttpEntitlementTransportResponse, HttpEntitlementTransportError> {
        let authorization = request.with_service_secret(|secret| {
            let mut value = Vec::with_capacity(7 + secret.len());
            value.extend_from_slice(b"Bearer ");
            value.extend_from_slice(secret);
            HeaderValue::from_bytes(&value)
        });
        let authorization = authorization
            .map_err(|_| transport_error(HttpEntitlementTransportErrorCode::InvalidCredential))?;
        let response = self
            .client
            .post(request.endpoint.clone())
            .timeout(request.timeout)
            .header(AUTHORIZATION, authorization)
            .header(CONTENT_TYPE, "application/json")
            .header(ACCEPT, "application/json")
            .header(USER_AGENT, "agentweave-entitlement-provider/1")
            .header("Idempotency-Key", &request.idempotency_key)
            .body(request.body)
            .send()
            .await
            .map_err(map_reqwest_error)?;
        if response
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<usize>().ok())
            .is_some_and(|length| length > request.max_response_bytes)
        {
            return Err(transport_error(
                HttpEntitlementTransportErrorCode::ResponseTooLarge,
            ));
        }
        let status = response.status().as_u16();
        let final_url = response.url().clone();
        let content_type = response
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned);
        let mut body = Vec::new();
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(map_reqwest_error)?;
            let next_len = body.len().checked_add(chunk.len()).ok_or_else(|| {
                transport_error(HttpEntitlementTransportErrorCode::ResponseTooLarge)
            })?;
            if next_len > request.max_response_bytes {
                return Err(transport_error(
                    HttpEntitlementTransportErrorCode::ResponseTooLarge,
                ));
            }
            body.extend_from_slice(&chunk);
        }
        Ok(HttpEntitlementTransportResponse {
            status,
            final_url,
            content_type,
            body,
        })
    }
}

#[derive(Clone)]
pub struct HttpEntitlementProvider {
    config: HttpEntitlementConfig,
    origin: Url,
    secret_resolver: Arc<dyn ServiceSecretResolver>,
    transport: Arc<dyn HttpEntitlementTransport>,
}

impl fmt::Debug for HttpEntitlementProvider {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpEntitlementProvider")
            .field("config", &self.config)
            .field("origin", &self.origin)
            .field("secret_resolver", &"<opaque>")
            .field("transport", &"<opaque>")
            .finish()
    }
}

impl HttpEntitlementProvider {
    pub fn new(
        config: HttpEntitlementConfig,
        secret_resolver: Arc<dyn ServiceSecretResolver>,
        transport: Arc<dyn HttpEntitlementTransport>,
    ) -> Result<Self, EntitlementProviderConfigurationError> {
        config.validate()?;
        let origin = validate_origin(&config.base_url)?;
        Ok(Self {
            config,
            origin,
            secret_resolver,
            transport,
        })
    }

    pub fn with_reqwest_transport(
        config: HttpEntitlementConfig,
        secret_resolver: Arc<dyn ServiceSecretResolver>,
    ) -> Result<Self, EntitlementProviderConfigurationError> {
        let transport = ReqwestEntitlementTransport::new().map_err(|_| {
            EntitlementProviderConfigurationError::HttpTransportInitializationFailed
        })?;
        Self::new(config, secret_resolver, Arc::new(transport))
    }

    async fn execute<T: DeserializeOwned>(
        &self,
        operation: HttpEntitlementOperation,
        raw_idempotency_key: &str,
        body: Vec<u8>,
    ) -> Result<T, EntitlementProviderError> {
        if body.len() > MAX_REQUEST_BYTES {
            return Err(provider_error(EntitlementProviderErrorCode::InvalidRequest));
        }
        let endpoint = self
            .origin
            .join(operation.path())
            .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        if endpoint.origin() != self.origin.origin() {
            return Err(provider_error(EntitlementProviderErrorCode::InvalidRequest));
        }
        let secret = self
            .secret_resolver
            .resolve(&self.config.service_secret_id)
            .await
            .map_err(|_| provider_error(EntitlementProviderErrorCode::Unavailable))?;
        let request = HttpEntitlementTransportRequest {
            operation,
            endpoint: endpoint.clone(),
            idempotency_key: digest_idempotency_key(operation, raw_idempotency_key),
            body,
            service_secret: secret,
            timeout: Duration::from_millis(self.config.timeout_milliseconds),
            max_response_bytes: self.config.max_response_bytes,
        };
        let response = tokio::time::timeout(request.timeout(), self.transport.execute(request))
            .await
            .map_err(|_| provider_error(EntitlementProviderErrorCode::Unavailable))?
            .map_err(map_transport_error)?;
        parse_response(response, &endpoint, self.config.max_response_bytes)
    }
}

#[async_trait]
impl EntitlementProvider for HttpEntitlementProvider {
    fn provider_id(&self) -> &str {
        HTTP_ENTITLEMENT_PROVIDER_ID
    }

    async fn reserve(
        &self,
        context: &SecurityContext,
        request: &EntitlementReservationRequest,
    ) -> Result<EntitlementReservationDecision, EntitlementProviderError> {
        validate_context(context)?;
        request
            .validate()
            .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        let body = serde_json::to_vec(&ReserveWireRequest {
            schema_version: HTTP_PROTOCOL_SCHEMA_VERSION,
            context,
            request,
        })
        .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        let response: ReserveWireResponse = self
            .execute(
                HttpEntitlementOperation::Reserve,
                &request.idempotency_key,
                body,
            )
            .await?;
        if response.schema_version != HTTP_PROTOCOL_SCHEMA_VERSION {
            return Err(provider_error(
                EntitlementProviderErrorCode::InvalidResponse,
            ));
        }
        validate_reserve_response(context, request, &response.decision)?;
        Ok(response.decision)
    }

    async fn commit(
        &self,
        context: &SecurityContext,
        request: &EntitlementCommitRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
        validate_context(context)?;
        validate_commit_shape(request)?;
        let body = serde_json::to_vec(&CommitWireRequest {
            schema_version: HTTP_PROTOCOL_SCHEMA_VERSION,
            context,
            request,
        })
        .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        let response: SettlementWireResponse = self
            .execute(
                HttpEntitlementOperation::Commit,
                &request.settlement_id,
                body,
            )
            .await?;
        validate_settlement_response(
            response,
            request.reservation_id.as_str(),
            request.settlement_id.as_str(),
            EntitlementSettlementState::Committed,
            Some(&request.actual_usage),
        )
    }

    async fn release(
        &self,
        context: &SecurityContext,
        request: &EntitlementReleaseRequest,
    ) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
        validate_context(context)?;
        if !valid_settlement_field(&request.reservation_id)
            || !valid_settlement_field(&request.release_id)
        {
            return Err(provider_error(EntitlementProviderErrorCode::InvalidRequest));
        }
        let body = serde_json::to_vec(&ReleaseWireRequest {
            schema_version: HTTP_PROTOCOL_SCHEMA_VERSION,
            context,
            request,
        })
        .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidRequest))?;
        let response: SettlementWireResponse = self
            .execute(HttpEntitlementOperation::Release, &request.release_id, body)
            .await?;
        validate_settlement_response(
            response,
            request.reservation_id.as_str(),
            request.release_id.as_str(),
            EntitlementSettlementState::Released,
            None,
        )
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReserveWireRequest<'a> {
    schema_version: u32,
    context: &'a SecurityContext,
    request: &'a EntitlementReservationRequest,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CommitWireRequest<'a> {
    schema_version: u32,
    context: &'a SecurityContext,
    request: &'a EntitlementCommitRequest,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReleaseWireRequest<'a> {
    schema_version: u32,
    context: &'a SecurityContext,
    request: &'a EntitlementReleaseRequest,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ReserveWireResponse {
    schema_version: u32,
    decision: EntitlementReservationDecision,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SettlementWireResponse {
    schema_version: u32,
    receipt: EntitlementSettlementReceipt,
}

fn parse_response<T: DeserializeOwned>(
    response: HttpEntitlementTransportResponse,
    endpoint: &Url,
    maximum_bytes: usize,
) -> Result<T, EntitlementProviderError> {
    if &response.final_url != endpoint
        || response.body.len() > maximum_bytes
        || !response
            .content_type
            .as_deref()
            .is_some_and(is_json_content_type)
    {
        return Err(provider_error(
            EntitlementProviderErrorCode::InvalidResponse,
        ));
    }
    if response.status != 200 {
        return Err(provider_error(match response.status {
            400 | 422 => EntitlementProviderErrorCode::InvalidRequest,
            409 => EntitlementProviderErrorCode::Conflict,
            410 => EntitlementProviderErrorCode::ReservationExpired,
            _ => EntitlementProviderErrorCode::Unavailable,
        }));
    }
    serde_json::from_slice(&response.body)
        .map_err(|_| provider_error(EntitlementProviderErrorCode::InvalidResponse))
}

fn validate_reserve_response(
    context: &SecurityContext,
    request: &EntitlementReservationRequest,
    decision: &EntitlementReservationDecision,
) -> Result<(), EntitlementProviderError> {
    let now = Utc::now();
    let valid = match decision {
        EntitlementReservationDecision::Granted(reservation) => reservation
            .validate_for(HTTP_ENTITLEMENT_PROVIDER_ID, context, request, now)
            .is_ok(),
        EntitlementReservationDecision::Denied(denial) => {
            denial.provider_id == HTTP_ENTITLEMENT_PROVIDER_ID
                && denial.operation_id == request.operation_id
                && denial.idempotency_key == request.idempotency_key
                && denial.resource == request.resource
                && denial
                    .retry_after
                    .is_none_or(|retry_after| retry_after > now)
        }
    };
    if valid {
        Ok(())
    } else {
        Err(provider_error(
            EntitlementProviderErrorCode::InvalidResponse,
        ))
    }
}

fn validate_settlement_response(
    response: SettlementWireResponse,
    reservation_id: &str,
    settlement_id: &str,
    state: EntitlementSettlementState,
    charged_usage: Option<&agent_runtime::entitlement::UsageUnits>,
) -> Result<EntitlementSettlementReceipt, EntitlementProviderError> {
    let receipt = response.receipt;
    if response.schema_version != HTTP_PROTOCOL_SCHEMA_VERSION
        || receipt.provider_id != HTTP_ENTITLEMENT_PROVIDER_ID
        || receipt.reservation_id != reservation_id
        || receipt.settlement_id != settlement_id
        || receipt.state != state
        || receipt.charged_usage.as_ref() != charged_usage
        || receipt.processed_at > Utc::now() + ChronoDuration::seconds(MAX_CLOCK_SKEW_SECONDS)
    {
        return Err(provider_error(
            EntitlementProviderErrorCode::InvalidResponse,
        ));
    }
    Ok(receipt)
}

fn validate_commit_shape(
    request: &EntitlementCommitRequest,
) -> Result<(), EntitlementProviderError> {
    if !valid_settlement_field(&request.reservation_id)
        || !valid_settlement_field(&request.settlement_id)
        || request.actual_usage.validate().is_err()
    {
        return Err(provider_error(EntitlementProviderErrorCode::InvalidRequest));
    }
    Ok(())
}

fn validate_context(context: &SecurityContext) -> Result<(), EntitlementProviderError> {
    let now = Utc::now();
    if context.validate().is_err()
        || context.expires_at <= now
        || context.authenticated_at > now + ChronoDuration::seconds(MAX_CLOCK_SKEW_SECONDS)
    {
        return Err(provider_error(EntitlementProviderErrorCode::InvalidRequest));
    }
    Ok(())
}

fn validate_origin(value: &str) -> Result<Url, EntitlementProviderConfigurationError> {
    let url =
        Url::parse(value).map_err(|_| EntitlementProviderConfigurationError::InvalidHttpOrigin)?;
    let is_loopback_http = url.scheme() == "http" && url.host().is_some_and(host_is_loopback);
    let valid = (url.scheme() == "https" || is_loopback_http)
        && url.host().is_some()
        && url.username().is_empty()
        && url.password().is_none()
        && url.path() == "/"
        && url.query().is_none()
        && url.fragment().is_none();
    if valid {
        Ok(url)
    } else {
        Err(EntitlementProviderConfigurationError::InvalidHttpOrigin)
    }
}

fn host_is_loopback(host: Host<&str>) -> bool {
    match host {
        Host::Domain(domain) => domain.eq_ignore_ascii_case("localhost"),
        Host::Ipv4(address) => address.is_loopback(),
        Host::Ipv6(address) => address.is_loopback(),
    }
}

fn is_json_content_type(value: &str) -> bool {
    value
        .split(';')
        .next()
        .is_some_and(|media_type| media_type.trim().eq_ignore_ascii_case("application/json"))
}

fn digest_idempotency_key(operation: HttpEntitlementOperation, value: &str) -> String {
    let mut digest = Sha256::new();
    digest.update(operation.idempotency_domain().as_bytes());
    digest.update([0]);
    digest.update(value.as_bytes());
    format!("v1-{}", hex::encode(digest.finalize()))
}

fn valid_settlement_field(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 2048
        && value == value.trim()
        && !value.chars().any(char::is_control)
}

fn map_reqwest_error(error: reqwest::Error) -> HttpEntitlementTransportError {
    if error.is_timeout() {
        transport_error(HttpEntitlementTransportErrorCode::Timeout)
    } else {
        transport_error(HttpEntitlementTransportErrorCode::Connection)
    }
}

fn map_transport_error(error: HttpEntitlementTransportError) -> EntitlementProviderError {
    let code = match error.code {
        HttpEntitlementTransportErrorCode::ResponseTooLarge
        | HttpEntitlementTransportErrorCode::Protocol => {
            EntitlementProviderErrorCode::InvalidResponse
        }
        HttpEntitlementTransportErrorCode::Timeout
        | HttpEntitlementTransportErrorCode::Connection
        | HttpEntitlementTransportErrorCode::InvalidCredential => {
            EntitlementProviderErrorCode::Unavailable
        }
    };
    provider_error(code)
}

fn transport_error(code: HttpEntitlementTransportErrorCode) -> HttpEntitlementTransportError {
    HttpEntitlementTransportError::new(code)
}

fn provider_error(code: EntitlementProviderErrorCode) -> EntitlementProviderError {
    EntitlementProviderError::new(code)
}
