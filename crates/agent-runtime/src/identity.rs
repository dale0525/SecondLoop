use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use thiserror::Error;
use url::{Host, Url};

pub const SECURITY_CONTEXT_SCHEMA_VERSION: u32 = 1;

const MAX_IDENTIFIER_BYTES: usize = 255;
const MAX_OPAQUE_VALUE_BYTES: usize = 2048;
const MAX_SCOPES: usize = 128;
const MAX_CLOCK_SKEW_SECONDS: i64 = 300;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum IdentityMode {
    LocalSingleUser,
    Required,
}

/// A stable principal key. Neither field is an authorization credential.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PrincipalIdentity {
    pub issuer: String,
    pub subject: String,
}

impl PrincipalIdentity {
    pub fn validate(&self) -> Result<(), IdentityContractError> {
        validate_issuer(&self.issuer)?;
        validate_opaque(&self.subject, "subject", MAX_OPAQUE_VALUE_BYTES)
    }
}

/// The non-secret requirements for the current authenticated principal.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SecurityContextRequest {
    pub app_id: String,
    pub tenant_id: String,
    pub audience: String,
    #[serde(default)]
    pub required_scopes: BTreeSet<String>,
}

impl SecurityContextRequest {
    pub fn validate(&self) -> Result<(), IdentityContractError> {
        validate_identifier(&self.app_id, "app_id")?;
        validate_identifier(&self.tenant_id, "tenant_id")?;
        validate_opaque(&self.audience, "audience", MAX_OPAQUE_VALUE_BYTES)?;
        validate_scopes(&self.required_scopes)
    }
}

/// Verified identity metadata safe to persist or pass across a host boundary.
///
/// Authentication proofs, access tokens, refresh tokens, cookies, and other
/// bearer material deliberately have no representation in this type. A host
/// implementation must keep those values inside its identity plugin.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SecurityContext {
    pub schema_version: u32,
    pub provider_id: String,
    pub app_id: String,
    pub tenant_id: String,
    pub audience: String,
    pub principal: PrincipalIdentity,
    #[serde(default)]
    pub granted_scopes: BTreeSet<String>,
    pub authenticated_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

impl SecurityContext {
    pub fn validate(&self) -> Result<(), IdentityContractError> {
        if self.schema_version != SECURITY_CONTEXT_SCHEMA_VERSION {
            return Err(IdentityContractError::UnsupportedSchemaVersion);
        }
        validate_identifier(&self.provider_id, "provider_id")?;
        validate_identifier(&self.app_id, "app_id")?;
        validate_identifier(&self.tenant_id, "tenant_id")?;
        validate_opaque(&self.audience, "audience", MAX_OPAQUE_VALUE_BYTES)?;
        self.principal.validate()?;
        validate_scopes(&self.granted_scopes)?;
        if self.expires_at <= self.authenticated_at {
            return Err(IdentityContractError::InvalidLifetime);
        }
        Ok(())
    }

    pub fn validate_for(
        &self,
        provider_id: &str,
        request: &SecurityContextRequest,
        now: DateTime<Utc>,
    ) -> Result<(), IdentityContractError> {
        validate_identifier(provider_id, "provider_id")?;
        request.validate()?;
        self.validate()?;
        if self.provider_id != provider_id {
            return Err(IdentityContractError::ContextMismatch("provider_id"));
        }
        if self.app_id != request.app_id {
            return Err(IdentityContractError::ContextMismatch("app_id"));
        }
        if self.tenant_id != request.tenant_id {
            return Err(IdentityContractError::ContextMismatch("tenant_id"));
        }
        if self.audience != request.audience {
            return Err(IdentityContractError::ContextMismatch("audience"));
        }
        if self.authenticated_at > now + Duration::seconds(MAX_CLOCK_SKEW_SECONDS) {
            return Err(IdentityContractError::NotYetValid);
        }
        if self.expires_at <= now {
            return Err(IdentityContractError::Expired);
        }
        if let Some(scope) = request
            .required_scopes
            .iter()
            .find(|scope| !self.granted_scopes.contains(*scope))
        {
            return Err(IdentityContractError::MissingScope(scope.clone()));
        }
        Ok(())
    }

    pub fn is_expired_at(&self, now: DateTime<Utc>) -> bool {
        self.expires_at <= now
    }

    pub fn scoped_user_id(&self) -> Result<String, IdentityContractError> {
        self.validate()?;
        derive_scoped_user_id(
            &self.app_id,
            &self.tenant_id,
            &self.provider_id,
            &self.principal,
        )
    }
}

/// Derives a stable, opaque local partition key from verified identity facts.
/// Display names and email addresses deliberately do not participate.
pub fn derive_scoped_user_id(
    app_id: &str,
    tenant_id: &str,
    provider_id: &str,
    principal: &PrincipalIdentity,
) -> Result<String, IdentityContractError> {
    validate_identifier(app_id, "app_id")?;
    validate_identifier(tenant_id, "tenant_id")?;
    validate_identifier(provider_id, "provider_id")?;
    principal.validate()?;
    let mut digest = Sha256::new();
    digest.update(b"agentweave.identity.account.v1\0");
    for value in [
        app_id,
        tenant_id,
        provider_id,
        principal.issuer.as_str(),
        principal.subject.as_str(),
    ] {
        digest.update((value.len() as u64).to_be_bytes());
        digest.update(value.as_bytes());
    }
    Ok(format!("usr_{}", hex::encode(digest.finalize())))
}

#[derive(Clone, Debug, Error, PartialEq, Eq)]
pub enum IdentityContractError {
    #[error("invalid identity field: {0}")]
    InvalidField(&'static str),
    #[error("unsupported security context schema version")]
    UnsupportedSchemaVersion,
    #[error("security context lifetime is invalid")]
    InvalidLifetime,
    #[error("security context does not match request field: {0}")]
    ContextMismatch(&'static str),
    #[error("security context is not yet valid")]
    NotYetValid,
    #[error("security context has expired")]
    Expired,
    #[error("security context is missing required scope: {0}")]
    MissingScope(String),
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum IdentityProviderErrorCode {
    AuthenticationRequired,
    AccessDenied,
    InvalidRequest,
    InvalidResponse,
    Unavailable,
}

#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
#[error("identity provider operation failed: {code:?}")]
pub struct IdentityProviderError {
    pub code: IdentityProviderErrorCode,
}

impl IdentityProviderError {
    pub fn new(code: IdentityProviderErrorCode) -> Self {
        Self { code }
    }
}

/// Resolves identity from provider-owned session state without exposing its
/// credentials to the runtime contract.
#[async_trait]
pub trait IdentityProvider: Send + Sync {
    fn provider_id(&self) -> &str;

    async fn security_context(
        &self,
        request: &SecurityContextRequest,
    ) -> Result<SecurityContext, IdentityProviderError>;
}

/// Resolves and validates a provider response before it enters runtime state.
pub async fn resolve_security_context(
    provider: &dyn IdentityProvider,
    request: &SecurityContextRequest,
    now: DateTime<Utc>,
) -> Result<SecurityContext, IdentityProviderError> {
    request
        .validate()
        .map_err(|_| IdentityProviderError::new(IdentityProviderErrorCode::InvalidRequest))?;
    validate_identifier(provider.provider_id(), "provider_id")
        .map_err(|_| IdentityProviderError::new(IdentityProviderErrorCode::InvalidResponse))?;
    let context = provider.security_context(request).await?;
    context
        .validate_for(provider.provider_id(), request, now)
        .map_err(|_| IdentityProviderError::new(IdentityProviderErrorCode::InvalidResponse))?;
    Ok(context)
}

fn validate_identifier(value: &str, field: &'static str) -> Result<(), IdentityContractError> {
    let valid = !value.is_empty()
        && value.len() <= MAX_IDENTIFIER_BYTES
        && value == value.trim()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'));
    if valid {
        Ok(())
    } else {
        Err(IdentityContractError::InvalidField(field))
    }
}

fn validate_opaque(
    value: &str,
    field: &'static str,
    maximum_bytes: usize,
) -> Result<(), IdentityContractError> {
    let valid = !value.is_empty()
        && value.len() <= maximum_bytes
        && value == value.trim()
        && !value.chars().any(char::is_control);
    if valid {
        Ok(())
    } else {
        Err(IdentityContractError::InvalidField(field))
    }
}

fn validate_issuer(value: &str) -> Result<(), IdentityContractError> {
    validate_opaque(value, "issuer", MAX_OPAQUE_VALUE_BYTES)?;
    let url = Url::parse(value).map_err(|_| IdentityContractError::InvalidField("issuer"))?;
    if url.query().is_some() || url.fragment().is_some() {
        return Err(IdentityContractError::InvalidField("issuer"));
    }
    let secure_web_issuer = url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && url.host().is_some();
    let loopback_development_issuer = url.scheme() == "http"
        && url.username().is_empty()
        && url.password().is_none()
        && url.host().is_some_and(host_is_loopback);
    let namespaced_issuer = url.scheme() == "urn";
    if secure_web_issuer || loopback_development_issuer || namespaced_issuer {
        Ok(())
    } else {
        Err(IdentityContractError::InvalidField("issuer"))
    }
}

fn host_is_loopback(host: Host<&str>) -> bool {
    match host {
        Host::Domain(domain) => domain.eq_ignore_ascii_case("localhost"),
        Host::Ipv4(address) => address.is_loopback(),
        Host::Ipv6(address) => address.is_loopback(),
    }
}

fn validate_scopes(scopes: &BTreeSet<String>) -> Result<(), IdentityContractError> {
    if scopes.len() > MAX_SCOPES {
        return Err(IdentityContractError::InvalidField("scopes"));
    }
    for scope in scopes {
        validate_opaque(scope, "scope", MAX_IDENTIFIER_BYTES)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 7, 19, 8, 0, 0).unwrap()
    }

    fn request() -> SecurityContextRequest {
        SecurityContextRequest {
            app_id: "com.example.agent".into(),
            tenant_id: "tenant-1".into(),
            audience: "https://gateway.example.com".into(),
            required_scopes: BTreeSet::from(["model.invoke".into()]),
        }
    }

    fn context() -> SecurityContext {
        SecurityContext {
            schema_version: SECURITY_CONTEXT_SCHEMA_VERSION,
            provider_id: "com.example.identity".into(),
            app_id: "com.example.agent".into(),
            tenant_id: "tenant-1".into(),
            audience: "https://gateway.example.com".into(),
            principal: PrincipalIdentity {
                issuer: "https://identity.example.com".into(),
                subject: "user-42".into(),
            },
            granted_scopes: BTreeSet::from(["model.invoke".into(), "profile.read".into()]),
            authenticated_at: now() - Duration::minutes(5),
            expires_at: now() + Duration::hours(1),
        }
    }

    #[test]
    fn validates_a_context_bound_to_the_exact_request() {
        let context = context();

        assert!(
            context
                .validate_for("com.example.identity", &request(), now())
                .is_ok()
        );
    }

    #[test]
    fn rejects_context_rebinding_and_missing_scopes() {
        let mut mismatched = context();
        mismatched.audience = "https://other.example.com".into();
        assert_eq!(
            mismatched
                .validate_for("com.example.identity", &request(), now())
                .unwrap_err(),
            IdentityContractError::ContextMismatch("audience")
        );

        let mut missing_scope = context();
        missing_scope.granted_scopes.clear();
        assert_eq!(
            missing_scope
                .validate_for("com.example.identity", &request(), now())
                .unwrap_err(),
            IdentityContractError::MissingScope("model.invoke".into())
        );
    }

    #[test]
    fn rejects_expired_future_and_invalid_lifetimes() {
        let mut expired = context();
        expired.expires_at = now();
        assert_eq!(
            expired
                .validate_for("com.example.identity", &request(), now())
                .unwrap_err(),
            IdentityContractError::Expired
        );

        let mut future = context();
        future.authenticated_at = now() + Duration::minutes(6);
        future.expires_at = now() + Duration::hours(1);
        assert_eq!(
            future
                .validate_for("com.example.identity", &request(), now())
                .unwrap_err(),
            IdentityContractError::NotYetValid
        );

        let mut inverted = context();
        inverted.expires_at = inverted.authenticated_at;
        assert_eq!(
            inverted.validate().unwrap_err(),
            IdentityContractError::InvalidLifetime
        );
    }

    #[test]
    fn issuer_requires_https_urn_or_loopback_http() {
        for issuer in [
            "https://identity.example.com",
            "urn:example:identity",
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://[::1]:8080",
        ] {
            assert!(
                PrincipalIdentity {
                    issuer: issuer.into(),
                    subject: "user-42".into(),
                }
                .validate()
                .is_ok(),
                "expected {issuer} to be accepted"
            );
        }

        for issuer in [
            "http://identity.example.com",
            "https://user:password@identity.example.com",
            "https://identity.example.com?token=value",
        ] {
            assert_eq!(
                PrincipalIdentity {
                    issuer: issuer.into(),
                    subject: "user-42".into(),
                }
                .validate()
                .unwrap_err(),
                IdentityContractError::InvalidField("issuer")
            );
        }
    }

    #[test]
    fn serialized_contract_has_no_place_for_bearer_secrets() {
        let encoded = serde_json::to_value(context()).unwrap();
        let object = encoded.as_object().unwrap();

        for forbidden in [
            "accessToken",
            "refreshToken",
            "authorization",
            "cookie",
            "credential",
        ] {
            assert!(!object.contains_key(forbidden));
        }

        let mut with_token = encoded;
        with_token["accessToken"] = serde_json::json!("secret-sentinel");
        assert!(serde_json::from_value::<SecurityContext>(with_token).is_err());
    }

    #[test]
    fn scoped_user_ids_are_stable_opaque_and_bound_to_every_authority_dimension() {
        let context = context();
        let id = context.scoped_user_id().unwrap();

        assert_eq!(id, context.scoped_user_id().unwrap());
        assert!(id.starts_with("usr_"));
        assert!(!id.contains("user-42"));
        for changed in [
            SecurityContext {
                app_id: "com.example.other".into(),
                ..context.clone()
            },
            SecurityContext {
                tenant_id: "tenant-2".into(),
                ..context.clone()
            },
            SecurityContext {
                provider_id: "com.example.other-idp".into(),
                ..context.clone()
            },
            SecurityContext {
                principal: PrincipalIdentity {
                    subject: "user-43".into(),
                    ..context.principal.clone()
                },
                ..context.clone()
            },
        ] {
            assert_ne!(id, changed.scoped_user_id().unwrap());
        }
    }

    struct StaticIdentityProvider {
        context: SecurityContext,
    }

    #[async_trait]
    impl IdentityProvider for StaticIdentityProvider {
        fn provider_id(&self) -> &str {
            "com.example.identity"
        }

        async fn security_context(
            &self,
            _request: &SecurityContextRequest,
        ) -> Result<SecurityContext, IdentityProviderError> {
            Ok(self.context.clone())
        }
    }

    #[tokio::test]
    async fn validated_resolver_accepts_only_provider_bound_responses() {
        let valid = StaticIdentityProvider { context: context() };
        assert!(
            resolve_security_context(&valid, &request(), now())
                .await
                .is_ok()
        );

        let mut wrong_app = context();
        wrong_app.app_id = "com.example.other".into();
        let invalid = StaticIdentityProvider { context: wrong_app };
        assert_eq!(
            resolve_security_context(&invalid, &request(), now())
                .await
                .unwrap_err(),
            IdentityProviderError::new(IdentityProviderErrorCode::InvalidResponse)
        );
    }
}
